import Foundation
import WebKit

final class GameAudioBridge: NSObject, WKScriptMessageHandler, NativeSfxEngineDelegate {
  static let name = "gardendlessAudio"

  private let engine: NativeSfxEngine
  private let webViewProvider: () -> WKWebView?
  private var destroyed = false

  init(engine: NativeSfxEngine, webViewProvider: @escaping () -> WKWebView?) {
    self.engine = engine
    self.webViewProvider = webViewProvider
    super.init()
    engine.delegate = self
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard !destroyed, message.frameInfo.isMainFrame,
          message.frameInfo.securityOrigin.protocol == "gardendless-game",
          message.frameInfo.securityOrigin.host == "localhost",
          let body = message.body as? [String: Any],
          let command = body["command"] as? String else { return }

    switch command {
    case "register":
      if let url = validatedURL(body) { engine.register(url) }
    case "play":
      guard let id = body["elementId"] as? String, !id.isEmpty,
            let url = validatedURL(body),
            let volume = body["volume"] as? NSNumber,
            let playbackRate = body["playbackRate"] as? NSNumber,
            playbackRate.doubleValue == 1,
            let loop = body["loop"] as? Bool, !loop else { return }
      engine.play(elementId: id, url: url, volume: volume.floatValue)
    case "stop":
      if let id = body["elementId"] as? String { engine.stop(elementId: id) }
    case "release":
      if let id = body["elementId"] as? String { engine.release(elementId: id) }
    case "stopAll":
      engine.stopAll()
    case "setMasterVolume":
      if let volume = body["volume"] as? NSNumber { engine.setMasterVolume(volume.floatValue) }
    default:
      break
    }
  }

  func nativeSfxEngineDidProduce(_ result: NativeSfxEngine.PlayResult) {
    guard !destroyed else { return }
    let function: String
    let elementId: String
    switch result {
    case .ended(let id):
      function = "__gardendlessNativeAudioEnded"
      elementId = id
    case .fallback(let id, _):
      function = "__gardendlessNativeAudioFallback"
      elementId = id
    }
    guard let argument = JavaScriptArgumentEncoder.string(elementId) else { return }
    DispatchQueue.main.async { [weak self] in
      self?.webViewProvider()?.evaluateJavaScript("window.\(function)(\(argument));")
    }
  }

  func destroy() {
    destroyed = true
    engine.delegate = nil
    engine.stopAll()
  }

  private func validatedURL(_ body: [String: Any]) -> URL? {
    guard let raw = body["url"] as? String, let url = URL(string: raw),
          url.scheme == "gardendless-game", url.host == "localhost" else { return nil }
    return url
  }
}
