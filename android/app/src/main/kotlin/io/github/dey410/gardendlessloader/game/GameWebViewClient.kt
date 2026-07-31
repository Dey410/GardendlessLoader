package io.github.dey410.gardendlessloader.game

import android.content.Intent
import android.net.Uri
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.github.dey410.gardendlessloader.logging.AppLogStore
import java.io.ByteArrayInputStream

class GameWebViewClient(
    private val session: NativeGameSession,
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
            if (response.statusCode >= 400) {
                val code = when (response.statusCode) {
                    403 -> "resource_path_forbidden"
                    404 -> "resource_file_not_found"
                    405 -> "resource_method_not_allowed"
                    else -> "resource_read_failed"
                }
                AppLogStore.emit(
                    source = "android",
                    level = if (response.statusCode == 404) "WARN" else "ERROR",
                    category = "game.resource",
                    event = "resource_request_failed",
                    outcome = "failed",
                    code = code,
                    gameSessionId = session.sessionId,
                    context = mapOf("path" to url.path, "statusCode" to response.statusCode),
                )
            } else if (response.mimeType == "application/octet-stream") {
                AppLogStore.emit(
                    source = "android",
                    level = "WARN",
                    category = "game.resource",
                    event = "resource_request_failed",
                    outcome = "failed",
                    code = "resource_mime_mismatch",
                    gameSessionId = session.sessionId,
                    context = mapOf(
                        "path" to url.path,
                        "statusCode" to response.statusCode,
                        "expectedMime" to "known resource MIME",
                        "actualMime" to response.mimeType,
                    ),
                )
            }
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
        AppLogStore.emit(
            source = "android",
            level = "WARN",
            category = "game.security",
            event = "network_request_blocked",
            outcome = "observed",
            gameSessionId = session.sessionId,
            context = mapOf("url" to "${url.scheme}://${url.host ?: ""}${url.path ?: ""}"),
        )
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
        AppLogStore.emit(
            source = "android",
            level = "WARN",
            category = "game.security",
            event = "navigation_blocked",
            outcome = "observed",
            gameSessionId = session.sessionId,
            context = mapOf("url" to "${url.scheme}://${url.host ?: ""}${url.path ?: ""}"),
        )
        return true
    }

    override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
        AppLogStore.emit(
            source = "android", level = "INFO", category = "game.webview",
            event = "webview_page_load_started", outcome = "started",
            gameSessionId = session.sessionId,
        )
    }

    override fun onPageFinished(view: WebView, url: String?) {
        AppLogStore.emit(
            source = "android", level = "INFO", category = "game.webview",
            event = "webview_page_load_finished", outcome = "succeeded",
            gameSessionId = session.sessionId,
        )
    }

    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
        if (!request.isForMainFrame) return
        AppLogStore.emit(
            source = "android", level = "ERROR", category = "game.webview",
            event = "webview_page_load_finished", outcome = "failed",
            code = "webview_page_load_failed", message = error.description.toString(),
            gameSessionId = session.sessionId,
        )
    }

    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
        AppLogStore.emit(
            source = "android", level = "ERROR", category = "game.webview",
            event = "webview_render_process_gone", outcome = "failed",
            code = "webview_render_process_gone", gameSessionId = session.sessionId,
            context = mapOf("crashed" to detail.didCrash()),
        )
        onRendererGone(detail.didCrash())
        return true
    }

    private fun isAllowedRemoteHost(host: String?): Boolean {
        val normalized = host?.lowercase() ?: return false
        return allowedRemoteHosts.any { normalized == it || normalized.endsWith(".$it") }
    }
}
