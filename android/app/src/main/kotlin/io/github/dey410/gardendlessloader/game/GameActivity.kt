package io.github.dey410.gardendlessloader.game

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class GameActivity : Activity() {
    private lateinit var session: NativeGameSession
    private lateinit var webView: WebView
    private lateinit var bridge: GameBridge
    private lateinit var gpNextCore: GpNextNativeCore
    private var fileChooserCallback: ValueCallback<Array<Uri>>? = null
    private var pendingExport: PendingExport? = null
    private var pendingGpImportRequestId: String? = null
    private var pendingGpSelection: PendingGpSelection? = null
    private var returning = false
    @Volatile private var destroyed = false

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
            val webViewPackage = WebViewCompat.getCurrentWebViewPackage(this)
            val code = if (error is WebViewUnsupportedException) "webview_unsupported" else "game_host_launch_failed"
            AppLogStore.emit(
                source = "android", level = "ERROR", category = "game.host",
                event = "game_host_launch_finished", outcome = "failed",
                code = code, error = error,
                context = mapOf(
                    "webViewPackage" to webViewPackage?.packageName,
                    "webViewVersion" to webViewPackage?.versionName,
                ),
            )
            writeExitResult(
                rawSession?.let { runCatching { JSONObject(it).optString("sessionId") }.getOrNull() }
                    ?: "unknown",
                GameExitReason.LAUNCH_FAILED,
                error.message ?: error.toString(),
                rawSession?.let { runCatching { JSONObject(it).optString("resourceRoot") }.getOrNull() },
                code = code,
            )
            startActivity(Intent(this, MainActivity::class.java))
            finish()
        }
    }

    private fun configureWebView() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            throw WebViewUnsupportedException("Installed Android System WebView lacks origin-scoped messaging")
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                settings.safeBrowsingEnabled = true
                setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, false)
            }
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        bridge = GameBridge(this, webView, session)
        gpNextCore = GpNextNativeCore(this, session, bridge)
        WebViewCompat.addWebMessageListener(
            webView,
            GameBridge.BRIDGE_NAME,
            setOf(session.origin),
            bridge,
        )
        // The resource handler inlines this into every served HTML document; the
        // WebView API for document-start scripts is missing on older WebViews.
        webView.webViewClient = GameWebViewClient(session, buildDocumentStartScript()) { crashed ->
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
            .put("hostAbi", 1)
            .put("platform", "android")
            .put("touchWheelCssMultiplier", -4.5)
            .put("touchDiagnosticsEnabled", false)
            .put("origin", session.origin)
            .put("activationGeneration", session.activationGeneration)
            .put("hasGpNext", session.hasGpNext)
            .put("gpNextCompatible", session.gpNextCompatible)
            .put("gpNextVersion", session.gpNextVersion ?: JSONObject.NULL)
            .put("watermarkEnabled", session.watermarkEnabled)
            .put("autoCollectSunEnabled", session.autoCollectSunEnabled)
            .put("detailedAudioDiagnosticsEnabled", session.detailedAudioDiagnosticsEnabled)
            .put(
                "gpNextBaseDirectory",
                File(session.gpNextRoot).parentFile?.absolutePath ?: session.appRoot,
            )
        val names = buildList {
            add("transport.js")
            add("logging.js")
            add("audio_diagnostic.js")
            add("auto_sun.js")
            add("touch_state_machine.js")
            add("touch_input_adapter.js")
            add("export_download_patch.js")
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

    fun dispatchFileOrGpNext(requestId: String, request: JSONObject) {
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
        if (pendingGpImportRequestId != null || pendingGpSelection != null || pendingExport != null) {
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

    fun beginGpNextSelection(requestId: String, directory: Boolean) {
        if (pendingGpSelection != null || pendingGpImportRequestId != null || pendingExport != null) {
            bridge.fail(requestId, "gp_next_selection_busy", "已有文件选择正在进行")
            return
        }
        pendingGpSelection = PendingGpSelection(requestId, directory)
        val intent = if (directory) {
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("application/zip", "application/x-zip-compressed"),
                )
            }
        }
        launchDocumentPicker(intent, REQUEST_GP_NEXT_SELECTION) {
            pendingGpSelection = null
            bridge.fail(requestId, "gp_next_picker_failed", it.message ?: it.toString())
        }
    }

    fun beginExistingFileExport(
        requestId: String,
        handle: String,
        file: File,
        fileName: String,
        mimeType: String,
    ) {
        if (destroyed || !gpNextCore.isFileActive(handle)) return
        if (pendingExport != null || pendingGpSelection != null || pendingGpImportRequestId != null) {
            gpNextCore.execute(requestId, control = true) {
                gpNextCore.exportFinished(handle, "export_in_progress", "Another document picker is active")
            }
            return
        }
        pendingExport = PendingExport(requestId, handle, file)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = exportMimeType(fileName, mimeType)
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        launchDocumentPicker(intent, REQUEST_EXPORT) {
            pendingExport = null
            gpNextCore.execute(requestId, control = true) {
                gpNextCore.exportFinished(handle, "export_picker_failed", it.message ?: "Cannot open export picker")
            }
        }
    }

    fun cancelFileExport(handle: String) {
        if (pendingExport?.handle == handle) {
            // Keep the slot until its result returns; a late result must never select a newer export.
            finishActivity(REQUEST_EXPORT)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_FILE_CHOOSER ||
            requestCode == REQUEST_EXPORT ||
            requestCode == REQUEST_GP_NEXT_IMPORT ||
            requestCode == REQUEST_GP_NEXT_SELECTION
        ) {
            restoreGameOrientation()
        }
        if (destroyed) return
        when (requestCode) {
            REQUEST_GP_NEXT_SELECTION -> {
                val selection = pendingGpSelection
                if (selection == null) return
                if (resultCode != RESULT_OK || data?.data == null) {
                    pendingGpSelection = null
                    bridge.complete(selection.requestId, null)
                    return
                }
                gpNextCore.execute(selection.requestId, onRejected = {
                    gpNextCore.postIfActive { if (pendingGpSelection === selection) pendingGpSelection = null }
                }) {
                    runCatching { stageGpNextSelection(data.data!!, selection.directory) }
                        .onSuccess { path -> gpNextCore.postIfActive {
                            pendingGpSelection = null
                            bridge.complete(selection.requestId, path.path)
                        } }
                        .onFailure { error ->
                            runCatching { clearGpNextSelection() }
                            gpNextCore.postIfActive {
                                pendingGpSelection = null
                                bridge.fail(
                                    selection.requestId,
                                    "gp_next_selection_failed",
                                    error.message ?: error.toString(),
                                )
                            }
                        }
                }
            }
            REQUEST_GP_NEXT_IMPORT -> {
                val requestId = pendingGpImportRequestId
                if (requestId == null) return
                if (resultCode != RESULT_OK || data == null) {
                    pendingGpImportRequestId = null
                    bridge.fail(requestId, "import_cancelled", "Import was cancelled")
                    return
                }
                val uris = buildList {
                    data.data?.let(::add)
                    val clip = data.clipData
                    if (clip != null) for (index in 0 until clip.itemCount) add(clip.getItemAt(index).uri)
                }.distinct()
                gpNextCore.execute(requestId, onRejected = {
                    gpNextCore.postIfActive { if (pendingGpImportRequestId == requestId) pendingGpImportRequestId = null }
                }) {
                    runCatching { importGpNextPackages(uris) }
                        .onSuccess { gpNextCore.postIfActive {
                            pendingGpImportRequestId = null
                            bridge.complete(requestId, null)
                        } }
                        .onFailure { error -> gpNextCore.postIfActive {
                            pendingGpImportRequestId = null
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
                if (export == null) return
                if (resultCode != RESULT_OK || data?.data == null) {
                    pendingExport = null
                    gpNextCore.execute(export.requestId, control = true) {
                        gpNextCore.exportFinished(export.handle, "export_cancelled", "Export was cancelled")
                    }
                    return
                }
                gpNextCore.execute(export.requestId, onRejected = {
                    gpNextCore.postIfActive { if (pendingExport === export) pendingExport = null }
                    gpNextCore.execute(null, control = true) {
                        gpNextCore.exportFinished(export.handle, "resource_limit_exceeded", "Export copy was rejected")
                    }
                }) {
                    if (!gpNextCore.isFileActive(export.handle)) {
                        gpNextCore.postIfActive { if (pendingExport === export) pendingExport = null }
                        return@execute
                    }
                    runCatching {
                        val output = requireNotNull(contentResolver.openOutputStream(data.data!!, "w")) {
                            "Cannot open export destination"
                        }
                        gpNextCore.useResource(output, export.handle) { destination ->
                            gpNextCore.useResource(export.file.inputStream(), export.handle) { input ->
                                val buffer = ByteArray(GpNextNativeCore.MAX_CHUNK_BYTES)
                                while (true) {
                                    check(gpNextCore.isFileActive(export.handle)) { "Export was cancelled" }
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    destination.write(buffer, 0, count)
                                }
                                destination.flush()
                            }
                        }
                    }.onSuccess { gpNextCore.exportFinished(export.handle) }
                        .onFailure { gpNextCore.exportFinished(export.handle, "export_failed", it.message) }
                    gpNextCore.postIfActive { if (pendingExport === export) pendingExport = null }
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
            context = mapOf("reason" to reason.wireName, "packageId" to session.packageId),
        )
        AppLogStore.flush(500)
        writeExitResult(session.sessionId, reason, message, session.resourceRoot, session.packageId)
        startActivity(Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        })
        finish()
    }

    override fun onDestroy() {
        destroyed = true
        pendingExport = null
        pendingGpSelection = null
        pendingGpImportRequestId = null
        fileChooserCallback?.onReceiveValue(null)
        fileChooserCallback = null
        if (::gpNextCore.isInitialized) gpNextCore.destroy()
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

    private fun importGpNextPackages(uris: List<Uri>): List<String> {
        val imported = mutableListOf<String>()
        for (uri in uris) {
            check(!destroyed && !Thread.currentThread().isInterrupted) { "Game host was destroyed" }
            val displayName = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
                ?: uri.lastPathSegment ?: "gp-next-file"
            val name = ExportDocumentSpec.safeFileName(displayName)
            val extension = name.substringAfterLast('.', "").lowercase()
            // Only GP-Next's legacy runtime reads packs/; its mod platform installs
            // ZIP mods from its own picker once configuration-state.json exists.
            require(extension != "zip" || !File(session.gpNextRoot, "configuration-state.json").exists()) {
                "GP-Next 已启用新版模组管理，请在 GP-Next 模组页安装 ZIP 模组"
            }
            val destinationDirectory = when (extension) {
                "zip" -> File(session.gpNextRoot, "packs")
                "json", "json5" -> File(session.gpNextRoot, "patches")
                else -> throw IllegalArgumentException("不支持的 GP-Next 文件：$name")
            }.apply { mkdirs() }
            val incoming = File(destinationDirectory, ".$name.incoming-${System.nanoTime()}")
            gpNextCore.useResource(requireNotNull(contentResolver.openInputStream(uri)) { "无法读取 $name" }) { input ->
                gpNextCore.useResource(incoming.outputStream()) { output -> input.copyTo(output, 64 * 1024) }
            }
            var prepared = incoming
            try {
                if (extension == "zip") {
                    prepared = GpNextPackArchiveNormalizer.prepare(
                        incoming,
                        destinationDirectory,
                        name,
                    )
                } else if (extension == "json") {
                    val text = incoming.readText()
                    runCatching { JSONObject(text) }.recoverCatching { org.json.JSONArray(text) }.getOrThrow()
                } else {
                    require(incoming.length() > 0) { "$name 是空文件" }
                }
                val destination = File(destinationDirectory, name)
                if (destination.exists() && !confirmReplacement(name)) continue
                check(!destroyed && !Thread.currentThread().isInterrupted) { "Game host was destroyed" }
                val backup = File(destinationDirectory, ".$name.backup-${System.nanoTime()}")
                if (destination.exists() && !destination.renameTo(backup)) error("无法暂存旧文件")
                try {
                    if (!prepared.renameTo(destination)) error("无法激活新文件")
                    if (backup.exists()) backup.delete()
                } catch (error: Exception) {
                    if (!destination.exists() && backup.exists()) backup.renameTo(destination)
                    throw error
                }
                imported.add(name)
            } finally {
                if (incoming.exists()) incoming.delete()
                if (prepared != incoming && prepared.exists()) prepared.delete()
            }
        }
        return imported
    }

    private fun stageGpNextSelection(uri: Uri, directory: Boolean): File {
        clearGpNextSelection()
        val stagingRoot = gpNextSelectionRoot()
        require(stagingRoot.mkdirs()) { "无法创建 GP-Next 选择暂存目录" }
        val budget = SelectionCopyBudget()
        return if (directory) {
            val destination = File(stagingRoot, "selection")
            require(destination.mkdir()) { "无法创建 GP-Next 目录暂存区" }
            copyDocumentTree(uri, destination, budget)
            destination
        } else {
            val displayName = documentDisplayName(uri)
            require(displayName.lowercase().endsWith(".zip")) { "请选择 ZIP 格式的 Mod 包" }
            val destination = File(stagingRoot, "selection.zip")
            copyDocumentFile(uri, destination, budget)
            destination
        }
    }

    private fun copyDocumentTree(treeUri: Uri, destination: File, budget: SelectionCopyBudget) {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
        copyDocumentChildren(treeUri, rootUri, destination, budget, mutableSetOf())
    }

    private fun copyDocumentChildren(
        treeUri: Uri,
        parentUri: Uri,
        destination: File,
        budget: SelectionCopyBudget,
        visited: MutableSet<String>,
    ) {
        val parentId = DocumentsContract.getDocumentId(parentUri)
        require(visited.add(parentId)) { "选择的目录包含循环引用" }
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        val cursor = requireNotNull(contentResolver.query(childrenUri, columns, null, null, null)) {
            "无法读取选择的目录"
        }
        gpNextCore.useResource(cursor) {
            val idColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeColumn = it.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (it.moveToNext()) {
                check(!destroyed && !Thread.currentThread().isInterrupted) { "Game host was destroyed" }
                budget.addEntry()
                val documentId = it.getString(idColumn)
                val name = requireSafeSelectionName(it.getString(nameColumn))
                val mime = it.getString(mimeColumn)
                val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
                val target = File(destination, name)
                require(target.parentFile == destination && !target.exists()) { "选择的目录包含重复路径" }
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    require(target.mkdir()) { "无法创建目录：$name" }
                    copyDocumentChildren(treeUri, childUri, target, budget, visited)
                } else {
                    copyDocumentFile(childUri, target, budget)
                }
            }
        }
    }

    private fun copyDocumentFile(uri: Uri, destination: File, budget: SelectionCopyBudget) {
        gpNextCore.useResource(requireNotNull(contentResolver.openInputStream(uri)) { "无法读取选择的文件" }) { input ->
            gpNextCore.useResource(destination.outputStream().buffered()) { output ->
                val buffer = ByteArray(128 * 1024)
                while (true) {
                    check(!destroyed && !Thread.currentThread().isInterrupted) { "Game host was destroyed" }
                    val count = input.read(buffer)
                    if (count < 0) break
                    budget.addBytes(count)
                    output.write(buffer, 0, count)
                }
            }
        }
    }

    private fun documentDisplayName(uri: Uri): String =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
            ?: uri.lastPathSegment
            ?: "selection.zip"

    private fun requireSafeSelectionName(value: String?): String {
        val name = value?.trim().orEmpty()
        require(name.isNotEmpty() && name != "." && name != "..") { "选择内容包含无效名称" }
        require(!name.contains('/') && !name.contains('\\') && !name.contains('\u0000')) {
            "选择内容包含无效名称"
        }
        return name
    }

    private fun clearGpNextSelection() {
        val root = gpNextSelectionRoot()
        if (!root.exists()) return
        require(!root.isSelectionSymbolicLink()) { "选择暂存目录不能是符号链接" }
        deleteSelectionTree(root)
    }

    private fun deleteSelectionTree(directory: File) {
        require(!directory.isSelectionSymbolicLink()) { "选择暂存区包含符号链接" }
        directory.listFiles().orEmpty().forEach { child ->
            require(!child.isSelectionSymbolicLink()) { "选择暂存区包含符号链接" }
            if (child.isDirectory) deleteSelectionTree(child)
            else require(child.delete()) { "无法清理选择暂存文件" }
        }
        require(directory.delete()) { "无法清理选择暂存目录" }
    }

    private fun gpNextSelectionRoot(): File = File(session.gpNextRoot, ".gardendless-selection")

    private fun confirmReplacement(name: String): Boolean {
        val latch = CountDownLatch(1)
        var confirmed = false
        gpNextCore.postIfActive {
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
        packageId: String = "unknown",
        code: String? = null,
    ) {
        val root = resourceRoot?.let { File(it).parentFile } ?: return
        val output = File(root, "game_exit_result.json")
        val temporary = File(output.path + ".tmp")
        val json = JSONObject()
            .put("schemaVersion", 1)
            .put("packageId", packageId)
            .put("sessionId", sessionId)
            .put("reason", reason.wireName)
            .put("finishedAt", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date()))
            .put("message", message ?: JSONObject.NULL)
            .put("code", code)
        runCatching {
            temporary.writeText(json.toString(2) + "\n")
            check(temporary.renameTo(output)) { "Cannot commit exit result" }
        }
    }

    private data class PendingExport(val requestId: String, val handle: String, val file: File)

    private data class PendingGpSelection(val requestId: String, val directory: Boolean)

    private class SelectionCopyBudget {
        private var entries = 0
        private var bytes = 0L

        fun addEntry() {
            entries += 1
            require(entries <= MAX_SELECTION_ENTRIES) { "选择的 Mod 包文件数量过多" }
        }

        fun addBytes(count: Int) {
            bytes += count
            require(bytes <= MAX_SELECTION_BYTES) { "选择的 Mod 包超过 512 MiB" }
        }
    }

    companion object {
        const val EXTRA_SESSION = "gameSession"
        private const val REQUEST_FILE_CHOOSER = 4101
        private const val REQUEST_EXPORT = 4102
        private const val REQUEST_GP_NEXT_IMPORT = 4103
        private const val REQUEST_GP_NEXT_SELECTION = 4104
        private const val USER_INTERACTION_TIMEOUT_MINUTES = 5L
        private const val MAX_SELECTION_ENTRIES = 10_000
        private const val MAX_SELECTION_BYTES = 512L * 1024 * 1024
    }
}

private fun File.isSelectionSymbolicLink(): Boolean = runCatching {
    OsConstants.S_ISLNK(Os.lstat(path).st_mode)
}.getOrDefault(false)

/** The System WebView lacks a feature the GameHost needs; updating it fixes the launch. */
private class WebViewUnsupportedException(message: String) : IllegalStateException(message)
