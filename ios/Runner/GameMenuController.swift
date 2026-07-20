import WebKit

final class GameMenuController {
  private weak var webView: WKWebView?

  init(webView: WKWebView) {
    self.webView = webView
  }

  func open() {
    webView?.evaluateJavaScript("window.__gardendlessMenu && window.__gardendlessMenu.open()")
  }
}
