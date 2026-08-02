import Flutter
import UIKit
import WebKit

enum GameViewportSize {
  static let minimumAspectRatio: CGFloat = 16.0 / 10.0
  static let maximumAspectRatio: CGFloat = 17.0 / 9.0

  static func fit(_ bounds: CGSize) -> CGSize {
    guard bounds.width > 0, bounds.height > 0 else { return .zero }
    let aspectRatio = bounds.width / bounds.height
    if aspectRatio > maximumAspectRatio {
      return CGSize(width: floor(bounds.height * maximumAspectRatio), height: bounds.height)
    }
    if aspectRatio < minimumAspectRatio {
      return CGSize(width: bounds.width, height: floor(bounds.width / minimumAspectRatio))
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
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

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

final class GameViewController: UIViewController, GameScriptBridgeDelegate, UIDocumentPickerDelegate {
  private let session: NativeGameSession
  private let onExit: () -> Void
  private let schemeHandler: GameResourceSchemeHandler
  private let networkRuleList: WKContentRuleList
  private let gpNextCore: GpNextNativeCore?
  private var webView: WKWebView!
  private var scriptBridge: GameScriptBridge!
  private var navigationDelegate: GameNavigationDelegate!
  private var pendingExport: (id: String, file: URL)?
  private var chunkedExport: ChunkedExport?
  private var pendingGpNextImportId: String?
  private var exiting = false
  private var cleanedUp = false

  init(
    session: NativeGameSession,
    networkRuleList: WKContentRuleList,
    onExit: @escaping () -> Void
  ) throws {
    self.session = session
    self.networkRuleList = networkRuleList
    self.onExit = onExit
    schemeHandler = try GameResourceSchemeHandler(
      resourceRoot: session.resourceRoot,
      onDiagnostic: { code, path, status, details in
        var context: [String: Any] = ["status": status]
        if let path { context["path"] = path }
        details.forEach { context[$0.key] = $0.value }
        AppLogStore.shared.emit([
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
    )
    gpNextCore = session.hasGpNext && session.gpNextCompatible
      ? try GpNextNativeCore(session: session)
      : nil
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func loadView() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "gardendless-game")
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
    scriptBridge = GameScriptBridge(webView: webView)
    scriptBridge.delegate = self
    contentController.addScriptMessageHandler(scriptBridge, contentWorld: .page, name: GameScriptBridge.name)
    navigationDelegate = GameNavigationDelegate(session: session)
    navigationDelegate.owner = self
    webView.navigationDelegate = navigationDelegate
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
    AppLogStore.shared.emit(
      source: "ios", level: "INFO", category: "game.host",
      event: "game_host_created", outcome: "succeeded",
      gameSessionId: session.sessionId
    )
    webView.load(URLRequest(url: session.entryURL, cachePolicy: .useProtocolCachePolicy))
  }

  override var prefersStatusBarHidden: Bool { true }
  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
  override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }

  @objc private func returnToLauncher() {
    exit(reason: "userReturned", message: nil)
  }

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
    AppLogStore.shared.emit([
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
    if let command { context["command"] = command }
    AppLogStore.shared.emit([
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

  func bridgeRequestedExport(command: String, id: String, arguments: [String: Any]) {
    if command != "host:export" {
      handleChunkedExport(command: command, id: id, arguments: arguments)
      return
    }
    guard let raw = arguments["url"] as? String,
          let url = URL(string: raw), isAllowedRemoteURL(url) else {
      scriptBridge.fail(id: id, code: "unsupported_export", message: "Export URL is not authorized")
      return
    }
    UIApplication.shared.open(url) { [weak self] opened in
      opened
        ? self?.scriptBridge.complete(id: id, value: NSNull())
        : self?.scriptBridge.fail(id: id, code: "external_open_failed", message: "Unable to open URL")
    }
  }

  private func handleChunkedExport(command: String, id: String, arguments: [String: Any]) {
    do {
      switch command {
      case "host:exportBegin":
        guard chunkedExport == nil, pendingExport == nil,
              let expected = arguments["totalBytes"] as? Int, expected >= 0,
              expected <= 512 * 1024 * 1024 else {
          throw GameSessionError.invalid("Export size is invalid or another export is active")
        }
        try FileManager.default.createDirectory(at: session.exportTemporaryRoot, withIntermediateDirectories: true)
        let name = safeFileName(arguments["suggestedFilename"] as? String ?? "gardendless-export.json")
        let file = session.exportTemporaryRoot.appendingPathComponent(".chunk-\(UUID().uuidString)-\(name)")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let token = "\(session.sessionId)-\(UUID().uuidString)"
        chunkedExport = ChunkedExport(
          token: token,
          file: file,
          handle: try FileHandle(forWritingTo: file),
          expectedBytes: expected,
          mimeType: arguments["mimeType"] as? String ?? "application/octet-stream",
          fileName: name
        )
        scriptBridge.complete(id: id, value: token)
      case "host:exportChunk":
        guard var export = chunkedExport,
              arguments["token"] as? String == export.token,
              arguments["index"] as? Int == export.nextIndex,
              let encoded = arguments["data"] as? String,
              let data = Data(base64Encoded: encoded), data.count <= 256 * 1024,
              export.written + data.count <= export.expectedBytes else {
          throw GameSessionError.invalid("Export chunk sequence is invalid")
        }
        try export.handle.write(contentsOf: data)
        export.written += data.count
        export.nextIndex += 1
        chunkedExport = export
        scriptBridge.complete(id: id, value: NSNull())
      case "host:exportCommit":
        guard let export = chunkedExport,
              arguments["token"] as? String == export.token,
              export.written == export.expectedBytes else {
          throw GameSessionError.invalid("Export did not receive every byte")
        }
        try export.handle.close()
        chunkedExport = nil
        pendingExport = (id, export.file)
        let picker = UIDocumentPickerViewController(forExporting: [export.file], asCopy: true)
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        present(picker, animated: true)
      case "host:exportAbort":
        if let export = chunkedExport, arguments["token"] as? String == export.token {
          try? export.handle.close()
          try? FileManager.default.removeItem(at: export.file)
          chunkedExport = nil
        }
        scriptBridge.complete(id: id, value: NSNull())
      default:
        throw GameSessionError.invalid("Unknown export command")
      }
    } catch {
      scriptBridge.fail(id: id, code: "export_failed", message: error.localizedDescription)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let id = pendingGpNextImportId {
      pendingGpNextImportId = nil
      scriptBridge.fail(id: id, code: "import_cancelled", message: "Import was cancelled")
      return
    }
    guard let export = pendingExport else { return }
    pendingExport = nil
    try? FileManager.default.removeItem(at: export.file)
    scriptBridge.fail(id: export.id, code: "export_cancelled", message: "Export was cancelled")
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

  func bridgeRequestedGpNext(id: String, request: [String: Any]) {
    guard let gpNextCore else {
      scriptBridge.fail(id: id, code: "gp_next_unavailable", message: "GP-Next compatibility is unavailable")
      return
    }
    gpNextCore.dispatch(request: request) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        switch result {
        case .failure(let error):
          self.scriptBridge.fail(id: id, code: "gp_next_error", message: error.localizedDescription)
        case .success(.value(let value)):
          self.scriptBridge.complete(id: id, value: value)
        case .success(.openURL(let url)):
          UIApplication.shared.open(url) { opened in
            opened
              ? self.scriptBridge.complete(id: id, value: NSNull())
              : self.scriptBridge.fail(id: id, code: "external_open_failed", message: "Unable to open URL")
          }
        case .success(.exportFile(let file)):
          guard self.pendingExport == nil else {
            self.scriptBridge.fail(id: id, code: "export_in_progress", message: "Another export is active")
            return
          }
          self.pendingExport = (id, file)
          let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
          picker.delegate = self
          self.present(picker, animated: true)
        case .success(.importPackages):
          self.beginGpNextImport(id: id)
        }
      }
    }
  }

  private func beginGpNextImport(id: String) {
    guard pendingGpNextImportId == nil, pendingExport == nil else {
      scriptBridge.fail(id: id, code: "gp_next_import_busy", message: "Another picker is active")
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
        for url in urls { try self.importGpNextPackage(url) }
        DispatchQueue.main.async { self.scriptBridge.complete(id: id, value: NSNull()) }
      } catch {
        DispatchQueue.main.async {
          self.scriptBridge.fail(id: id, code: "gp_next_import_failed", message: error.localizedDescription)
        }
      }
    }
  }

  private func importGpNextPackage(_ source: URL) throws -> String {
    let accessed = source.startAccessingSecurityScopedResource()
    defer { if accessed { source.stopAccessingSecurityScopedResource() } }
    let name = safeFileName(source.lastPathComponent)
    let ext = source.pathExtension.lowercased()
    let destinationDirectory: URL
    switch ext {
    case "zip":
      destinationDirectory = session.gpNextRoot.appendingPathComponent("packs", isDirectory: true)
    case "json", "json5":
      destinationDirectory = session.gpNextRoot.appendingPathComponent("patches", isDirectory: true)
    default:
      throw GameSessionError.invalid("不支持的 GP-Next 文件：\(name)")
    }
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    let incoming = destinationDirectory.appendingPathComponent(".\(name).incoming-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: source, to: incoming)
    defer { try? FileManager.default.removeItem(at: incoming) }
    if ext == "json" {
      _ = try JSONSerialization.jsonObject(with: Data(contentsOf: incoming))
    } else if ext == "json5" {
      guard (try incoming.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
        throw GameSessionError.invalid("\(name) 是空文件")
      }
    } else {
      guard zipContainsRootPackJSON(incoming) else {
        throw GameSessionError.invalid("\(name) 缺少根目录 pack.json")
      }
    }
    let destination = destinationDirectory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: destination.path) {
      guard confirmReplacement(name) else { return name }
    }
    let backup = destinationDirectory.appendingPathComponent(".\(name).backup-\(UUID().uuidString)")
    let existed = FileManager.default.fileExists(atPath: destination.path)
    if existed { try FileManager.default.moveItem(at: destination, to: backup) }
    do {
      try FileManager.default.moveItem(at: incoming, to: destination)
      if existed { try? FileManager.default.removeItem(at: backup) }
    } catch {
      if existed && !FileManager.default.fileExists(atPath: destination.path) {
        try? FileManager.default.moveItem(at: backup, to: destination)
      }
      throw error
    }
    return name
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
      alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in semaphore.signal() })
      alert.addAction(UIAlertAction(title: "替换", style: .destructive) { _ in
        confirmed = true
        semaphore.signal()
      })
      self.present(alert, animated: true)
    }
    return semaphore.wait(timeout: .now() + 300) == .success && confirmed
  }

  private func zipContainsRootPackJSON(_ url: URL) -> Bool {
    // A bounded central-directory scan avoids extracting untrusted archives in the game process.
    guard let handle = try? FileHandle(forReadingFrom: url),
          let size = try? handle.seekToEnd(), size >= 22 else { return false }
    defer { try? handle.close() }
    let tailSize = min(size, 65_557)
    try? handle.seek(toOffset: size - tailSize)
    guard let tail = try? handle.read(upToCount: Int(tailSize)) else { return false }
    let bytes = [UInt8](tail)
    guard let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: {
      bytes[$0] == 0x50 && bytes[$0 + 1] == 0x4b && bytes[$0 + 2] == 0x05 && bytes[$0 + 3] == 0x06
    }) else { return false }
    let centralOffset = UInt64(bytes[end + 16]) | UInt64(bytes[end + 17]) << 8 |
      UInt64(bytes[end + 18]) << 16 | UInt64(bytes[end + 19]) << 24
    let count = Int(bytes[end + 10]) | Int(bytes[end + 11]) << 8
    try? handle.seek(toOffset: centralOffset)
    for _ in 0..<count {
      guard let header = try? handle.read(upToCount: 46), header.count == 46 else { return false }
      let value = [UInt8](header)
      guard value[0...3].elementsEqual([0x50, 0x4b, 0x01, 0x02]) else { return false }
      let nameLength = Int(value[28]) | Int(value[29]) << 8
      let extraLength = Int(value[30]) | Int(value[31]) << 8
      let commentLength = Int(value[32]) | Int(value[33]) << 8
      guard let nameData = try? handle.read(upToCount: nameLength) else { return false }
      if String(data: nameData, encoding: .utf8)?.replacingOccurrences(of: "\\", with: "/") == "pack.json" {
        return true
      }
      let current = (try? handle.offset()) ?? 0
      try? handle.seek(toOffset: current + UInt64(extraLength + commentLength))
    }
    return false
  }

  func rendererDidTerminate() {
    AppLogStore.shared.emit(
      source: "ios", level: "ERROR", category: "game.webview",
      event: "webview_render_process_gone", outcome: "failed",
      code: "webview_render_process_gone", gameSessionId: session.sessionId
    )
    exit(reason: "rendererGone", message: "iOS WebContent process terminated")
  }

  func navigationDidFail(_ error: Error) {
    AppLogStore.shared.emit(
      source: "ios", level: "ERROR", category: "game.webview",
      event: "webview_page_load_finished", outcome: "failed",
      code: "webview_page_load_failed", message: error.localizedDescription,
      gameSessionId: session.sessionId, error: error
    )
    guard webView.url == nil else { return }
    exit(reason: "launchFailed", message: error.localizedDescription)
  }

  func navigationDidStart() {
    AppLogStore.shared.emit(
      source: "ios", level: "INFO", category: "game.webview",
      event: "webview_page_load_started", outcome: "started",
      gameSessionId: session.sessionId
    )
  }

  func navigationDidFinish() {
    AppLogStore.shared.emit(
      source: "ios", level: "INFO", category: "game.webview",
      event: "webview_page_load_finished", outcome: "succeeded",
      gameSessionId: session.sessionId
    )
  }

  func navigationWasBlocked() {
    AppLogStore.shared.emit(
      source: "ios", level: "WARN", category: "game.security",
      event: "navigation_blocked", outcome: "observed",
      gameSessionId: session.sessionId
    )
  }

  private func exit(reason: String, message: String?) {
    guard !exiting else { return }
    exiting = true
    AppLogStore.shared.emit(
      source: "ios",
      level: reason == "rendererGone" || reason == "launchFailed" ? "ERROR" : "INFO",
      category: "game.host", event: "game_host_finished",
      outcome: reason == "rendererGone" || reason == "launchFailed" ? "failed" : "succeeded",
      message: message, gameSessionId: session.sessionId,
      context: ["reason": reason]
    )
    _ = AppLogStore.shared.flush(timeout: 0.5)
    writeExitResult(reason: reason, message: message)
    cleanupWebView()
    onExit()
  }

  private func cleanupWebView() {
    guard !cleanedUp else { return }
    cleanedUp = true
    if let export = chunkedExport {
      try? export.handle.close()
      try? FileManager.default.removeItem(at: export.file)
      chunkedExport = nil
    }
    if let export = pendingExport {
      try? FileManager.default.removeItem(at: export.file)
      pendingExport = nil
    }
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: GameScriptBridge.name,
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
      "finishedAt": formatter.string(from: Date()),
      "message": message ?? NSNull(),
    ]
    if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
      try? data.write(to: output, options: .atomic)
    }
  }

  private func buildDocumentStartScript() -> String {
    let config: [String: Any] = [
      "platform": "ios",
      "origin": NativeGameSession.origin,
      "activationGeneration": session.activationGeneration,
      "hasGpNext": session.hasGpNext,
      "gpNextCompatible": session.gpNextCompatible,
      "gpNextVersion": session.gpNextVersion ?? NSNull(),
      "watermarkEnabled": session.watermarkEnabled,
      "autoCollectSunEnabled": session.autoCollectSunEnabled,
      "gpNextBaseDirectory": session.appRoot.path,
    ]
    let configData = try! JSONSerialization.data(withJSONObject: config)
    var source = "window.__gardendlessHostConfig=" + String(data: configData, encoding: .utf8)! + ";"
    var names = [
      "transport.js",
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

  private func safeFileName(_ value: String) -> String {
    let base = (value.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
    let cleaned = base
      .replacingOccurrences(of: "[\\x00-\\x1f:*?\"<>|]", with: "_", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty || cleaned == "." || cleaned == ".."
      ? "gardendless-export.json"
      : cleaned
  }

  private func isAllowedRemoteURL(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
    return session.allowedRemoteHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
  }

  deinit {
    if webView != nil { cleanupWebView() }
  }
}

private struct ChunkedExport {
  let token: String
  let file: URL
  let handle: FileHandle
  let expectedBytes: Int
  let mimeType: String
  let fileName: String
  var written = 0
  var nextIndex = 0
}
