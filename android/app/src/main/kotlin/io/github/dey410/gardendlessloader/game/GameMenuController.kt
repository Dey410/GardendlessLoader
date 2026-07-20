package io.github.dey410.gardendlessloader.game

import android.webkit.WebView

class GameMenuController(private val webView: WebView) {
    fun open() {
        webView.evaluateJavascript(
            "window.__gardendlessMenu && window.__gardendlessMenu.open()",
            null,
        )
    }
}
