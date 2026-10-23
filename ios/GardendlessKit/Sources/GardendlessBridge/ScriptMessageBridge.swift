import Foundation
import GardendlessCore
import WebKit

public protocol ScriptBridgeDelegate: AnyObject {
  func bridgeRequestedReturnHome()
  func bridgeRequestedHaptic(kind: String?)
  func bridgeRequestedLog(id: String, arguments: [String: Any])
  func bridgeRequestedExport(command: String, id: String, arguments: [String: Any])
  func bridgeRequestedFile(command: String, id: String, arguments: [String: Any])
  func bridgeRequestedGpNext(id: String, request: [String: Any])
  func bridgeRejectedMessage(reason: String, command: String?)
}

public final class ScriptMessageBridge: NSObject, WKScriptMessageHandlerWithReply {
  public static let name = BridgeConstants.handlerName

  public weak var delegate: ScriptBridgeDelegate?
  private weak var webView: WKWebView?
  private let stateLock = NSLock()
  private var activeRequestIds = Set<String>()
  private var destroyed = false

  public init(webView: WKWebView) {
    self.webView = webView
  }

  public func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage,
    replyHandler: @escaping (Any?, String?) -> Void
  ) {
    guard !destroyed else {
      replyHandler(nil, "Bridge is destroyed")
      return
    }
    guard message.frameInfo.isMainFrame,
          message.frameInfo.securityOrigin.protocol == GameOrigin.scheme,
          message.frameInfo.securityOrigin.host == GameOrigin.host,
          let raw = message.body as? String else {
      delegate?.bridgeRejectedMessage(reason: "origin_frame_or_size_rejected", command: nil)
      replyHandler(nil, "Rejected bridge message")
      return
    }
    guard let request = try? BridgeRequest.decode(raw) else {
      delegate?.bridgeRejectedMessage(reason: "invalid_json_or_fields", command: nil)
      replyHandler(nil, "Invalid bridge request")
      return
    }
    stateLock.lock()
    let duplicate = activeRequestIds.contains(request.id)
    let full = activeRequestIds.count >= BridgeConstants.pendingRequestLimit(
      command: request.command, args: request.args
    )
    let inserted = !destroyed && !duplicate && !full
    if inserted { activeRequestIds.insert(request.id) }
    stateLock.unlock()
    guard inserted else {
      let code = duplicate ? "duplicate_request_id" : "bridge_busy"
      delegate?.bridgeRejectedMessage(reason: code, command: request.command)
      replyHandler(nil, code)
      // A duplicate must not settle the original request's pending promise.
      if !duplicate {
        respond(id: request.id, ok: false,
                payload: ["code": code, "message": "Bridge request limit reached"],
                removeActive: false)
      }
      return
    }
    replyHandler(["accepted": true], nil)
    switch request.command {
      case _ where BridgeCommand.isReturnHome(request.command):
        complete(id: request.id, value: NSNull())
        delegate?.bridgeRequestedReturnHome()
      case BridgeCommand.haptic.rawValue:
        complete(id: request.id, value: NSNull())
        delegate?.bridgeRequestedHaptic(kind: request.args["kind"] as? String)
      case BridgeCommand.log.rawValue:
        delegate?.bridgeRequestedLog(id: request.id, arguments: request.args)
      case _ where BridgeCommand.isFile(request.command):
        delegate?.bridgeRequestedFile(
          command: request.command, id: request.id, arguments: request.args
        )
      case _ where BridgeCommand.isExport(request.command):
        delegate?.bridgeRequestedExport(
          command: request.command,
          id: request.id,
          arguments: request.args
        )
      default:
        if request.namespace == "gp-next" {
          delegate?.bridgeRequestedGpNext(id: request.id, request: [
            "id": request.id,
            "command": request.command,
            "args": request.args,
            "options": request.options,
          ])
        } else {
          delegate?.bridgeRejectedMessage(
            reason: "unknown_command",
            command: request.command
          )
          fail(
            id: request.id,
            code: "unknown_command",
            message: "Unsupported host command: \(request.command)"
          )
        }
    }
  }

  public func complete(id: String, value: Any) {
    respond(id: id, ok: true, payload: value)
  }

  public func fail(id: String, code: String, message: String) {
    respond(id: id, ok: false, payload: ["code": code, "message": message])
  }

  public func destroy() {
    stateLock.lock()
    destroyed = true
    activeRequestIds.removeAll()
    stateLock.unlock()
    webView?.evaluateJavaScript(
      "window.__gardendlessTransport && window.__gardendlessTransport.rejectAll('host_destroyed','Game host was destroyed')"
    )
  }

  private func respond(
    id: String,
    ok: Bool,
    payload: Any,
    removeActive: Bool = true
  ) {
    if removeActive {
      stateLock.lock()
      activeRequestIds.remove(id)
      stateLock.unlock()
    }
    var response: [String: Any] = ["id": id, "ok": ok]
    response[ok ? "value" : "error"] = payload
    guard JSONSerialization.isValidJSONObject(response),
          let data = try? JSONSerialization.data(withJSONObject: response),
          let json = String(data: data, encoding: .utf8) else {
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.stateLock.lock()
      let alive = !self.destroyed
      self.stateLock.unlock()
      guard alive else { return }
      self.webView?.evaluateJavaScript(
        "window.__gardendlessTransport && window.__gardendlessTransport.resolve(\(json))"
      )
    }
  }
}
