package io.github.dey410.gardendlessloader.game

import android.content.Intent
import android.net.Uri
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.ByteArrayInputStream

class GameWebViewClient(
    session: NativeGameSession,
    private val onRendererGone: (Boolean) -> Unit,
) : WebViewClient() {
    private val resolver = GameResourceResolver(java.io.File(session.resourceRoot))
    private val origin = Uri.parse(session.origin)
    private val allowedRemoteHosts = session.allowedRemoteHosts

    override fun shouldInterceptRequest(
        view: WebView,
        request: WebResourceRequest,
    ): WebResourceResponse? {
        val url = request.url
        if (url.scheme == origin.scheme && url.host == origin.host) {
            val response = resolver.resolve(
                url = url.toString(),
                method = request.method,
                requestHeaders = request.requestHeaders,
            )
            return WebResourceResponse(
                response.mimeType,
                response.encoding,
                response.statusCode,
                response.reason,
                response.headers,
                response.body,
            )
        }
        if (url.scheme == "https" && isAllowedRemoteHost(url.host)) {
            return null
        }
        return WebResourceResponse(
            "text/plain",
            "UTF-8",
            403,
            "Forbidden",
            mapOf("Content-Length" to "0"),
            ByteArrayInputStream(ByteArray(0)),
        )
    }

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        val url = request.url
        if (url.scheme == origin.scheme && url.host == origin.host) return false
        if (!request.isForMainFrame) return !isAllowedRemoteHost(url.host)
        if (url.scheme == "https" && isAllowedRemoteHost(url.host)) {
            view.context.startActivity(Intent(Intent.ACTION_VIEW, url))
        }
        return true
    }

    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
        onRendererGone(detail.didCrash())
        return true
    }

    private fun isAllowedRemoteHost(host: String?): Boolean {
        val normalized = host?.lowercase() ?: return false
        return allowedRemoteHosts.any { normalized == it || normalized.endsWith(".$it") }
    }
}
