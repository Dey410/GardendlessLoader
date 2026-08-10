package io.github.dey410.gardendlessloader.game

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.provider.OpenableColumns
import android.util.Base64
import android.view.View
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.github.dey410.gardendlessloader.MainActivity
import io.github.dey410.gardendlessloader.prepareForDocumentPicker
import io.github.dey410.gardendlessloader.restoreLandscapeOrientation
import io.github.dey410.gardendlessloader.logging.AppLogStore
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.BufferedOutputStream
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.zip.ZipFile
import kotlin.concurrent.thread

class GameActivity : Activity() {
    private lateinit var session: NativeGameSession
    private lateinit var webView: WebView
    private lateinit var bridge: GameBridge
    private lateinit var gpNextCore: GpNextNativeCore
    private var fileChooserCallback: ValueCallback<Array<Uri>>? = null
    private var pendingExport: PendingExport? = null
    private var chunkedExport: ChunkedExport? = null
    private var pendingGpImportRequestId: String? = null
    private var returning = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        enterImmersiveMode()
        val rawSession = intent.getStringExtra(EXTRA_SESSION)
        try {
            session = GameSessionCodec.decode(requireNotNull(rawSession) { "Missing game session" })
            AppLogStore.emit(
                source = "android", level = "INFO", category = "game.host",
                event = "game_host_created", outcome = "succeeded",
                gameSessionId = session.sessionId,
            )
            configureWebView()
        } catch (error: Exception) {
            AppLogStore.emit(
                source = "android", level = "ERROR", category = "game.host",
                event = "game_host_launch_finished", outcome = "failed",
                code = "game_host_launch_failed", error = error,
            )
            writeExitResult(
                rawSession?.let { runCatching { JSONObject(it).optString("sessionId") }.getOrNull() }
                    ?: "unknown",
                GameExitReason.LAUNCH_FAILED,
                error.message ?: error.toString(),
                rawSession?.let { runCatching { JSONObject(it).optString("resourceRoot") }.getOrNull() },
            )
            startActivity(Intent(this, MainActivity::class.java))
            finish()
        }
    }

    private fun configureWebView() {
        check(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            "Installed Android System WebView lacks document-start injection"
        }
        check(WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            "Installed Android System WebView lacks origin-scoped messaging"
        }
        webView = WebView(this).apply {
            setBackgroundColor(Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.setSupportMultipleWindows(false)
            settings.mediaPlaybackRequiresUserGesture = false
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.safeBrowsingEnabled = true
            setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, false)
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        bridge = GameBridge(this, webView, session)
        if (session.hasGpNext && session.gpNextCompatible) {
            gpNextCore = GpNextNativeCore(this, session, bridge)
        }
        WebViewCompat.addWebMessageListener(
            webView,
            GameBridge.BRIDGE_NAME,
            setOf(session.origin),
            bridge,
        )
        val documentStartScript = buildDocumentStartScript()
        WebViewCompat.addDocumentStartJavaScript(
            webView,
            documentStartScript,
            setOf(session.origin),
        )
        webView.webViewClient = GameWebViewClient(session) { crashed ->
            returnToLauncher(
                GameExitReason.RENDERER_GONE,
                if (crashed) "Android WebView renderer crashed" else "Android WebView renderer exited",
            )
        }
        webView.webChromeClient = GameChromeClient(::openFileChooser)
        val viewport = GameViewportLayout(this).apply {
            addView(webView)
        }
        setContentView(viewport)
        webView.loadUrl(session.entryUrl)
    }

    private fun buildDocumentStartScript(): String {
        val config = JSONObject()
            .put("platform", "android")
            .put("origin", session.origin)
            .put("activationGeneration", session.activationGeneration)
            .put("hasGpNext", session.hasGpNext)
            .put("gpNextCompatible", session.gpNextCompatible)
            .put("gpNextVersion", session.gpNextVersion ?: JSONObject.NULL)
            .put("watermarkEnabled", session.watermarkEnabled)
            .put("autoCollectSunEnabled", session.autoCollectSunEnabled)
            .put("gpNextBaseDirectory", session.appRoot)
        val names = buildList {
            add("transport.js")
            add("bootstrap.js")
            add("logging.js")
            add("auto_sun.js")
            add("touch_patch.js")
            add("export_download_patch.js")
            if (session.hasGpNext && session.gpNextCompatible) {
                add("gp_next_core.js")
                add("gp_next_compat_bridge.js")
            }
            add("watermark.js")
        }
        return buildString {
            append("window.__gardendlessHostConfig=")
            append(config.toString())
            append(';')
            for (name in names) {
                assets.open("flutter_assets/assets/game_bridge/$name").bufferedReader().use {
                    append('\n')
                    append(it.readText())
                }
            }
        }
    }

    private fun openFileChooser(intent: Intent, callback: ValueCallback<Array<Uri>>) {
        fileChooserCallback?.onReceiveValue(null)
        fileChooserCallback = callback
        launchDocumentPicker(intent, REQUEST_FILE_CHOOSER) {
            fileChooserCallback = null
            callback.onReceiveValue(null)
        }
    }

    fun beginExport(requestId: String, args: JSONObject) {
        if (pendingExport != null) {
            bridge.fail(requestId, "export_in_progress", "Another export is already active")
            return
        }
        val uri = runCatching { Uri.parse(args.optString("url")) }.getOrNull()
        val host = uri?.host?.lowercase()
        if (uri?.scheme != "https" || host == null ||
            session.allowedRemoteHosts.none { host == it || host.endsWith(".$it") }
        ) {
            bridge.fail(requestId, "unsupported_export", "Export URL is not authorized")
            return
        }
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
            .onSuccess { bridge.complete(requestId, null) }
            .onFailure { bridge.fail(requestId, "external_open_failed", it.message ?: it.toString()) }
    }

    fun beginChunkedExport(requestId: String, args: JSONObject) {
        if (chunkedExport != null || pendingExport != null) {
            bridge.fail(requestId, "export_in_progress", "Another export is already active")
            return
        }
        val totalBytes = args.optLong("totalBytes", -1)
        if (totalBytes < 0 || totalBytes > MAX_EXPORT_BYTES) {
            bridge.fail(requestId, "invalid_export_size", "Export size is invalid")
            return
        }
        val name = safeFileName(args.optString("suggestedFilename").ifBlank { "gardendless-export.json" })
        val directory = File(session.exportTemporaryRoot).apply { mkdirs() }
        val file = File(directory, ".chunk-${System.nanoTime()}-$name")
        val token = "${session.sessionId}-${System.nanoTime()}"
        chunkedExport = ChunkedExport(
            token, file, BufferedOutputStream(FileOutputStream(file)), totalBytes,
            args.optString("mimeType").ifBlank { "application/octet-stream" }, name,
        )
        bridge.complete(requestId, token)
    }

    fun appendChunkedExport(requestId: String, args: JSONObject) {
        val export = chunkedExport
        if (export == null || args.optString("token") != export.token || args.optInt("index", -1) != export.nextIndex) {
            bridge.fail(requestId, "invalid_export_chunk", "Export chunk sequence is invalid")
            return
        }
        runCatching {
            val bytes = Base64.decode(args.getString("data"), Base64.NO_WRAP)
            require(bytes.size <= MAX_EXPORT_CHUNK_BYTES) { "Export chunk is too large" }
            require(export.written + bytes.size <= export.expectedBytes) { "Export exceeds declared size" }
            export.output.write(bytes)
            export.written += bytes.size
            export.nextIndex += 1
        }.onSuccess { bridge.complete(requestId, null) }
            .onFailure { abortChunkedExport(requestId, args, it.message ?: it.toString()) }
    }

    fun commitChunkedExport(requestId: String, args: JSONObject) {
        val export = chunkedExport
        if (export == null || args.optString("token") != export.token || export.written != export.expectedBytes) {
            bridge.fail(requestId, "incomplete_export", "Export did not receive every byte")
            return
        }
        export.output.close()
        chunkedExport = null
        pendingExport = PendingExport(requestId, export.file)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = exportMimeType(export.fileName, export.mimeType)
            putExtra(Intent.EXTRA_TITLE, export.fileName)
        }
        launchDocumentPicker(intent, REQUEST_EXPORT) {
            pendingExport = null
            export.file.delete()
            bridge.fail(requestId, "export_picker_failed", it.message ?: it.toString())
        }
    }

    fun abortChunkedExport(requestId: String, args: JSONObject) =
        abortChunkedExport(requestId, args, null)

    private fun abortChunkedExport(requestId: String, args: JSONObject, failure: String?) {
        val export = chunkedExport
        if (export != null && args.optString("token") == export.token) {
            runCatching { export.output.close() }
            export.file.delete()
            chunkedExport = null
        }
        if (failure == null) bridge.complete(requestId, null)
        else bridge.fail(requestId, "invalid_export_chunk", failure)
    }

    fun dispatchGpNext(requestId: String, request: JSONObject) {
        if (!::gpNextCore.isInitialized) {
            bridge.fail(requestId, "gp_next_unavailable", "GP-Next compatibility is unavailable")
            return
        }
        gpNextCore.dispatch(requestId, request)
    }

    fun openGpNextUrl(raw: String, requestId: String) {
        val uri = runCatching { Uri.parse(raw) }.getOrNull()
        val host = uri?.host?.lowercase()
        if (uri == null || (uri.scheme != "https" && uri.scheme != "http") ||
            host == null || session.allowedRemoteHosts.none { host == it || host.endsWith(".$it") }
        ) {
            bridge.fail(requestId, "external_url_blocked", "GP-Next 请求打开了未授权网址")
            return
        }
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
            .onSuccess { bridge.complete(requestId, null) }
            .onFailure { bridge.fail(requestId, "external_open_failed", it.message ?: it.toString()) }
    }

    fun beginGpNextPackageImport(requestId: String) {
        if (pendingGpImportRequestId != null) {
            bridge.fail(requestId, "gp_next_import_busy", "已有 GP-Next 文件选择正在进行")
            return
        }
        pendingGpImportRequestId = requestId
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/json", "text/plain"))
        }
        launchDocumentPicker(intent, REQUEST_GP_NEXT_IMPORT) {
            pendingGpImportRequestId = null
            bridge.fail(requestId, "gp_next_picker_failed", it.message ?: it.toString())
        }
    }

    fun beginExistingFileExport(requestId: String, file: File) {
        if (pendingExport != null) {
            bridge.fail(requestId, "export_in_progress", "Another export is already active")
            return
        }
        pendingExport = PendingExport(requestId, file)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = exportMimeType(file.name, "application/json")
            putExtra(Intent.EXTRA_TITLE, file.name)
        }
        launchDocumentPicker(intent, REQUEST_EXPORT) {
            pendingExport = null
            bridge.fail(requestId, "export_picker_failed", it.message ?: it.toString())
        }
    }

    fun persistWatermark(enabled: Boolean) {
        val file = File(session.appRoot, "app_settings.json")
        val temporary = File(file.path + ".tmp")
        temporary.writeText(JSONObject().put("watermarkEnabled", enabled).toString(2) + "\n")
        if (!temporary.renameTo(file)) throw IllegalStateException("Cannot persist watermark setting")
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_FILE_CHOOSER ||
            requestCode == REQUEST_EXPORT ||
            requestCode == REQUEST_GP_NEXT_IMPORT
        ) {
            restoreGameOrientation()
        }
        when (requestCode) {
            REQUEST_GP_NEXT_IMPORT -> {
                val requestId = pendingGpImportRequestId
                pendingGpImportRequestId = null
                if (requestId == null) return
                if (resultCode != RESULT_OK || data == null) {
                    bridge.fail(requestId, "import_cancelled", "Import was cancelled")
                    return
                }
                val uris = buildList {
                    data.data?.let(::add)
                    val clip = data.clipData
                    if (clip != null) for (index in 0 until clip.itemCount) add(clip.getItemAt(index).uri)
                }.distinct()
                thread(name = "GardendlessGpNextImport") {
                    runCatching { importGpNextPackages(uris) }
                        .onSuccess { runOnUiThread { bridge.complete(requestId, null) } }
                        .onFailure { error -> runOnUiThread {
                            bridge.fail(requestId, "gp_next_import_failed", error.message ?: error.toString())
                        } }
                }
            }
            REQUEST_FILE_CHOOSER -> {
                val callback = fileChooserCallback
                fileChooserCallback = null
                callback?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data))
            }
            REQUEST_EXPORT -> {
                val export = pendingExport
                pendingExport = null
                if (export == null) return
                if (resultCode != RESULT_OK || data?.data == null) {
                    export.file.delete()
                    bridge.fail(export.requestId, "export_cancelled", "Export was cancelled")
                    return
                }
                thread(name = "GardendlessExportCopy") {
                    runCatching {
                        contentResolver.openOutputStream(data.data!!, "w").use { output ->
                            requireNotNull(output) { "Cannot open export destination" }
                            export.file.inputStream().use { input -> input.copyTo(output, 128 * 1024) }
                        }
                    }.onSuccess {
                        runOnUiThread { bridge.complete(export.requestId, null) }
                    }.onFailure {
                        runOnUiThread {
                            bridge.fail(export.requestId, "export_failed", it.message ?: it.toString())
                        }
                    }.also {
                        export.file.delete()
                    }
                }
            }
            else -> super.onActivityResult(requestCode, resultCode, data)
        }
    }

    @Deprecated("Invoked by the Android framework")
    override fun onBackPressed() {
        returnToLauncher(GameExitReason.USER_RETURNED, null)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enterImmersiveMode()
    }

    fun returnToLauncher(reason: GameExitReason, message: String?) {
        if (returning) return
        returning = true
        AppLogStore.emit(
            source = "android",
            level = if (reason == GameExitReason.RENDERER_GONE || reason == GameExitReason.LAUNCH_FAILED) "ERROR" else "INFO",
            category = "game.host",
            event = "game_host_finished",
            outcome = if (reason == GameExitReason.RENDERER_GONE || reason == GameExitReason.LAUNCH_FAILED) "failed" else "succeeded",
            code = if (reason == GameExitReason.RENDERER_GONE) "webview_render_process_gone" else null,
            message = message,
            gameSessionId = session.sessionId,
            context = mapOf("reason" to reason.wireName),
        )
        AppLogStore.flush(500)
        writeExitResult(session.sessionId, reason, message, session.resourceRoot)
        startActivity(Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        })
        finish()
    }

    override fun onDestroy() {
        chunkedExport?.let { runCatching { it.output.close() }; it.file.delete() }
        chunkedExport = null
        pendingExport?.file?.delete()
        pendingExport = null
        fileChooserCallback?.onReceiveValue(null)
        fileChooserCallback = null
        if (::bridge.isInitialized) bridge.destroy()
        if (::webView.isInitialized) {
            webView.stopLoading()
            webView.webChromeClient = null
            webView.webViewClient = android.webkit.WebViewClient()
            webView.removeAllViews()
            webView.destroy()
        }
        super.onDestroy()
    }

    private fun enterImmersiveMode() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
    }

    private fun launchDocumentPicker(
        intent: Intent,
        requestCode: Int,
        onFailure: (Throwable) -> Unit,
    ) {
        prepareForDocumentPicker()
        runCatching { startActivityForResult(intent, requestCode) }.onFailure {
            restoreGameOrientation()
            onFailure(it)
        }
    }

    private fun restoreGameOrientation() {
        restoreLandscapeOrientation()
    }

    private fun exportMimeType(fileName: String, declaredMimeType: String): String =
        ExportDocumentSpec.resolveMimeType(fileName, declaredMimeType) { extension ->
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        }

    private fun safeFileName(value: String): String {
        val cleaned = File(value.replace('\\', '/')).name
            .replace(Regex("[\\u0000-\\u001f:*?\"<>|]"), "_")
            .trim()
        return cleaned.takeIf { it.isNotEmpty() && it != "." && it != ".." }
            ?: "gardendless-export.json"
    }

    private fun importGpNextPackages(uris: List<Uri>): List<String> {
        val imported = mutableListOf<String>()
        for (uri in uris) {
            val displayName = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
                ?: uri.lastPathSegment ?: "gp-next-file"
            val name = safeFileName(displayName)
            val extension = name.substringAfterLast('.', "").lowercase()
            val destinationDirectory = when (extension) {
                "zip" -> File(session.gpNextRoot, "packs")
                "json", "json5" -> File(session.gpNextRoot, "patches")
                else -> throw IllegalArgumentException("不支持的 GP-Next 文件：$name")
            }.apply { mkdirs() }
            val incoming = File(destinationDirectory, ".$name.incoming-${System.nanoTime()}")
            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "无法读取 $name" }
                incoming.outputStream().use { output -> input.copyTo(output, 128 * 1024) }
            }
            try {
                if (extension == "zip") {
                    ZipFile(incoming).use { zip -> require(zip.getEntry("pack.json") != null) { "$name 缺少根目录 pack.json" } }
                } else if (extension == "json") {
                    val text = incoming.readText()
                    runCatching { JSONObject(text) }.recoverCatching { org.json.JSONArray(text) }.getOrThrow()
                } else {
                    require(incoming.length() > 0) { "$name 是空文件" }
                }
                val destination = File(destinationDirectory, name)
                if (destination.exists() && !confirmReplacement(name)) continue
                val backup = File(destinationDirectory, ".$name.backup-${System.nanoTime()}")
                if (destination.exists() && !destination.renameTo(backup)) error("无法暂存旧文件")
                try {
                    if (!incoming.renameTo(destination)) error("无法激活新文件")
                    if (backup.exists()) backup.delete()
                } catch (error: Exception) {
                    if (!destination.exists() && backup.exists()) backup.renameTo(destination)
                    throw error
                }
                imported.add(name)
            } finally {
                if (incoming.exists()) incoming.delete()
            }
        }
        return imported
    }

    private fun confirmReplacement(name: String): Boolean {
        val latch = CountDownLatch(1)
        var confirmed = false
        runOnUiThread {
            AlertDialog.Builder(this)
                .setTitle("替换 GP-Next 文件")
                .setMessage("$name 已存在，是否使用新文件替换？")
                .setPositiveButton("替换") { _, _ -> confirmed = true; latch.countDown() }
                .setNegativeButton("取消") { _, _ -> latch.countDown() }
                .setOnCancelListener { latch.countDown() }
                .show()
        }
        return latch.await(USER_INTERACTION_TIMEOUT_MINUTES, TimeUnit.MINUTES) && confirmed
    }

    private fun writeExitResult(
        sessionId: String,
        reason: GameExitReason,
        message: String?,
        resourceRoot: String?,
    ) {
        val root = resourceRoot?.let { File(it).parentFile } ?: return
        val output = File(root, "game_exit_result.json")
        val temporary = File(output.path + ".tmp")
        val json = JSONObject()
            .put("schemaVersion", 1)
            .put("sessionId", sessionId)
            .put("reason", reason.wireName)
            .put("finishedAt", Instant.now().toString())
            .put("message", message ?: JSONObject.NULL)
        runCatching {
            temporary.writeText(json.toString(2) + "\n")
            check(temporary.renameTo(output)) { "Cannot commit exit result" }
        }
    }

    private data class PendingExport(val requestId: String, val file: File)

    private data class ChunkedExport(
        val token: String,
        val file: File,
        val output: BufferedOutputStream,
        val expectedBytes: Long,
        val mimeType: String,
        val fileName: String,
        var written: Long = 0,
        var nextIndex: Int = 0,
    )

    companion object {
        const val EXTRA_SESSION = "gameSession"
        private const val REQUEST_FILE_CHOOSER = 4101
        private const val REQUEST_EXPORT = 4102
        private const val REQUEST_GP_NEXT_IMPORT = 4103
        private const val MAX_EXPORT_BYTES = 512L * 1024 * 1024
        private const val MAX_EXPORT_CHUNK_BYTES = 256 * 1024
        private const val USER_INTERACTION_TIMEOUT_MINUTES = 5L
    }
}
