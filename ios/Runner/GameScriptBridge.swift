import Foundation
import WebKit

protocol GameScriptBridgeDelegate: AnyObject {
  func bridgeRequestedReturnHome()
  func bridgeRequestedExport(command: String, id: String, arguments: [String: Any])
  func bridgeRequestedGpNext(id: String, request: [String: Any])
  func bridgeRequestedWatermark(_ enabled: Bool) throws
  func bridgeRequestedLog(id: String, arguments: [String: Any])
  func bridgeRejectedMessage(reason: String, command: String?)
}

final class GameScriptBridge: NSObject, WKScriptMessageHandlerWithReply {
  static let name = "gardendlessNative"
  static let maxMessageSize = 1024 * 1024

  weak var delegate: GameScriptBridgeDelegate?
  private weak var webView: WKWebView?
  private var activeRequestIds = Set<String>()
  private var destroyed = false

  init(webView: WKWebView) {
    self.webView = webView
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage,
    replyHandler: @escaping (Any?, String?) -> Void
  ) {
    guard !destroyed else {
      replyHandler(nil, "Bridge is destroyed")
      return
    }
    guard message.frameInfo.isMainFrame,
          message.frameInfo.securityOrigin.protocol == "gardendless-game",
          message.frameInfo.securityOrigin.host == "localhost",
          let raw = message.body as? String,
          raw.utf8.count <= Self.maxMessageSize else {
      delegate?.bridgeRejectedMessage(reason: "origin_frame_or_size_rejected", command: nil)
      replyHandler(nil, "Rejected bridge message")
      return
    }
    guard let data = raw.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = request["id"] as? String, !id.isEmpty,
          let command = request["command"] as? String, !command.isEmpty else {
      delegate?.bridgeRejectedMessage(reason: "invalid_json_or_fields", command: nil)
      replyHandler(nil, "Invalid bridge request")
      return
    }
    guard activeRequestIds.insert(id).inserted else {
      delegate?.bridgeRejectedMessage(reason: "duplicate_request_id", command: command)
      replyHandler(nil, "Duplicate bridge request id")
      respond(
        id: id,
        ok: false,
        payload: [
          "code": "duplicate_request_id",
          "message": "Bridge request id is already active",
        ],
        removeActive: false
      )
      return
    }
    replyHandler(["accepted": true], nil)
    do {
      switch command {
      case "host:returnHome", "host:return_home":
        complete(id: id, value: NSNull())
        delegate?.bridgeRequestedReturnHome()
      case "host:setWatermark", "host:set_watermark":
        let arguments = request["args"] as? [String: Any]
        try delegate?.bridgeRequestedWatermark(arguments?["enabled"] as? Bool ?? true)
        complete(id: id, value: NSNull())
      case "host:log":
        delegate?.bridgeRequestedLog(
          id: id,
          arguments: request["args"] as? [String: Any] ?? [:]
        )
      case "host:export", "host:exportBegin", "host:exportChunk", "host:exportCommit", "host:exportAbort":
        delegate?.bridgeRequestedExport(
          command: command,
          id: id,
          arguments: request["args"] as? [String: Any] ?? [:]
        )
      default:
        if request["namespace"] as? String == "gp-next" {
          delegate?.bridgeRequestedGpNext(id: id, request: request)
        } else {
          delegate?.bridgeRejectedMessage(reason: "unknown_command", command: command)
          fail(id: id, code: "unknown_command", message: "Unsupported host command: \(command)")
        }
      }
    } catch {
      fail(id: id, code: "native_error", message: error.localizedDescription)
    }
  }

  func complete(id: String, value: Any) {
    respond(id: id, ok: true, payload: value)
  }

  func fail(id: String, code: String, message: String) {
    respond(id: id, ok: false, payload: ["code": code, "message": message])
  }

  func destroy() {
    destroyed = true
    activeRequestIds.removeAll()
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
      activeRequestIds.remove(id)
    }
    var response: [String: Any] = ["id": id, "ok": ok]
    response[ok ? "value" : "error"] = payload
    guard !destroyed,
          JSONSerialization.isValidJSONObject(response),
          let data = try? JSONSerialization.data(withJSONObject: response),
          let json = String(data: data, encoding: .utf8) else { return }
    DispatchQueue.main.async { [weak self] in
      guard self?.destroyed == false else { return }
      self?.webView?.evaluateJavaScript(
        "window.__gardendlessTransport && window.__gardendlessTransport.resolve(\(json))"
      )
    }
  }
}
