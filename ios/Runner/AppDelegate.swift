import Flutter
import Foundation
import GardendlessCore
import GardendlessImport
import GardendlessLogging
import UniformTypeIdentifiers
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let logStore: LogStore = {
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return LogStore(
      directory: support.appendingPathComponent(
        "GardendlessLoader/logs",
        isDirectory: true
      )
    )
  }()

  private var launcherEngine: FlutterEngine?
  private var gameHostChannel: FlutterMethodChannel?
  private var resourceZipImporterChannel: FlutterMethodChannel?
  private var lastImportProgressReportAt: UInt64 = 0
  private var pendingImportResult: FlutterResult?
  private var pendingImportTargetDirectory: String?
  private var zipImportInProgress = false
  private var gameLaunchInProgress = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
    logStore.initialize()
    showLauncher()
    return launched
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    logStore.endSession()
    super.applicationWillTerminate(application)
  }

  private func showLauncher() {
    if window == nil {
      window = UIWindow(frame: UIScreen.main.bounds)
    }
    let engine = FlutterEngine(name: "gardendless-launcher-\(UUID().uuidString)")
    guard engine.run() else { return }
    GeneratedPluginRegistrant.register(with: engine)
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    launcherEngine = engine
    window?.rootViewController = controller
    window?.makeKeyAndVisible()
    registerChannels(on: controller.binaryMessenger)
  }

  private func registerChannels(on messenger: FlutterBinaryMessenger) {
    registerExternalBrowser(on: messenger)
    registerGameHost(on: messenger)
    registerResourceZipImporter(on: messenger)
    registerAppLogger(on: messenger)
  }

  private func registerExternalBrowser(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "io.github.dey410.gardendlessloader/external_browser",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let raw = arguments["url"] as? String,
            let url = URL(string: raw),
            url.scheme == "https" || url.scheme == "http" else {
        result(
          FlutterError(
            code: "invalid_external_url",
            message: "Only HTTP(S) URLs are allowed",
            details: nil
          )
        )
        return
      }
      UIApplication.shared.open(url) { opened in
        if opened {
          result(nil)
        } else {
          result(
            FlutterError(
              code: "external_open_failed",
              message: "No application can open this URL",
              details: nil
            )
          )
        }
      }
    }
  }

  private func registerGameHost(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "io.github.dey410.gardendlessloader/game_host",
      binaryMessenger: messenger
    )
    gameHostChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "launch" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(
          FlutterError(
            code: "game_host_unavailable",
            message: "App delegate released",
            details: nil
          )
        )
        return
      }
      guard !self.gameLaunchInProgress else {
        result(
          FlutterError(
            code: "game_host_launch_busy",
            message: "Native GameHost is launching",
            details: nil
          )
        )
        return
      }
      do {
        let session = try GameSessionDecoder.decode(call.arguments)
        self.gameLaunchInProgress = true
        NetworkPolicy.load(for: session) { [weak self] policyResult in
          DispatchQueue.main.async {
            guard let self else {
              result(
                FlutterError(
                  code: "game_host_unavailable",
                  message: "App delegate released",
                  details: nil
                )
              )
              return
            }
            self.gameLaunchInProgress = false
            do {
              let policy = try policyResult.get()
              let gameController = try GameHostController(
                session: session,
                networkRuleList: policy,
                logStore: self.logStore
              ) { [weak self] in
                self?.showLauncher()
              }
              let engine = self.launcherEngine
              self.launcherEngine = nil
              self.resourceZipImporterChannel?.setMethodCallHandler(nil)
              self.gameHostChannel?.setMethodCallHandler(nil)
              result(nil)
              self.window?.rootViewController = gameController
              self.window?.makeKeyAndVisible()
              DispatchQueue.main.async {
                engine?.destroyContext()
              }
            } catch {
              result(
                FlutterError(
                  code: "game_host_launch_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      } catch {
        result(
          FlutterError(
            code: "game_host_launch_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func registerResourceZipImporter(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "io.github.dey410.gardendlessloader/resource_zip_importer",
      binaryMessenger: messenger
    )
    resourceZipImporterChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickAndExtractDocsZip" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.pickAndExtractDocsZip(call: call, result: result)
    }
  }

  private func registerAppLogger(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "io.github.dey410.gardendlessloader/app_logger",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "initialize":
        self.logStore.initialize()
        result(["appSessionId": self.logStore.appSessionId])
      case "emit":
        guard let event = call.arguments as? [String: Any] else {
          result(
            FlutterError(
              code: "invalid_log_event",
              message: "Log event must be a map",
              details: nil
            )
          )
          return
        }
        self.logStore.emit(event)
        result(nil)
      case "snapshot":
        let limit = (call.arguments as? [String: Any])?["limit"] as? Int ?? 500
        result(self.logStore.snapshot(limit: limit))
      case "flush":
        _ = self.logStore.flush(timeout: 0.5)
        result(nil)
      case "deleteHistory":
        self.logStore.deleteHistory()
        result(nil)
      case "endSession":
        self.logStore.endSession()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickAndExtractDocsZip(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
          let targetDirectory = args["targetDirectory"] as? String,
          !targetDirectory.isEmpty else {
      result(
        FlutterError(
          code: "invalid_target_directory",
          message: "缺少导入目标目录",
          details: nil
        )
      )
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        result(
          FlutterError(
            code: "missing_app_delegate",
            message: "无法获取 iOS 应用代理",
            details: nil
          )
        )
        return
      }
      guard let rootController = self.topViewController() else {
        result(
          FlutterError(
            code: "missing_view_controller",
            message: "Unable to present ZIP picker",
            details: nil
          )
        )
        return
      }
      if self.zipImportInProgress || self.pendingImportResult != nil {
        result(
          FlutterError(
            code: "zip_import_busy",
            message: "已有 ZIP 导入选择正在进行",
            details: nil
          )
        )
        return
      }
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.zip],
        asCopy: true
      )
      picker.delegate = self
      picker.allowsMultipleSelection = false
      picker.modalPresentationStyle = .formSheet
      self.zipImportInProgress = true
      self.pendingImportResult = result
      self.pendingImportTargetDirectory = targetDirectory
      rootController.present(picker, animated: true)
    }
  }

  private func finishPickedZipImport(
    zipURL: URL,
    targetDirectory: String,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "missing_app_delegate",
              message: "无法获取 iOS 应用代理",
              details: nil
            )
          )
        }
        return
      }
      let didAccess = zipURL.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          zipURL.stopAccessingSecurityScopedResource()
        }
      }
      do {
        let session = ZipImportSession(
          zipURL: zipURL,
          targetDirectory: URL(
            fileURLWithPath: targetDirectory,
            isDirectory: true
          )
        )
        _ = try session.run { [weak self] progress in
          self?.reportImportProgress(progress)
        }
        DispatchQueue.main.async {
          self.zipImportInProgress = false
          result(targetDirectory)
        }
      } catch {
        DispatchQueue.main.async {
          self.zipImportInProgress = false
          result(
            FlutterError(
              code: "zip_import_failed",
              message: "无法导入选择的 ZIP：\(error.localizedDescription)",
              details: nil
            )
          )
        }
      }
    }
  }

  private func reportImportProgress(_ progress: ImportProgress) {
    let now = DispatchTime.now().uptimeNanoseconds
    if now - lastImportProgressReportAt < 100_000_000 {
      return
    }
    lastImportProgressReportAt = now
    let arguments: [String: Any] = [
      "phase": progress.phase,
      "processedBytes": progress.processedBytes,
      "totalBytes": progress.totalBytes,
      "processedFiles": progress.processedFiles,
      "totalFiles": progress.totalFiles,
      "message": progress.message,
    ]
    DispatchQueue.main.async { [weak self] in
      self?.resourceZipImporterChannel?.invokeMethod(
        "progress",
        arguments: arguments
      )
    }
  }

  private func topViewController() -> UIViewController? {
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let pendingImportResult else { return }
    pendingImportResult(nil)
    self.pendingImportResult = nil
    pendingImportTargetDirectory = nil
    zipImportInProgress = false
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let pendingImportResult else { return }
    let targetDirectory = pendingImportTargetDirectory
    self.pendingImportResult = nil
    pendingImportTargetDirectory = nil
    guard let zipURL = urls.first, let targetDirectory else {
      zipImportInProgress = false
      pendingImportResult(nil)
      return
    }
    finishPickedZipImport(
      zipURL: zipURL,
      targetDirectory: targetDirectory,
      result: pendingImportResult
    )
  }
}
