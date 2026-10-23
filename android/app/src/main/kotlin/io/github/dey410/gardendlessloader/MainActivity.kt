package io.github.dey410.gardendlessloader

import android.app.Activity
import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.text.format.Formatter
import androidx.webkit.WebViewCompat
import io.github.dey410.gardendlessloader.game.GameActivity
import io.github.dey410.gardendlessloader.logging.AppLogStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.Locale
import java.util.zip.ZipException
import java.util.zip.ZipInputStream
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var resourceZipImporterChannel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingTargetDirectory: String? = null
    private var lastImportProgressReportAt = 0L
    private var transferringToGameHost = false
    /** A ZIP another app opened or shared, waiting for the launcher's decision. */
    private var incomingZip: Uri? = null
    private var shortcutChannel: MethodChannel? = null
    /** The home-screen shortcut that opened the launcher, until Flutter takes it. */
    private var pendingShortcut: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppLogStore.install(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.dey410.gardendlessloader/game_host",
        ).setMethodCallHandler { call, result ->
            if (call.method == "device") {
                result.success(hostDevice())
                return@setMethodCallHandler
            }
            if (call.method != "launch") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val arguments = call.arguments as? Map<*, *>
            if (arguments == null) {
                result.error("invalid_game_session", "缺少原生游戏会话", null)
                return@setMethodCallHandler
            }
            try {
                transferringToGameHost = true
                startActivity(
                    Intent(this, GameActivity::class.java).putExtra(
                        GameActivity.EXTRA_SESSION,
                        JSONObject(arguments).toString(),
                    ),
                )
                result.success(null)
                window.decorView.post { finish() }
            } catch (error: Exception) {
                transferringToGameHost = false
                result.error("game_host_launch_failed", error.message, null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.dey410.gardendlessloader/external_browser",
        ).setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val value = call.argument<String>("url")
            val uri = value?.let { runCatching { Uri.parse(it) }.getOrNull() }
            if (uri == null || (uri.scheme != "https" && uri.scheme != "http")) {
                result.error("invalid_external_url", "只允许打开 HTTP(S) 链接", null)
                return@setMethodCallHandler
            }
            runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                .onSuccess { result.success(null) }
                .onFailure { result.error("external_open_failed", it.message, null) }
        }
        val importChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.dey410.gardendlessloader/resource_zip_importer",
        )
        resourceZipImporterChannel = importChannel
        incomingZip = incomingZipOf(intent)
        pendingShortcut = shortcutOf(intent)
        val shortcuts = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.dey410.gardendlessloader/shortcuts",
        )
        shortcutChannel = shortcuts
        shortcuts.setMethodCallHandler { call, result ->
            when (call.method) {
                "take" -> {
                    result.success(pendingShortcut)
                    pendingShortcut = null
                }
                "setItems" -> {
                    val titles = call.arguments as? Map<*, *>
                    if (titles == null) {
                        result.error("invalid_shortcuts", "Shortcut titles must be a map", null)
                    } else {
                        publishShortcuts(titles)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        importChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "incomingZip" -> {
                    result.success(incomingZip?.let(::displayName))
                    return@setMethodCallHandler
                }
                "discardIncomingZip" -> {
                    incomingZip = null
                    result.success(null)
                    return@setMethodCallHandler
                }
                "pickAndExtractDocsZip", "extractIncomingDocsZip" -> Unit
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }

            if (pendingResult != null) {
                result.error("zip_import_busy", "已有 ZIP 导入选择正在进行", null)
                return@setMethodCallHandler
            }

            val targetDirectory = call.argument<String>("targetDirectory")
            if (targetDirectory.isNullOrBlank()) {
                result.error("invalid_target_directory", "缺少导入目标目录", null)
                return@setMethodCallHandler
            }

            if (call.method == "extractIncomingDocsZip") {
                val uri = incomingZip
                incomingZip = null
                if (uri == null) result.success(null) else extractInBackground(uri, targetDirectory, result)
                return@setMethodCallHandler
            }

            pendingResult = result
            pendingTargetDirectory = targetDirectory
            launchZipPicker(result)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        incomingZipOf(intent)?.let { uri ->
            incomingZip = uri
            resourceZipImporterChannel?.invokeMethod("incomingZipReceived", displayName(uri))
        }
        shortcutOf(intent)?.let { shortcutChannel?.invokeMethod("perform", it) }
    }

    // Every route to an import ends here, and MainActivity is exported: other apps
    // share documents as content URIs, never as paths this app could read for them.
    private fun incomingZipOf(intent: Intent?): Uri? =
        intent?.data?.takeIf {
            intent.action == ACTION_IMPORT_ZIP && it.scheme == ContentResolver.SCHEME_CONTENT
        }

    private fun shortcutOf(intent: Intent?): String? =
        intent?.getStringExtra(EXTRA_SHORTCUT)?.takeIf { intent.action == ACTION_SHORTCUT }

    /** Titles come from the launcher so they follow its language setting. */
    private fun publishShortcuts(titles: Map<*, *>) {
        if (Build.VERSION.SDK_INT < 25) return
        val icons = mapOf(
            "startGame" to R.drawable.ic_shortcut_start_game,
            "importResources" to R.drawable.ic_shortcut_import_resources,
        )
        val shortcuts = icons.mapNotNull { (id, icon) ->
            val title = titles[id] as? String ?: return@mapNotNull null
            ShortcutInfo.Builder(this, id)
                .setShortLabel(title)
                .setIcon(Icon.createWithResource(this, icon))
                .setIntent(
                    Intent(this, LaunchRouterActivity::class.java)
                        .setAction(ACTION_SHORTCUT)
                        .putExtra(EXTRA_SHORTCUT, id),
                )
                .build()
        }
        getSystemService(ShortcutManager::class.java).setDynamicShortcuts(shortcuts)
    }

    private fun displayName(uri: Uri): String {
        val queried = runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        }.getOrNull()
        return queried ?: uri.lastPathSegment ?: "ZIP"
    }

    override fun onDestroy() {
        if (isFinishing && !transferringToGameHost) {
            AppLogStore.endSession()
        }
        super.onDestroy()
    }

    private fun createZipPickerIntent(action: String): Intent {
        return Intent(action).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "application/zip",
                    "application/x-zip-compressed",
                    "application/octet-stream",
                ),
            )
        }
    }

    private fun hostDevice(): Map<String, Any?> {
        val memory = ActivityManager.MemoryInfo()
        (getSystemService(ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        val webView = WebViewCompat.getCurrentWebViewPackage(this)
        return mapOf(
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "webViewVersion" to webView?.let { "${it.packageName} ${it.versionName}" },
            "memoryBytes" to memory.totalMem,
        )
    }

    private fun launchZipPicker(result: MethodChannel.Result) {
        prepareForDocumentPicker()
        try {
            startActivityForResult(
                createZipPickerIntent(Intent.ACTION_OPEN_DOCUMENT),
                pickZipRequestCode,
            )
        } catch (error: ActivityNotFoundException) {
            try {
                startActivityForResult(
                    createZipPickerIntent(Intent.ACTION_GET_CONTENT),
                    pickZipRequestCode,
                )
            } catch (fallbackError: Exception) {
                restoreLandscapeOrientation()
                failZipPicker(result, fallbackError)
            }
        } catch (error: Exception) {
            restoreLandscapeOrientation()
            failZipPicker(result, error)
        }
    }

    private fun failZipPicker(result: MethodChannel.Result, error: Exception) {
        pendingResult = null
        pendingTargetDirectory = null
        result.error("zip_picker_failed", error.message ?: error.toString(), null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickZipRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        restoreLandscapeOrientation()
        val result = pendingResult
        val targetDirectory = pendingTargetDirectory
        pendingResult = null
        pendingTargetDirectory = null

        if (result == null || targetDirectory == null) {
            return
        }

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }
        extractInBackground(uri, targetDirectory, result)
    }

    private fun extractInBackground(uri: Uri, targetDirectory: String, result: MethodChannel.Result) {
        Thread {
            try {
                lastImportProgressReportAt = 0L
                extractDocsZip(uri, File(targetDirectory))
                runOnUiThread { result.success(targetDirectory) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        when (error) {
                            is ZipImportException -> error.code
                            is ZipException -> "zip_invalid"
                            else -> "zip_import_failed"
                        },
                        "无法导入选择的 ZIP：${error.message ?: error.toString()}",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun extractDocsZip(uri: Uri, targetDirectory: File) {
        val sourceBytes = contentResolver.openAssetFileDescriptor(uri, "r")?.use { descriptor ->
            descriptor.length.coerceAtLeast(0L)
        } ?: 0L
        reportImportProgress(
            phase = "receiving",
            processedBytes = 0,
            totalBytes = sourceBytes,
            message = "正在读取 ZIP",
            force = true,
        )
        val scan = findDocsPrefix(uri, sourceBytes)
            ?: throw ZipImportException("zip_docs_missing", "选择的 ZIP 中没有找到有效的 docs 资源目录")
        resetDirectory(targetDirectory)
        // ZipInputStream holds each entry to its recorded size and CRC-32, so the
        // scanned total bounds what extraction writes.
        if (scan.totalBytes > targetDirectory.usableSpace) {
            throw ZipImportException(
                "zip_write_failed",
                "设备剩余空间不足：解压需要 ${Formatter.formatFileSize(this, scan.totalBytes)}，" +
                    "剩余 ${Formatter.formatFileSize(this, targetDirectory.usableSpace)}",
            )
        }
        var processedBytes = 0L
        var processedFiles = 0
        reportImportProgress(
            phase = "extracting",
            processedFiles = 0,
            totalFiles = scan.totalFiles,
            message = "正在解压资源",
            force = true,
        )

        contentResolver.openInputStream(uri)?.use { input ->
            ZipInputStream(BufferedInputStream(input)).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val archivePath = safeArchivePath(entry.name)
                    if (!isWithinArchivePrefix(archivePath, scan.prefix)) {
                        zip.closeEntry()
                        continue
                    }

                    val relativePath = if (scan.prefix.isEmpty()) {
                        archivePath
                    } else {
                        archivePath.removePrefix("${scan.prefix}/")
                    }
                    if (relativePath.isEmpty()) {
                        zip.closeEntry()
                        continue
                    }

                    val targetFile = resolveTargetFile(targetDirectory, relativePath)
                    if (entry.isDirectory) {
                        targetFile.mkdirs()
                    } else {
                        targetFile.parentFile?.mkdirs()
                        BufferedOutputStream(FileOutputStream(targetFile)).use { output ->
                            val buffer = ByteArray(zipCopyBufferSize)
                            while (true) {
                                val count = zip.read(buffer)
                                if (count < 0) {
                                    break
                                }
                                if (count > scan.totalBytes - processedBytes) {
                                    throw ZipImportException("zip_invalid", "选择的 ZIP 在导入期间发生了变化")
                                }
                                output.write(buffer, 0, count)
                                processedBytes += count
                                reportImportProgress(
                                    phase = "extracting",
                                    processedBytes = processedBytes,
                                    processedFiles = processedFiles,
                                    totalFiles = scan.totalFiles,
                                    message = "正在解压资源",
                                )
                            }
                        }
                        processedFiles++
                        reportImportProgress(
                            phase = "extracting",
                            processedBytes = processedBytes,
                            processedFiles = processedFiles,
                            totalFiles = scan.totalFiles,
                            message = "正在解压资源",
                            force = true,
                        )
                    }
                    zip.closeEntry()
                }
            }
        } ?: throw IllegalArgumentException("无法打开选择的 ZIP")
    }

    private fun findDocsPrefix(uri: Uri, sourceBytes: Long): DocsScan? {
        val fileSizes = linkedMapOf<String, Long>()
        val filePaths = fileSizes.keys
        val directoryPaths = linkedSetOf<String>()
        var bytesRead = 0L

        contentResolver.openInputStream(uri)?.use { input ->
            val progressInput = ProgressInputStream(BufferedInputStream(input)) { processed ->
                bytesRead = processed
                reportImportProgress(
                    phase = "receiving",
                    processedBytes = processed,
                    totalBytes = sourceBytes,
                    message = "正在读取 ZIP",
                )
            }
            ZipInputStream(progressInput).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    if (fileSizes.size + directoryPaths.size >= maxZipEntries) {
                        throw ZipImportException("zip_unsupported", "选择的 ZIP 超过 $maxZipEntries 个文件")
                    }
                    val archivePath = safeArchivePath(entry.name)
                    // Reading to the entry's end records its size, also behind a data descriptor.
                    zip.closeEntry()
                    if (entry.isDirectory) {
                        directoryPaths.add(archivePath)
                    } else {
                        // A repeated path is extracted again, so its bytes count twice.
                        fileSizes[archivePath] = (fileSizes[archivePath] ?: 0L) + entry.size
                    }
                }
            }
        } ?: throw IllegalArgumentException("无法打开选择的 ZIP")
        reportImportProgress(
            phase = "receiving",
            processedBytes = if (sourceBytes > 0) sourceBytes else bytesRead,
            totalBytes = sourceBytes,
            message = "已读取 ZIP",
            force = true,
        )

        val candidates = linkedSetOf<String>()
        for (path in filePaths) {
            if (basename(path).lowercase(Locale.ROOT) == "index.html") {
                candidates.add(dirname(path))
            }
            if (path.endsWith(packageManifestPath)) {
                candidates.add(dirname(dirname(dirname(path))))
            }
        }

        val prefix = candidates.filter { candidate ->
            fun candidatePath(relativePath: String): String {
                return if (candidate.isEmpty()) relativePath else "$candidate/$relativePath"
            }

            fun hasFile(relativePath: String): Boolean {
                return filePaths.contains(candidatePath(relativePath))
            }

            fun hasDirectory(relativePath: String): Boolean {
                val path = candidatePath(relativePath)
                return directoryPaths.contains(path) ||
                    filePaths.any { filePath -> filePath.startsWith("$path/") }
            }

            // A package manifest marks the root on its own: a delta package carries
            // only changed files, so it may lack the runtime layout below.
            hasFile(packageManifestPath) || (
                hasFile("index.html") &&
                    hasFile("src/settings.json") &&
                    hasFile("src/import-map.json") &&
                    hasDirectory("assets") &&
                    hasDirectory("cocos-js") &&
                    hasDirectory("src")
                )
        }.sortedWith { a, b ->
            val aIsDocs = basename(a) == "docs"
            val bIsDocs = basename(b) == "docs"
            when {
                aIsDocs != bIsDocs -> if (aIsDocs) -1 else 1
                else -> a.length.compareTo(b.length)
            }
        }.firstOrNull() ?: return null
        val files = fileSizes.filterKeys { path -> isWithinArchivePrefix(path, prefix) }
        return DocsScan(prefix, files.size, files.values.sum())
    }

    private fun reportImportProgress(
        phase: String,
        processedBytes: Long = 0,
        totalBytes: Long = 0,
        processedFiles: Int = 0,
        totalFiles: Int = 0,
        message: String,
        force: Boolean = false,
    ) {
        val now = android.os.SystemClock.elapsedRealtime()
        if (!force && now - lastImportProgressReportAt < progressReportIntervalMs) {
            return
        }
        lastImportProgressReportAt = now
        val arguments = mapOf(
            "phase" to phase,
            "processedBytes" to processedBytes,
            "totalBytes" to totalBytes,
            "processedFiles" to processedFiles,
            "totalFiles" to totalFiles,
            "message" to message,
        )
        runOnUiThread {
            resourceZipImporterChannel?.invokeMethod("progress", arguments)
        }
    }

    private fun safeArchivePath(path: String): String {
        val parts = path.replace('\\', '/')
            .split('/')
            .filter { it.isNotEmpty() && it != "." }
        if (path.startsWith("/") || parts.isEmpty() || parts.any { it == ".." }) {
            throw ZipImportException("zip_path_unsafe", "选择的 ZIP 包含不安全路径")
        }
        return parts.joinToString("/")
    }

    private fun isWithinArchivePrefix(path: String, prefix: String): Boolean {
        return prefix.isEmpty() || path == prefix || path.startsWith("$prefix/")
    }

    private fun resolveTargetFile(root: File, relativePath: String): File {
        val rootFile = root.canonicalFile
        val targetFile = File(rootFile, relativePath.replace('/', File.separatorChar)).canonicalFile
        val rootPath = rootFile.path
        val targetPath = targetFile.path
        if (targetPath != rootPath && !targetPath.startsWith(rootPath + File.separator)) {
            throw ZipImportException("zip_path_unsafe", "选择的 ZIP 包含 docs 外部路径")
        }
        return targetFile
    }

    private fun resetDirectory(directory: File) {
        if (directory.exists()) {
            directory.listFiles()?.forEach { deleteRecursively(it) }
        } else {
            directory.mkdirs()
        }
        if (!directory.exists()) {
            directory.mkdirs()
        }
    }

    private fun deleteRecursively(file: File) {
        if (file.isDirectory) {
            file.listFiles()?.forEach { deleteRecursively(it) }
        }
        if (!file.delete() && file.exists()) {
            throw IllegalStateException("无法清理旧导入文件：${file.path}")
        }
    }

    private fun basename(path: String): String {
        return path.substringAfterLast('/')
    }

    private fun dirname(path: String): String {
        val index = path.lastIndexOf('/')
        return if (index == -1) "" else path.substring(0, index)
    }

    companion object {
        /** Intent action carrying a ZIP from [LaunchRouterActivity] or a game that held it. */
        const val ACTION_IMPORT_ZIP = "io.github.dey410.gardendlessloader.IMPORT_ZIP"
        const val ACTION_SHORTCUT = "io.github.dey410.gardendlessloader.SHORTCUT"
        const val EXTRA_SHORTCUT = "shortcut"
        private const val pickZipRequestCode = 26410
        private const val zipCopyBufferSize = 64 * 1024
        private const val progressReportIntervalMs = 100L

        /** The classic ZIP entry limit; iOS rejects the ZIP64 archives that exceed it. */
        private const val maxZipEntries = 65_535
        private const val packageManifestPath = "__gardendless/package/resource-manifest.json"
    }

    private data class DocsScan(val prefix: String, val totalFiles: Int, val totalBytes: Long)

    private class ProgressInputStream(
        private val source: InputStream,
        private val onProgress: (Long) -> Unit,
    ) : InputStream() {
        private var bytesRead = 0L

        override fun read(): Int {
            val value = source.read()
            if (value >= 0) {
                bytesRead++
                onProgress(bytesRead)
            }
            return value
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            val count = source.read(buffer, offset, length)
            if (count > 0) {
                bytesRead += count
                onProgress(bytesRead)
            }
            return count
        }

        override fun close() {
            source.close()
        }
    }
}

/** A ZIP import failure whose [code] names the cause, selecting the launcher's fix hint. */
private class ZipImportException(val code: String, message: String) : Exception(message)
