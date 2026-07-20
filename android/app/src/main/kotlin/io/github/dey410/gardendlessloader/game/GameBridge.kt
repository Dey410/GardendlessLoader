package io.github.dey410.gardendlessloader.game

import android.net.Uri
import android.webkit.WebView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import org.json.JSONObject
import java.io.File

class GameBridge(
    private val activity: GameActivity,
    private val webView: WebView,
    private val session: NativeGameSession,
) : WebViewCompat.WebMessageListener {
    private val activeRequestIds = mutableSetOf<String>()
    private var destroyed = false

    override fun onPostMessage(
        view: WebView,
        message: WebMessageCompat,
        sourceOrigin: Uri,
        isMainFrame: Boolean,
        replyProxy: JavaScriptReplyProxy,
    ) {
        if (destroyed || !isMainFrame || sourceOrigin.toString() != session.origin) return
        val raw = message.data ?: return
        if (raw.length > MAX_MESSAGE_SIZE) {
            respond(null, false, error("message_too_large", "Bridge request is too large"))
            return
        }
        val request = runCatching { JSONObject(raw) }.getOrElse {
            respond(null, false, error("invalid_message", "Bridge request is not valid JSON"))
            return
        }
        val id = request.optString("id")
        val command = request.optString("command")
        if (id.isBlank() || command.isBlank()) {
            respond(id.takeIf { it.isNotBlank() }, false, error("invalid_message", "Bridge id or command is empty"))
            return
        }
        synchronized(activeRequestIds) {
            if (!activeRequestIds.add(id)) {
                respond(
                    id,
                    false,
                    error("duplicate_request_id", "Bridge request id is already active"),
                    removeActive = false,
                )
                return
            }
        }
        try {
            when (command) {
                "host:returnHome", "host:return_home" -> {
                    respond(id, true, JSONObject.NULL)
                    activity.returnToLauncher(GameExitReason.USER_RETURNED, null)
                }
                "host:setWatermark", "host:set_watermark" -> {
                    val enabled = request.optJSONObject("args")?.optBoolean("enabled", true) ?: true
                    activity.persistWatermark(enabled)
                    respond(id, true, JSONObject.NULL)
                }
                "host:export" -> activity.beginExport(id, request.optJSONObject("args") ?: JSONObject())
                "host:exportBegin" -> activity.beginChunkedExport(id, request.optJSONObject("args") ?: JSONObject())
                "host:exportChunk" -> activity.appendChunkedExport(id, request.optJSONObject("args") ?: JSONObject())
                "host:exportCommit" -> activity.commitChunkedExport(id, request.optJSONObject("args") ?: JSONObject())
                "host:exportAbort" -> activity.abortChunkedExport(id, request.optJSONObject("args") ?: JSONObject())
                else -> {
                    if (request.optString("namespace") == "gp-next") {
                        activity.dispatchGpNext(id, request)
                    } else {
                        respond(id, false, error("unknown_command", "Unsupported host command: $command"))
                    }
                }
            }
        } catch (error: Exception) {
            respond(id, false, error("native_error", error.message ?: error.toString()))
        }
    }

    fun complete(id: String, value: Any?) = respond(id, true, value ?: JSONObject.NULL)

    fun fail(id: String, code: String, message: String) = respond(id, false, error(code, message))

    fun destroy() {
        destroyed = true
        synchronized(activeRequestIds) { activeRequestIds.clear() }
        WebViewCompat.removeWebMessageListener(webView, BRIDGE_NAME)
        webView.evaluateJavascript(
            "window.__gardendlessTransport && window.__gardendlessTransport.rejectAll('host_destroyed','Game host was destroyed')",
            null,
        )
    }

    private fun respond(
        id: String?,
        ok: Boolean,
        value: Any,
        removeActive: Boolean = true,
    ) {
        if (id != null && removeActive) {
            synchronized(activeRequestIds) { activeRequestIds.remove(id) }
        }
        if (destroyed || id == null) return
        val response = JSONObject().put("id", id).put("ok", ok)
        if (ok) response.put("value", value) else response.put("error", value)
        val encoded = JSONObject.quote(response.toString())
        webView.post {
            if (!destroyed) {
                webView.evaluateJavascript(
                    "window.__gardendlessTransport && window.__gardendlessTransport.resolve($encoded)",
                    null,
                )
            }
        }
    }

    private fun error(code: String, message: String) =
        JSONObject().put("code", code).put("message", message)

    companion object {
        const val BRIDGE_NAME = "gardendlessNative"
        const val MAX_MESSAGE_SIZE = 1024 * 1024
    }
}

enum class GameExitReason(val wireName: String) {
    NORMAL("normal"),
    USER_RETURNED("userReturned"),
    RENDERER_GONE("rendererGone"),
    LAUNCH_FAILED("launchFailed"),
    SYSTEM_TERMINATED("systemTerminated"),
}
