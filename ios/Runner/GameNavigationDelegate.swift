import UIKit
import WebKit

final class GameNavigationDelegate: NSObject, WKNavigationDelegate {
  private let session: NativeGameSession
  weak var owner: GameViewController?

  init(session: NativeGameSession) {
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
    if url.scheme == "gardendless-game", url.host == "localhost" {
      decisionHandler(.allow)
      return
    }
    guard navigationAction.targetFrame?.isMainFrame != false,
          url.scheme == "https", isAllowedRemoteHost(url.host) else {
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
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    owner?.navigationDidFail(error)
  }

  private func isAllowedRemoteHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return session.allowedRemoteHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
  }
}
