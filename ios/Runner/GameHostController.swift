import Flutter
import Foundation
import GardendlessBridge
import GardendlessCore
import GardendlessGPNext
import GardendlessLogging
import GardendlessResource
import UIKit
import UniformTypeIdentifiers
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
  private let fileTasks: FileTaskCoordinator
  private let gpNextSelectionStager: GpNextSelectionStager?
  private let logStore: LogStore
  private let selectionQueue = DispatchQueue(label: "io.github.dey410.gardendless.selection", qos: .userInitiated)

  private var webView: WKWebView!
  private var scriptBridge: ScriptMessageBridge!
  private var navigationPolicy: NavigationPolicy!
  private var pendingExport: (id: String, handle: String, file: URL, picker: UIDocumentPickerViewController)?
  private var activePicker: UIDocumentPickerViewController?
  private var pendingReplacementDecision: ((Bool) -> Void)?
  private var pendingGpNextImportId: String?
  private var pendingGpNextSelection: (id: String, directory: Bool)?
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
    let router = session.hasGpNext && session.gpNextCompatible
      ? try GpNextCommandRouter(session: session)
      : nil
    fileTasks = try FileTaskCoordinator(session: session, gpNextRouter: router)
    gpNextSelectionStager = session.hasGpNext && session.gpNextCompatible
      ? GpNextSelectionStager(gpNextRoot: session.gpNextRoot)
      : nil
    super.init(nibName: nil, bundle: nil)
    fileTasks.onExportCancelled = { [weak self] file, code in
      guard let self, let export = self.pendingExport, export.file == file else { return }
      self.pendingExport = nil
      if self.activePicker === export.picker { self.activePicker = nil }
      export.picker.dismiss(animated: true)
      self.scriptBridge.fail(id: export.id, code: code, message: "Export was cancelled or expired")
    }
    modalPresentationStyle = .fullScreen
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func loadView() {
    let configuration = WKWebViewConfiguration()
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
      "context": ["packageId": session.packageId as Any? ?? NSNull()],
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

  func bridgeRequestedLog(id: String, arguments: [String: Any]) {
    let javascriptEvents = [
      "javascript_uncaught_error",
      "javascript_unhandled_rejection",
      "javascript_console",
    ]
    let audioEvents = [
      "audio_decode_started",
      "audio_decode_succeeded",
      "audio_decode_failed",
      "audio_media_load_started",
      "audio_media_ready",
      "audio_media_play_requested",
      "audio_media_playing",
      "audio_media_ended",
      "audio_media_failed",
      "audio_summary",
    ]
    let requested = arguments["event"] as? String ?? "javascript_console"
    let isAudio = audioEvents.contains(requested)
    let event = isAudio || javascriptEvents.contains(requested)
      ? requested : "javascript_console"
    let context = isAudio
      ? arguments["context"] as? [String: Any] ?? [:]
      : [
        "page": arguments["page"] as? String ?? "",
        "line": arguments["line"] as? Int ?? 0,
        "column": arguments["column"] as? Int ?? 0,
      ]
    logStore.emit([
      "source": "javascript",
      "level": arguments["level"] as? String ?? "ERROR",
      "category": isAudio ? "game.audio" : "game.javascript",
      "event": event,
      "outcome": isAudio
        ? arguments["outcome"] as? String ?? "observed" : "failed",
      "code": event.contains("failed") ? event : NSNull(),
      "message": arguments["message"] as? String ?? "",
      "gameSessionId": session.sessionId,
      "context": context,
      "error": isAudio ? NSNull() : [
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
  }

  func bridgeRequestedFile(command: String, id: String, arguments: [String: Any]) {
    fileTasks.submit(command: command, arguments: arguments) { [weak self] result in
      self?.completeFileAction(result, id: id)
    }
  }

  func bridgeRequestedGpNext(id: String, request: [String: Any]) {
    fileTasks.submitGpNext(request) { [weak self] result in
      self?.completeFileAction(result, id: id)
    }
  }

  private func completeFileAction(_ result: Result<GpNextAction, Error>, id: String) {
    guard !cleanedUp else { return }
    do {
      switch try result.get() {
      case .value(let value):
        scriptBridge.complete(id: id, value: value)
      case .openURL(let url):
        UIApplication.shared.open(url) { [weak self] opened in
          opened
            ? self?.scriptBridge.complete(id: id, value: NSNull())
            : self?.scriptBridge.fail(id: id, code: "external_open_failed", message: "Unable to open URL")
        }
      case .exportFile(let file):
        guard let handle = fileTasks.exportHandle(for: file) else {
          scriptBridge.fail(id: id, code: "cancelled", message: "Export was cancelled or expired")
          return
        }
        guard pendingExport == nil, pendingGpNextImportId == nil,
              pendingGpNextSelection == nil else {
          fileTasks.finishExport(handle: handle, cancelled: true) { [weak self] _ in
            self?.scriptBridge.fail(id: id, code: "export_in_progress", message: "Another picker is active")
          }
          return
        }
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        pendingExport = (id, handle, file, picker)
        activePicker = picker
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
      case .importPackages:
        beginGpNextImport(id: id)
      case .openSelection(let directory):
        beginGpNextSelection(id: id, directory: directory)
      }
    } catch {
      scriptBridge.fail(id: id, code: "file_error", message: error.localizedDescription)
    }
  }

  private func beginGpNextImport(id: String) {
    guard pendingGpNextImportId == nil,
          pendingGpNextSelection == nil,
          pendingExport == nil else {
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
    activePicker = picker
    picker.delegate = self
    picker.allowsMultipleSelection = true
    picker.modalPresentationStyle = .formSheet
    present(picker, animated: true)
  }

  private func beginGpNextSelection(id: String, directory: Bool) {
    guard pendingGpNextImportId == nil,
          pendingGpNextSelection == nil,
          pendingExport == nil,
          gpNextSelectionStager != nil else {
      scriptBridge.fail(
        id: id,
        code: "gp_next_selection_busy",
        message: "Another picker is active"
      )
      return
    }
    pendingGpNextSelection = (id, directory)
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [directory ? .folder : .zip],
      asCopy: true
    )
    activePicker = picker
    picker.delegate = self
    picker.allowsMultipleSelection = false
    picker.modalPresentationStyle = .formSheet
    present(picker, animated: true)
  }

  private func importGpNextPackages(_ urls: [URL], id: String) {
    selectionQueue.async { [weak self] in
      guard let self else { return }
      do {
        let importer = GpNextPackageImporter(gpNextRoot: self.session.gpNextRoot)
        for url in urls {
          _ = try importer.importPackage(url, isCancelled: { !self.fileTasks.isActive }) { name in
            self.confirmReplacement(name)
          }
        }
        DispatchQueue.main.async {
          guard !self.cleanedUp else { return }
          self.pendingGpNextImportId = nil
          self.scriptBridge.complete(id: id, value: NSNull())
        }
      } catch {
        DispatchQueue.main.async {
          guard !self.cleanedUp else { return }
          self.pendingGpNextImportId = nil
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
    DispatchQueue.main.async { [self] in
      guard !self.cleanedUp else { semaphore.signal(); return }
      var answered = false
      let answer: (Bool) -> Void = { [weak self] value in
        guard !answered else { return }
        answered = true
        confirmed = value
        self?.pendingReplacementDecision = nil
        semaphore.signal()
      }
      self.pendingReplacementDecision = answer
      let alert = UIAlertController(
        title: "替换 GP-Next 文件",
        message: "\(name) 已存在，是否使用新文件替换？",
        preferredStyle: .alert
      )
      alert.addAction(
        UIAlertAction(title: "取消", style: .cancel) { _ in answer(false) }
      )
      alert.addAction(
        UIAlertAction(title: "替换", style: .destructive) { _ in answer(true) }
      )
      self.present(alert, animated: true)
    }
    return semaphore.wait(timeout: .now() + 300) == .success && confirmed
  }

  // MARK: UIDocumentPickerDelegate

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard activePicker === controller else { return }
    activePicker = nil
    if let selection = pendingGpNextSelection {
      pendingGpNextSelection = nil
      clearSelection()
      scriptBridge.complete(id: selection.id, value: NSNull())
      return
    }
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
    fileTasks.finishExport(handle: export.handle, cancelled: true) { [weak self] _ in
      self?.scriptBridge.fail(id: export.id, code: "export_cancelled", message: "Export was cancelled")
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard activePicker === controller else { return }
    activePicker = nil
    if let selection = pendingGpNextSelection {
      guard let url = urls.first, let gpNextSelectionStager else {
        pendingGpNextSelection = nil
        scriptBridge.complete(id: selection.id, value: NSNull())
        return
      }
      selectionQueue.async { [weak self] in
        guard let self else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
          if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
          let staged = try gpNextSelectionStager.stage(
            url,
            directory: selection.directory,
            isCancelled: { !self.fileTasks.isActive }
          )
          DispatchQueue.main.async {
            guard !self.cleanedUp else { return }
            self.pendingGpNextSelection = nil
            self.scriptBridge.complete(id: selection.id, value: staged.path)
          }
        } catch {
          try? gpNextSelectionStager.clear()
          DispatchQueue.main.async {
            guard !self.cleanedUp else { return }
            self.pendingGpNextSelection = nil
            self.scriptBridge.fail(
              id: selection.id,
              code: "gp_next_selection_failed",
              message: error.localizedDescription
            )
          }
        }
      }
      return
    }
    if let id = pendingGpNextImportId {
      importGpNextPackages(urls, id: id)
      return
    }
    guard let export = pendingExport else { return }
    pendingExport = nil
    fileTasks.finishExport(handle: export.handle, cancelled: false) { [weak self] result in
      switch result {
      case .success:
        self?.scriptBridge.complete(id: export.id, value: NSNull())
      case .failure(let error):
        self?.scriptBridge.fail(id: export.id, code: "export_failed", message: error.localizedDescription)
      }
    }
  }

  private func clearSelection() {
    let stager = gpNextSelectionStager
    selectionQueue.async { try? stager?.clear() }
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
      "context": ["reason": reason, "packageId": session.packageId as Any? ?? NSNull()],
    ])
    _ = logStore.flush(timeout: 0.5)
    writeExitResult(reason: reason, message: message)
    cleanupWebView()
    onExit()
  }

  private func cleanupWebView() {
    guard !cleanedUp else { return }
    cleanedUp = true
    pendingReplacementDecision?(false)
    pendingGpNextImportId = nil
    pendingExport = nil
    activePicker = nil
    pendingGpNextSelection = nil
    clearSelection()
    fileTasks.destroy()
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: ScriptMessageBridge.name,
      contentWorld: .page
    )
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
      "packageId": session.packageId ?? NSNull(),
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
    let config: [String: Any] = [
      "hostAbi": 1,
      "packageId": session.packageId ?? NSNull(),
      "platform": "ios",
      "touchWheelCssMultiplier": -4.5,
      "touchDiagnosticsEnabled": false,
      "origin": GameOrigin.value,
      "activationGeneration": session.activationGeneration,
      "hasGpNext": session.hasGpNext,
      "gpNextCompatible": session.gpNextCompatible,
      "gpNextVersion": session.gpNextVersion ?? NSNull(),
      "watermarkEnabled": session.watermarkEnabled,
      "autoCollectSunEnabled": session.autoCollectSunEnabled,
      "detailedAudioDiagnosticsEnabled":
        session.detailedAudioDiagnosticsEnabled,
      "gpNextBaseDirectory": session.gpNextRoot
        .deletingLastPathComponent().path,
    ]
    let configData = try! JSONSerialization.data(withJSONObject: config)
    var source = "window.__gardendlessHostConfig="
      + String(data: configData, encoding: .utf8)!
      + ";"
    var names = [
      "transport.js",
      "logging.js",
      "audio_diagnostic.js",
      "auto_sun.js",
      "touch_state_machine.js",
      "touch_input_adapter.js",
      "export_download_patch.js",
    ]
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
