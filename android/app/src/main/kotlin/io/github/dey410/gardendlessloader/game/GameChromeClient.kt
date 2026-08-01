package io.github.dey410.gardendlessloader.game

import android.content.Intent
import android.net.Uri
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebView

class GameChromeClient(
    private val openFileChooser: (Intent, ValueCallback<Array<Uri>>) -> Unit,
) : WebChromeClient() {
    override fun onShowFileChooser(
        webView: WebView,
        filePathCallback: ValueCallback<Array<Uri>>,
        fileChooserParams: FileChooserParams,
    ): Boolean {
        val intent = runCatching { fileChooserParams.createIntent() }.getOrElse {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
            }
        }
        openFileChooser(intent, filePathCallback)
        return true
    }
}
