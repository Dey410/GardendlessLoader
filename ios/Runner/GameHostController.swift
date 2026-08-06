import Flutter
import Foundation
import GardendlessAudio
import GardendlessBridge
import GardendlessCore
import GardendlessGPNext
import GardendlessLogging
import GardendlessResource
import UIKit
import WebKit

enum GameViewportSize {
  static let minimumAspectRatio: CGFloat = 16.0 / 10.0
  static let maximumAspectRatio: CGFloat = 17.0 / 9.0

  static func fit(_ bounds: CGSize) -> CGSize {
    guard bounds.width > 0, bounds.height > 0 else { return .zero }
    let aspectRatio = bounds.width / bounds.height
    if aspectRatio > maximumAspectRatio {
      return CGSize(
        width: floor(bounds.height * maximumAspectRatio),
        height: bounds.height
      )
    }
    if aspectRatio < minimumAspectRatio {
      return CGSize(
        width: bounds.width,
        height: floor(bounds.width / minimumAspectRatio)
      )
    }
    return bounds
  }
}

private final class GameViewportView: UIView {
  let webView: WKWebView

  init(webView: WKWebView) {
    self.webView = webView
    super.init(frame: .zero)
    backgroundColor = .black
    addSubview(webView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let size = GameViewportSize.fit(bounds.size)
    webView.frame = CGRect(
      x: floor((bounds.width - size.width) / 2),
      y: floor((bounds.height - size.height) / 2),
      width: size.width,
      height: size.height
    )
  }
}

final class GameHostController: UIViewController,
  ScriptBridgeDelegate,
  UIDocumentPickerDelegate {
  private let session: GameSession
  private let networkRuleList: WKContentRuleList
  private let onExit: () -> Void
  private let sandbox: PathSandbox
  private let schemeHandler: ResourceSchemeHandler
  private let audioEngine: AudioPipelineEngine
  private let exportCoordinator: ExportCoordinator
  private let gpNextRouter: GpNextCommandRouter?
  private let logStore: LogStore

  private var webView: WKWebView!
  private var scriptBridge: ScriptMessageBridge!
  private var audioBridge: AudioScriptBridge!
  private var navigationPolicy: NavigationPolicy!
  private var pendingExport: (id: String, file: URL)?
  private var pendingGpNextImportId: String?
  private var exiting = false
  private var cleanedUp = false

  init(
    session: GameSession,
    networkRuleList: WKContentRuleList,
    logStore: LogStore,
    onExit: @escaping () -> Void
  ) throws {
    self.session = session
    self.networkRuleList = networkRuleList
    self.logStore = logStore
    self.onExit = onExit
    sandbox = try PathSandbox(root: session.resourceRoot)
    schemeHandler = ResourceSchemeHandler(
      sandbox: sandbox
    ) { [session] code, path, status, details in
      var context: [String: Any] = ["status": status]
      if let path {
        context["path"] = path
      }
      details.forEach { context[$0.key] = $0.value }
      logStore.emit([
        "source": "ios",
        "level": status >= 500 ? "ERROR" : "WARN",
        "category": "resource.handler",
        "event": "resource_request_failed",
        "outcome": "failed",
        "code": code,
        "gameSessionId": session.sessionId,
        "context": context,
      ])
    }
    audioEngine = AudioPipelineEngine(
      sandbox: sandbox,
      configuration: Self.audioConfiguration()
    ) { [session] event, context in
      logStore.emit([
        "source": "ios",
        "level": event == "native_sfx_decode_failed" ? "WARN" : "INFO",
        "category": "game.audio",
        "event": event,
        "outcome": event.contains("failed") ? "failed" : "observed",
        "gameSessionId": session.sessionId,
        "context": context,
      ])
    }
    exportCoordinator = try ExportCoordinator(
      temporaryRoot: session.exportTemporaryRoot
    )
    gpNextRouter = session.hasGpNext && session.gpNextCompatible
      ? try GpNextCommandRouter(session: session)
      : nil
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  private static func audioConfiguration() -> GameConfiguration {
    let defaults = UserDefaults.standard
    var config = GameConfiguration.default
    if let value = defaults.object(forKey: "audioCompressedSfxByteLimit")
      as? Int, value > 0 {
      config.compressedSfxByteLimit = Int64(value)
    }
    if let value = defaults.object(forKey: "audioPcmCacheByteLimit")
      as? Int, value > 0 {
      config.pcmCacheByteLimit = value
    }
    if let value = defaults.object(forKey: "audioSingleBufferByteLimit")
      as? Int, value > 0 {
      config.singleBufferByteLimit = value
    }
    if let value = defaults.object(forKey: "audioMaximumSfxDuration")
      as? Double, value > 0 {
      config.maximumSfxDuration = value
    }
    if let value = defaults.object(forKey: "audioLongMaxBytes")
      as? Int, value > 0 {
      config.longMaxBytes = Int64(value)
    }
    if let value = defaults.object(forKey: "audioLongMaxDuration")
      as? Double, value > 0 {
      config.longMaxDuration = value
    }
    return config
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func loadView() {
    let configuration = WKWebViewConfiguration()
    _ = GDLDisableWebKit60FPSPreference(configuration)
    configuration.websiteDataStore = .default()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.setURLSchemeHandler(
      schemeHandler,
      forURLScheme: GameOrigin.scheme
    )
    let contentController = WKUserContentController()
    contentController.add(networkRuleList)
    contentController.addUserScript(
      WKUserScript(
        source: buildDocumentStartScript(),
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
      )
    )
    configuration.userContentController = contentController

    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.isOpaque = true
    webView.backgroundColor = .black
    webView.scrollView.backgroundColor = .black
    webView.scrollView.bounces = false
    webView.allowsBackForwardNavigationGestures = false
    webView.allowsLinkPreview = false

    scriptBridge = ScriptMessageBridge(webView: webView)
    scriptBridge.delegate = self
    contentController.addScriptMessageHandler(
      scriptBridge,
      contentWorld: .page,
      name: ScriptMessageBridge.name
    )

    audioBridge = AudioScriptBridge(
      engine: audioEngine,
      webViewProvider: { [weak self] in self?.webView }
    )
    contentController.add(
      audioBridge,
      contentWorld: .page,
      name: AudioScriptBridge.name
    )

    navigationPolicy = NavigationPolicy(session: session)
    navigationPolicy.owner = self
    webView.navigationDelegate = navigationPolicy

    let viewport = GameViewportView(webView: webView)
    let edgeGesture = UIScreenEdgePanGestureRecognizer(
      target: self,
      action: #selector(returnToLauncher)
    )
    edgeGesture.edges = .left
    viewport.addGestureRecognizer(edgeGesture)
    view = viewport
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    logStore.emit([
      "source": "ios",
      "level": "INFO",
      "category": "game.host",
      "event": "game_host_created",
      "outcome": "succeeded",
      "gameSessionId": session.sessionId,
    ])
    webView.load(
      URLRequest(
        url: session.entryURL,
        cachePolicy: .useProtocolCachePolicy
      )
    )
  }

  override var prefersStatusBarHidden: Bool { true }
  override var prefersHomeIndicatorAutoHidden: Bool { true }
  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    .landscape
  }
  override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
    .landscapeRight
  }

  @objc private func returnToLauncher() {
    exit(reason: "userReturned", message: nil)
  }

  // MARK: ScriptBridgeDelegate

  func bridgeRequestedReturnHome() {
    exit(reason: "userReturned", message: nil)
  }

  func bridgeRequestedWatermark(_ enabled: Bool) throws {
    let output = session.appRoot.appendingPathComponent("app_settings.json")
    let data = try JSONSerialization.data(
      withJSONObject: ["watermarkEnabled": enabled],
      options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: output, options: .atomic)
  }

  func bridgeRequestedLog(id: String, arguments: [String: Any]) {
    let allowed = [
      "javascript_uncaught_error",
      "javascript_unhandled_rejection",
      "javascript_console",
    ]
    let requested = arguments["event"] as? String ?? "javascript_console"
    let event = allowed.contains(requested) ? requested : "javascript_console"
    logStore.emit([
      "source": "javascript",
      "level": arguments["level"] as? String ?? "ERROR",
      "category": "game.javascript",
      "event": event,
      "outcome": "failed",
      "code": event == "javascript_console" ? NSNull() : event,
      "message": arguments["message"] as? String ?? "",
      "gameSessionId": session.sessionId,
      "context": [
        "page": arguments["page"] as? String ?? "",
        "line": arguments["line"] as? Int ?? 0,
        "column": arguments["column"] as? Int ?? 0,
      ],
      "error": [
        "type": "JavaScriptError",
        "message": arguments["message"] as? String ?? "",
        "stackTrace": arguments["stack"] as? String ?? "",
      ],
    ])
    scriptBridge.complete(id: id, value: NSNull())
  }

  func bridgeRejectedMessage(reason: String, command: String?) {
    var context: [String: Any] = ["reason": reason]
    if let command {
      context["command"] = command
    }
    logStore.emit([
      "source": "ios",
      "level": "WARN",
      "category": "game.bridge",
      "event": "bridge_message_invalid",
      "outcome": "failed",
      "code": "bridge_message_invalid",
      "gameSessionId": session.sessionId,
      "context": context,
    ])
  }

  func bridgeRequestedExport(
    command: String,
    id: String,
    arguments: [String: Any]
  ) {
    if command == BridgeCommand.export.rawValue {
      guard let raw = arguments["url"] as? String,
            let url = URL(string: raw),
            isAllowedRemoteURL(url) else {
        scriptBridge.fail(
          id: id,
          code: "unsupported_export",
          message: "Export URL is not authorized"
        )
        return
      }
      UIApplication.shared.open(url) { [weak self] opened in
        opened
          ? self?.scriptBridge.complete(id: id, value: NSNull())
          : self?.scriptBridge.fail(
            id: id,
            code: "external_open_failed",
            message: "Unable to open URL"
          )
      }
      return
    }
    handleChunkedExport(command: command, id: id, arguments: arguments)
  }

  private func handleChunkedExport(
    command: String,
    id: String,
    arguments: [String: Any]
  ) {
    do {
      switch command {
      case BridgeCommand.exportBegin.rawValue:
        guard pendingExport == nil,
              let expected = arguments["totalBytes"] as? Int,
              expected >= 0 else {
          throw GameError.failed(
            .exportFailed,
            "Export size is invalid or another export is active"
          )
        }
        let token = try exportCoordinator.begin(
          sessionId: session.sessionId,
          suggestedFilename: arguments["suggestedFilename"] as? String
            ?? "gardendless-export.json",
          mimeType: arguments["mimeType"] as? String
            ?? "application/octet-stream",
          totalBytes: expected
        )
        scriptBridge.complete(id: id, value: token)
      case BridgeCommand.exportChunk.rawValue:
        guard let token = arguments["token"] as? String,
              let index = arguments["index"] as? Int,
              let encoded = arguments["data"] as? String,
              let data = Data(base64Encoded: encoded) else {
          throw GameError.failed(.exportFailed, "Export chunk sequence is invalid")
        }
        try exportCoordinator.append(
          token: token,
          index: index,
          data: data
        )
        scriptBridge.complete(id: id, value: NSNull())
      case BridgeCommand.exportCommit.rawValue:
        guard let token = arguments["token"] as? String else {
          throw GameError.failed(.exportFailed, "Export token is missing")
        }
        let file = try exportCoordinator.commit(token: token)
        pendingExport = (id, file)
        let picker = UIDocumentPickerViewController(
          forExporting: [file],
          asCopy: true
        )
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
      case BridgeCommand.exportAbort.rawValue:
        if let token = arguments["token"] as? String {
          exportCoordinator.abort(token: token)
        }
        scriptBridge.complete(id: id, value: NSNull())
      default:
        throw GameError.failed(.exportFailed, "Unknown export command")
      }
    } catch {
      scriptBridge.fail(
        id: id,
        code: "export_failed",
        message: error.localizedDescription
      )
    }
  }

  func bridgeRequestedGpNext(id: String, request: [String: Any]) {
    guard let gpNextRouter else {
      scriptBridge.fail(
        id: id,
        code: "gp_next_unavailable",
        message: "GP-Next compatibility is unavailable"
      )
      return
    }
    do {
      switch try gpNextRouter.dispatch(request) {
      case .value(let value):
        scriptBridge.complete(id: id, value: value)
      case .openURL(let url):
        UIApplication.shared.open(url) { [weak self] opened in
          opened
            ? self?.scriptBridge.complete(id: id, value: NSNull())
            : self?.scriptBridge.fail(
              id: id,
              code: "external_open_failed",
              message: "Unable to open URL"
            )
        }
      case .exportFile(let file):
        guard pendingExport == nil else {
          scriptBridge.fail(
            id: id,
            code: "export_in_progress",
            message: "Another export is active"
          )
          return
        }
        pendingExport = (id, file)
        let picker = UIDocumentPickerViewController(
          forExporting: [file],
          asCopy: true
        )
        picker.delegate = self
        present(picker, animated: true)
      case .importPackages:
        beginGpNextImport(id: id)
      }
    } catch {
      scriptBridge.fail(
        id: id,
        code: "gp_next_error",
        message: error.localizedDescription
      )
    }
  }

  private func beginGpNextImport(id: String) {
    guard pendingGpNextImportId == nil, pendingExport == nil else {
      scriptBridge.fail(
        id: id,
        code: "gp_next_import_busy",
        message: "Another picker is active"
      )
      return
    }
    pendingGpNextImportId = id
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.zip, .json, .plainText, .data],
      asCopy: true
    )
    picker.delegate = self
    picker.allowsMultipleSelection = true
    picker.modalPresentationStyle = .formSheet
    present(picker, animated: true)
  }

  private func importGpNextPackages(_ urls: [URL], id: String) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      do {
        let importer = GpNextPackageImporter(gpNextRoot: self.session.gpNextRoot)
        for url in urls {
          _ = try importer.importPackage(url) { name in
            self.confirmReplacement(name)
          }
        }
        DispatchQueue.main.async {
          self.scriptBridge.complete(id: id, value: NSNull())
        }
      } catch {
        DispatchQueue.main.async {
          self.scriptBridge.fail(
            id: id,
            code: "gp_next_import_failed",
            message: error.localizedDescription
          )
        }
      }
    }
  }

  private func confirmReplacement(_ name: String) -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var confirmed = false
    DispatchQueue.main.async {
      let alert = UIAlertController(
        title: "替换 GP-Next 文件",
        message: "\(name) 已存在，是否使用新文件替换？",
        preferredStyle: .alert
      )
      alert.addAction(
        UIAlertAction(title: "取消", style: .cancel) { _ in
          semaphore.signal()
        }
      )
      alert.addAction(
        UIAlertAction(title: "替换", style: .destructive) { _ in
          confirmed = true
          semaphore.signal()
        }
      )
      self.present(alert, animated: true)
    }
    return semaphore.wait(timeout: .now() + 300) == .success && confirmed
  }

  // MARK: UIDocumentPickerDelegate

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let id = pendingGpNextImportId {
      pendingGpNextImportId = nil
      scriptBridge.fail(
        id: id,
        code: "import_cancelled",
        message: "Import was cancelled"
      )
      return
    }
    guard let export = pendingExport else { return }
    pendingExport = nil
    try? FileManager.default.removeItem(at: export.file)
    scriptBridge.fail(
      id: export.id,
      code: "export_cancelled",
      message: "Export was cancelled"
    )
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    if let id = pendingGpNextImportId {
      pendingGpNextImportId = nil
      importGpNextPackages(urls, id: id)
      return
    }
    guard let export = pendingExport else { return }
    pendingExport = nil
    try? FileManager.default.removeItem(at: export.file)
    scriptBridge.complete(id: export.id, value: NSNull())
  }

  // MARK: Navigation callbacks

  func rendererDidTerminate() {
    logStore.emit([
      "source": "ios",
      "level": "ERROR",
      "category": "game.webview",
      "event": "webview_render_process_gone",
      "outcome": "failed",
      "code": "webview_render_process_gone",
      "gameSessionId": session.sessionId,
    ])
    exit(reason: "rendererGone", message: "iOS WebContent process terminated")
  }

  func navigationDidFail(_ error: Error) {
    logStore.emit([
      "source": "ios",
      "level": "ERROR",
      "category": "game.webview",
      "event": "webview_page_load_finished",
      "outcome": "failed",
      "code": "webview_page_load_failed",
      "message": error.localizedDescription,
      "gameSessionId": session.sessionId,
      "error": [
        "type": String(describing: type(of: error)),
        "message": error.localizedDescription,
      ],
    ])
    guard webView.url == nil else { return }
    exit(reason: "launchFailed", message: error.localizedDescription)
  }

  func navigationDidStart() {
    logStore.emit([
      "source": "ios",
      "level": "INFO",
      "category": "game.webview",
      "event": "webview_page_load_started",
      "outcome": "started",
      "gameSessionId": session.sessionId,
    ])
  }

  func navigationDidFinish() {
    logStore.emit([
      "source": "ios",
      "level": "INFO",
      "category": "game.webview",
      "event": "webview_page_load_finished",
      "outcome": "succeeded",
      "gameSessionId": session.sessionId,
    ])
  }

  func navigationWasBlocked() {
    logStore.emit([
      "source": "ios",
      "level": "WARN",
      "category": "game.security",
      "event": "navigation_blocked",
      "outcome": "observed",
      "gameSessionId": session.sessionId,
    ])
  }

  // MARK: Lifecycle

  private func exit(reason: String, message: String?) {
    guard !exiting else { return }
    exiting = true
    logStore.emit([
      "source": "ios",
      "level": reason == "rendererGone" || reason == "launchFailed"
        ? "ERROR" : "INFO",
      "category": "game.host",
      "event": "game_host_finished",
      "outcome": reason == "rendererGone" || reason == "launchFailed"
        ? "failed" : "succeeded",
      "message": message ?? NSNull(),
      "gameSessionId": session.sessionId,
      "context": ["reason": reason],
    ])
    _ = logStore.flush(timeout: 0.5)
    writeExitResult(reason: reason, message: message)
    cleanupWebView()
    onExit()
  }

  private func cleanupWebView() {
    guard !cleanedUp else { return }
    cleanedUp = true
    if let export = pendingExport {
      try? FileManager.default.removeItem(at: export.file)
      pendingExport = nil
    }
    exportCoordinator.cancelActive()
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: ScriptMessageBridge.name,
      contentWorld: .page
    )
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: AudioScriptBridge.name,
      contentWorld: .page
    )
    audioBridge.destroy()
    audioEngine.shutdown()
    scriptBridge.destroy()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.removeFromSuperview()
  }

  private func writeExitResult(reason: String, message: String?) {
    let output = session.appRoot.appendingPathComponent("game_exit_result.json")
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let json: [String: Any] = [
      "schemaVersion": 1,
      "sessionId": session.sessionId,
      "reason": reason,
      "finishedAt": formatter.string(from: Date()),
      "message": message ?? NSNull(),
    ]
    if let data = try? JSONSerialization.data(
      withJSONObject: json,
      options: [.prettyPrinted]
    ) {
      try? data.write(to: output, options: .atomic)
    }
  }

  private func buildDocumentStartScript() -> String {
    let nativeSfxEnabled = UserDefaults.standard.object(
      forKey: "nativeSfxEnabled"
    ) as? Bool ?? true
    let audioDiagnosticsEnabled = UserDefaults.standard.object(
      forKey: "audioDiagnosticsEnabled"
    ) as? Bool ?? true
    let config: [String: Any] = [
      "platform": "ios",
      "origin": GameOrigin.value,
      "activationGeneration": session.activationGeneration,
      "hasGpNext": session.hasGpNext,
      "gpNextCompatible": session.gpNextCompatible,
      "gpNextVersion": session.gpNextVersion ?? NSNull(),
      "watermarkEnabled": session.watermarkEnabled,
      "autoCollectSunEnabled": session.autoCollectSunEnabled,
      "nativeSfxEnabled": nativeSfxEnabled,
      "audioDiagnosticsEnabled": audioDiagnosticsEnabled,
      "audioVoicePoolSize": AudioPlaybackLimits.voicePoolSize,
      "gpNextBaseDirectory": session.appRoot.path,
    ]
    let configData = try! JSONSerialization.data(withJSONObject: config)
    var source = "window.__gardendlessHostConfig="
      + String(data: configData, encoding: .utf8)!
      + ";"
    var names = [
      "transport.js",
      "audio_diagnostic.js",
      "ios_audio_facade.js",
      "ios_audio_proxy.js",
      "bootstrap.js",
      "logging.js",
      "auto_sun.js",
      "touch_patch.js",
      "export_download_patch.js",
    ]
    if session.hasGpNext && session.gpNextCompatible {
      names.append("gp_next_core.js")
      names.append("gp_next_compat_bridge.js")
    }
    names.append("watermark.js")
    for name in names {
      guard let script = Self.loadFlutterAsset("assets/game_bridge/\(name)") else {
        preconditionFailure("Missing shared game bridge asset: \(name)")
      }
      source += "\n" + script
    }
    return source
  }

  private static func loadFlutterAsset(_ name: String) -> String? {
    let key = FlutterDartProject.lookupKey(forAsset: name)
    let bundles = [
      Bundle.main,
      Bundle.main.privateFrameworksURL
        .map { $0.appendingPathComponent("App.framework") }
        .flatMap(Bundle.init(url:)),
    ].compactMap { $0 }
    for bundle in bundles {
      if let url = bundle.url(forResource: key, withExtension: nil),
         let source = try? String(contentsOf: url, encoding: .utf8) {
        return source
      }
    }
    return nil
  }

  private func isAllowedRemoteURL(_ url: URL) -> Bool {
    guard url.scheme == "https",
          let host = url.host?.lowercased() else {
      return false
    }
    return session.allowedRemoteHosts.contains {
      host == $0 || host.hasSuffix(".\($0)")
    }
  }

  deinit {
    if webView != nil {
      cleanupWebView()
    }
  }
}

private final class NavigationPolicy: NSObject, WKNavigationDelegate {
  private let session: GameSession
  weak var owner: GameHostController?

  init(session: GameSession) {
    self.session = session
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    if url.scheme == GameOrigin.scheme, url.host == GameOrigin.host {
      decisionHandler(.allow)
      return
    }
    guard navigationAction.targetFrame?.isMainFrame != false,
          url.scheme == "https",
          isAllowedRemoteHost(url.host) else {
      owner?.navigationWasBlocked()
      decisionHandler(.cancel)
      return
    }
    UIApplication.shared.open(url)
    decisionHandler(.cancel)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    owner?.rendererDidTerminate()
  }

  func webView(
    _ webView: WKWebView,
    didStartProvisionalNavigation navigation: WKNavigation!
  ) {
    owner?.navigationDidStart()
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    owner?.navigationDidFinish()
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    owner?.navigationDidFail(error)
  }

  private func isAllowedRemoteHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return session.allowedRemoteHosts.contains {
      host == $0 || host.hasSuffix(".\($0)")
    }
  }
}
