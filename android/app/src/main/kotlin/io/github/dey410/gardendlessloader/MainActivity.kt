package io.github.dey410.gardendlessloader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.Locale
import java.util.zip.ZipInputStream

class MainActivity : FlutterActivity() {
    private var resourceZipImporterChannel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingTargetDirectory: String? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportPath: String? = null
    private var pendingGpNextImportResult: MethodChannel.Result? = null
    private var pendingGpNextImportTarget: String? = null
    private var lastImportProgressReportAt = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val importChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.dey410.gardendlessloader/resource_zip_importer",
        )
        resourceZipImporterChannel = importChannel
        importChannel.setMethodCallHandler { call, result ->
            if (call.method != "pickAndExtractDocsZip") {
                result.notImplemented()
                return@setMethodCallHandler
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

            pendingResult = result
            pendingTargetDirectory = targetDirectory

            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/zip"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "application/zip",
                        "application/x-zip-compressed",
                        "application/octet-stream",
                    ),
                )
            }

            try {
                startActivityForResult(intent, pickZipRequestCode)
            } catch (error: Exception) {
                pendingResult = null
                pendingTargetDirectory = null
                result.error("zip_picker_failed", error.message, null)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.dey410.gardendlessloader/game_file_exporter",
        ).setMethodCallHandler { call, result ->
            if (call.method != "exportFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            if (pendingExportResult != null) {
                result.error("export_in_progress", "已有导出正在进行", null)
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("invalid_arguments", "缺少导出文件路径", null)
                return@setMethodCallHandler
            }

            val sourceFile = File(path)
            if (!sourceFile.exists() || !sourceFile.isFile) {
                result.error("file_not_found", "导出文件不存在", path)
                return@setMethodCallHandler
            }

            val fileName = call.argument<String>("name")
                ?.takeIf { it.isNotBlank() }
                ?: sourceFile.name
            val mimeType = call.argument<String>("mimeType")
                ?.takeIf { it.isNotBlank() }
                ?: "application/json"

            pendingExportResult = result
            pendingExportPath = sourceFile.path

            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, fileName)
            }

            try {
                startActivityForResult(intent, exportFileRequestCode)
            } catch (error: Exception) {
                pendingExportResult = null
                pendingExportPath = null
                result.error("export_picker_failed", error.message, null)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.dey410.gardendlessloader/gp_next_file_importer",
        ).setMethodCallHandler { call, result ->
            if (call.method != "pickAndCopyFiles") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingGpNextImportResult != null) {
                result.error("gp_next_import_busy", "已有 GP-Next 文件选择正在进行", null)
                return@setMethodCallHandler
            }
            val targetDirectory = call.argument<String>("targetDirectory")
            if (targetDirectory.isNullOrBlank()) {
                result.error("invalid_target_directory", "缺少 GP-Next 导入暂存目录", null)
                return@setMethodCallHandler
            }
            pendingGpNextImportResult = result
            pendingGpNextImportTarget = targetDirectory
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "application/zip",
                        "application/json",
                        "application/json5",
                        "text/plain",
                        "application/octet-stream",
                    ),
                )
            }
            try {
                startActivityForResult(intent, gpNextImportRequestCode)
            } catch (error: Exception) {
                pendingGpNextImportResult = null
                pendingGpNextImportTarget = null
                result.error("gp_next_picker_failed", error.message, null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == gpNextImportRequestCode) {
            handleGpNextImportResult(resultCode, data)
            return
        }
        if (requestCode == exportFileRequestCode) {
            handleExportFileResult(resultCode, data)
            return
        }

        if (requestCode != pickZipRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

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

        Thread {
            try {
                lastImportProgressReportAt = 0L
                extractDocsZip(uri, File(targetDirectory))
                runOnUiThread { result.success(targetDirectory) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "zip_import_failed",
                        "无法导入选择的 ZIP：${error.message ?: error.toString()}",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun handleGpNextImportResult(resultCode: Int, data: Intent?) {
        val result = pendingGpNextImportResult
        val targetPath = pendingGpNextImportTarget
        pendingGpNextImportResult = null
        pendingGpNextImportTarget = null
        if (result == null || targetPath == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                uris.add(clip.getItemAt(index).uri)
            }
        }
        data.data?.let { uri ->
            if (!uris.contains(uri)) {
                uris.add(uri)
            }
        }
        if (uris.isEmpty()) {
            result.success(null)
            return
        }
        Thread {
            try {
                val target = File(targetPath)
                target.mkdirs()
                val copied = uris.map { uri -> copyGpNextFile(uri, target).path }
                runOnUiThread { result.success(copied) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "gp_next_import_failed",
                        "无法导入选择的 GP-Next 文件：${error.message ?: error}",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun copyGpNextFile(uri: Uri, targetDirectory: File): File {
        val displayName = contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
        val fallbackName = uri.lastPathSegment?.substringAfterLast('/') ?: "gp-next-file"
        val safeName = File(displayName ?: fallbackName).name
            .replace(Regex("[\\u0000-\\u001f:*?\"<>|]"), "_")
            .ifBlank { "gp-next-file" }
        var destination = File(targetDirectory, safeName)
        var suffix = 1
        while (destination.exists()) {
            val stem = destination.nameWithoutExtension
            val extension = destination.extension.let { if (it.isEmpty()) "" else ".$it" }
            destination = File(targetDirectory, "$stem-$suffix$extension")
            suffix++
        }
        contentResolver.openInputStream(uri)?.use { input ->
            destination.outputStream().use { output ->
                input.copyTo(output, zipCopyBufferSize)
            }
        } ?: throw IllegalArgumentException("无法读取所选文件")
        return destination
    }

    private fun handleExportFileResult(resultCode: Int, data: Intent?) {
        val result = pendingExportResult
        val sourcePath = pendingExportPath
        pendingExportResult = null
        pendingExportPath = null

        if (result == null || sourcePath == null) {
            return
        }

        if (resultCode != Activity.RESULT_OK) {
            result.error("export_cancelled", "已取消导出", null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.error("export_cancelled", "已取消导出", null)
            return
        }

        Thread {
            try {
                copyFileToUri(File(sourcePath), uri)
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "export_failed",
                        "无法保存导出文件：${error.message ?: error.toString()}",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun copyFileToUri(sourceFile: File, uri: Uri) {
        sourceFile.inputStream().use { input ->
            contentResolver.openOutputStream(uri, "w")?.use { output ->
                input.copyTo(output, zipCopyBufferSize)
            } ?: throw IllegalArgumentException("无法打开保存位置")
        }
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
            ?: throw IllegalArgumentException("选择的 ZIP 中没有找到有效的 docs 资源目录")
        resetDirectory(targetDirectory)
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
        val filePaths = linkedSetOf<String>()
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
                    val archivePath = safeArchivePath(entry.name)
                    if (entry.isDirectory) {
                        directoryPaths.add(archivePath)
                    } else {
                        filePaths.add(archivePath)
                    }
                    zip.closeEntry()
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

            hasFile("index.html") &&
                hasFile("src/settings.json") &&
                hasFile("src/import-map.json") &&
                hasDirectory("assets") &&
                hasDirectory("cocos-js") &&
                hasDirectory("src")
        }.sortedWith { a, b ->
            val aIsDocs = basename(a) == "docs"
            val bIsDocs = basename(b) == "docs"
            when {
                aIsDocs != bIsDocs -> if (aIsDocs) -1 else 1
                else -> a.length.compareTo(b.length)
            }
        }.firstOrNull() ?: return null
        val totalFiles = filePaths.count { path ->
            isWithinArchivePrefix(path, prefix)
        }
        return DocsScan(prefix, totalFiles)
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
            throw IllegalArgumentException("选择的 ZIP 包含不安全路径")
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
            throw IllegalArgumentException("选择的 ZIP 包含 docs 外部路径")
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
        private const val pickZipRequestCode = 26410
        private const val exportFileRequestCode = 26411
        private const val gpNextImportRequestCode = 26412
        private const val zipCopyBufferSize = 64 * 1024
        private const val progressReportIntervalMs = 100L
    }

    private data class DocsScan(val prefix: String, val totalFiles: Int)

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
