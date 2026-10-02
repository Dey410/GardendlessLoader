package io.github.dey410.gardendlessloader.game

import android.net.Uri
import android.system.Os
import android.system.OsConstants
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.thread

class GpNextNativeCore(
    private val activity: GameActivity,
    private val session: NativeGameSession,
    private val bridge: GameBridge,
) {
    private val root = File(session.gpNextRoot).absoluteFile
    private val pendingExports = mutableSetOf<String>()
    private val pendingWrites = mutableMapOf<String, PendingWrite>()

    init {
        ensureSafeDirectory(root)
        ensureSafeDirectory(File(root, "packs"))
        ensureSafeDirectory(File(root, "patches"))
    }

    fun dispatch(requestId: String, request: JSONObject) {
        thread(name = "GardendlessGpNext") {
            try {
                val command = request.getString("command")
                val args = request.optJSONObject("args") ?: JSONObject()
                val options = request.optJSONObject("options") ?: JSONObject()
                val value: Any? = when (command) {
                    "plugin:fs|mkdir" -> {
                        val path = resolve(args.opt("path"), nestedOptions(args, options))
                        ensureSafeDirectory(path)
                        null
                    }
                    "plugin:fs|read_dir" -> readDirectory(resolve(args.opt("path"), nestedOptions(args, options)))
                    "plugin:fs|read_file", "plugin:fs|read_text_file" -> readFile(
                        resolve(args.opt("path"), nestedOptions(args, options)),
                    )
                    "plugin:fs|lstat" -> fileInfo(resolve(args.opt("path"), nestedOptions(args, options)))
                    "plugin:fs|exists" -> exists(resolve(args.opt("path"), nestedOptions(args, options)))
                    "plugin:fs|remove" -> {
                        remove(resolve(args.opt("path"), nestedOptions(args, options)), recursive(nestedOptions(args, options)))
                        null
                    }
                    "plugin:fs|write_file", "plugin:fs|write_text_file" -> {
                        if (writeFile(requestId, request, args, options)) {
                            return@thread
                        }
                        null
                    }
                    "plugin:fs|rename" -> {
                        rename(args, nestedOptions(args, options))
                        null
                    }
                    "plugin:dialog|open" -> {
                        val dialogOptions = args.optJSONObject("options") ?: JSONObject()
                        require(!dialogOptions.optBoolean("multiple", false)) {
                            "GP-Next 仅支持选择一个 Mod 包"
                        }
                        activity.runOnUiThread {
                            activity.beginGpNextSelection(
                                requestId,
                                dialogOptions.optBoolean("directory", false),
                            )
                        }
                        return@thread
                    }
                    "plugin:dialog|save" -> prepareExport(args)
                    "plugin:opener|open_url" -> {
                        activity.openGpNextUrl(args.optString("url"), requestId)
                        return@thread
                    }
                    "plugin:opener|open_path" -> {
                        activity.beginGpNextPackageImport(requestId)
                        return@thread
                    }
                    else -> throw GpNextFailure("未兼容的 GP-Next 命令：$command")
                }
                activity.runOnUiThread { bridge.complete(requestId, value) }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    bridge.fail(requestId, "gp_next_error", error.message ?: error.toString())
                }
            }
        }
    }

    private fun readDirectory(path: File): JSONArray {
        requireSafeExisting(path)
        require(path.isDirectory) { "目录不存在：${path.path}" }
        val result = JSONArray()
        path.listFiles().orEmpty().sortedBy { it.name }.forEach { child ->
            val isSymlink = child.isSymbolicLink()
            result.put(
                JSONObject()
                    .put("name", child.name)
                    .put("isFile", !isSymlink && child.isFile)
                    .put("isDirectory", !isSymlink && child.isDirectory)
                    .put("isSymlink", isSymlink),
            )
        }
        return result
    }

    private fun readFile(path: File): JSONArray {
        requireSafeExisting(path)
        require(path.isFile) { "文件不存在：${path.path}" }
        val result = JSONArray()
        path.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                for (index in 0 until count) result.put(buffer[index].toInt() and 0xff)
            }
        }
        return result
    }

    private fun fileInfo(path: File): JSONObject {
        requireSafeExisting(path)
        val isSymlink = path.isSymbolicLink()
        return JSONObject()
            .put("isFile", !isSymlink && path.isFile)
            .put("isDirectory", !isSymlink && path.isDirectory)
            .put("isSymlink", isSymlink)
            .put("size", if (path.isFile) path.length() else 0)
            .put("mtime", JSONObject.NULL)
            .put("atime", JSONObject.NULL)
            .put("birthtime", JSONObject.NULL)
            .put("readonly", !path.canWrite())
            .put("fileAttributes", JSONObject.NULL)
            .put("dev", 0)
            .put("ino", 0)
            .put("mode", 0)
            .put("nlink", 0)
            .put("uid", 0)
            .put("gid", 0)
            .put("rdev", 0)
            .put("blksize", 0)
            .put("blocks", 0)
    }

    private fun exists(path: File): Boolean {
        ensureNoSymlink(path)
        return path.exists()
    }

    private fun writeFile(
        requestId: String,
        request: JSONObject,
        args: JSONObject,
        options: JSONObject,
    ): Boolean {
        val transfer = args.optJSONObject("__gardendlessTransfer")
        if (transfer != null) {
            return writeFileChunk(requestId, args, options, transfer)
        }
        val headers = options.optJSONObject("headers") ?: JSONObject()
        val encodedPath = headers.optString("path").takeIf { it.isNotBlank() }
        val headerOptions = headers.optString("options").takeIf { it.isNotBlank() && it != "undefined" }
            ?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
        val path = resolve(encodedPath?.let(Uri::decode) ?: args.opt("path"), headerOptions)
        val values = args.optJSONArray("__gardendlessBytes")
            ?: request.optJSONArray("args")
            ?: throw GpNextFailure("GP-Next 写入内容不是字节数组")
        ensureSafeDirectory(requireNotNull(path.parentFile) { "GP-Next 文件没有父目录" })
        ensureNoSymlink(path)
        path.outputStream().buffered().use { output ->
            val buffer = ByteArray(64 * 1024)
            var position = 0
            while (position < values.length()) {
                val count = minOf(buffer.size, values.length() - position)
                for (index in 0 until count) buffer[index] = values.getInt(position + index).toByte()
                output.write(buffer, 0, count)
                position += count
            }
        }
        if (pendingExports.remove(path.path)) {
            activity.runOnUiThread { activity.beginExistingFileExport(requestId, path) }
            return true
        }
        return false
    }

    @Synchronized
    private fun writeFileChunk(
        requestId: String,
        args: JSONObject,
        options: JSONObject,
        transfer: JSONObject,
    ): Boolean {
        val token = transfer.optString("token")
        require(token.matches(Regex("[A-Za-z0-9-]{1,96}"))) { "GP-Next 分块写入 token 无效" }
        if (transfer.optBoolean("abort", false)) {
            pendingWrites.remove(token)?.temporary?.delete()
            return false
        }
        val headers = options.optJSONObject("headers") ?: JSONObject()
        val encodedPath = headers.optString("path").takeIf { it.isNotBlank() }
        val headerOptions = headers.optString("options").takeIf { it.isNotBlank() && it != "undefined" }
            ?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
        val path = resolve(encodedPath?.let(Uri::decode) ?: args.opt("path"), headerOptions)
        val values = args.optJSONArray("__gardendlessBytes")
            ?: throw GpNextFailure("GP-Next 分块写入内容不是字节数组")
        require(values.length() <= MAX_WRITE_CHUNK_BYTES) { "GP-Next 写入分块过大" }
        val index = transfer.optInt("index", -1)
        val total = transfer.optLong("totalBytes", -1)
        require(total in 0..MAX_WRITE_BYTES) { "GP-Next 写入大小无效" }
        val state = if (index == 0) {
            require(!pendingWrites.containsKey(token)) { "GP-Next 分块写入已存在" }
            ensureSafeDirectory(requireNotNull(path.parentFile) { "GP-Next 文件没有父目录" })
            ensureNoSymlink(path)
            val temporary = File(path.parentFile, ".gardendless-write-$token")
            require(!temporary.exists()) { "GP-Next 分块临时文件已存在" }
            PendingWrite(path, temporary, total).also { pendingWrites[token] = it }
        } else {
            pendingWrites[token] ?: throw GpNextFailure("GP-Next 分块写入不存在")
        }
        require(state.path == path && state.nextIndex == index && state.expectedBytes == total) {
            "GP-Next 分块写入顺序无效"
        }
        java.io.FileOutputStream(state.temporary, index > 0).buffered().use { output ->
            val buffer = ByteArray(values.length())
            for (position in buffer.indices) buffer[position] = values.getInt(position).toByte()
            output.write(buffer)
        }
        state.written += values.length()
        state.nextIndex += 1
        require(state.written <= state.expectedBytes) { "GP-Next 分块写入超出声明大小" }
        if (!transfer.optBoolean("final", false)) return false
        require(state.written == state.expectedBytes) { "GP-Next 分块写入不完整" }
        pendingWrites.remove(token)
        commitTemporaryWrite(state)
        if (pendingExports.remove(path.path)) {
            activity.runOnUiThread { activity.beginExistingFileExport(requestId, path) }
            return true
        }
        return false
    }

    private fun commitTemporaryWrite(state: PendingWrite) {
        val backup = File(state.path.parentFile, ".gardendless-backup-${System.nanoTime()}")
        if (state.path.exists()) {
            require(state.path.renameTo(backup)) { "无法暂存旧 GP-Next 文件" }
        }
        try {
            require(state.temporary.renameTo(state.path)) { "无法提交 GP-Next 文件" }
            if (backup.exists()) require(backup.delete()) { "无法清理旧 GP-Next 文件" }
        } catch (error: Exception) {
            if (!state.path.exists() && backup.exists()) backup.renameTo(state.path)
            state.temporary.delete()
            throw error
        }
    }

    @Synchronized
    fun destroy() {
        pendingWrites.values.forEach { it.temporary.delete() }
        pendingWrites.clear()
    }

    private fun prepareExport(args: JSONObject): String {
        val requested = args.optJSONObject("options")?.optString("defaultPath")
            ?.takeIf { it.isNotBlank() } ?: "gardendless-export.json"
        val directory = File(session.exportTemporaryRoot).absoluteFile
        ensureSafeDirectory(directory)
        val path = File(directory, safeFileName(requested)).absoluteFile
        require(path.parentFile == directory) { "导出文件名无效" }
        pendingExports.add(path.path)
        return path.path
    }

    private fun rename(args: JSONObject, options: JSONObject) {
        val oldOptions = JSONObject().put("baseDir", options.opt("oldPathBaseDir"))
        val newOptions = JSONObject().put("baseDir", options.opt("newPathBaseDir"))
        val source = resolve(args.opt("oldPath"), oldOptions)
        val destination = resolve(args.opt("newPath"), newOptions)
        requireSafeExisting(source)
        require(source != root) { "不允许移动 GP-Next 根目录" }
        require(!destination.exists()) { "目标路径已存在：${destination.path}" }
        ensureSafeDirectory(requireNotNull(destination.parentFile) { "目标路径没有父目录" })
        ensureNoSymlink(destination)
        require(source.renameTo(destination)) { "无法移动 GP-Next 路径" }
    }

    private fun remove(path: File, recursive: Boolean) {
        ensureNoSymlink(path)
        if (!path.exists()) return
        require(path != root) { "不允许删除 GP-Next 根目录" }
        if (path.isDirectory) {
            require(recursive) { "目录删除需要 recursive=true" }
            removeDirectoryTree(path)
            return
        }
        require(path.delete()) { "无法删除文件：${path.path}" }
    }

    private fun resolve(rawValue: Any?, options: JSONObject): File {
        val raw = rawValue as? String ?: throw GpNextFailure("GP-Next 文件路径为空")
        require(raw.isNotBlank()) { "GP-Next 文件路径为空" }
        val baseDir = options.opt("baseDir")
        require(baseDir == null || baseDir == JSONObject.NULL || baseDir == 14) {
            "不允许访问 Tauri baseDir $baseDir"
        }
        val normalizedRaw = decodeFilePath(raw).replace('\\', '/')
        val candidate = resolveGpNextSandboxPath(root, normalizedRaw)
        ensureNoSymlink(candidate)
        return candidate
    }

    private fun ensureNoSymlink(path: File) {
        require(!root.isSymbolicLink()) { "GP-Next 根目录不能是符号链接" }
        var current = root
        val relative = path.path.removePrefix(root.path).removePrefix(File.separator)
        if (relative.isEmpty()) return
        for (part in relative.split(File.separatorChar)) {
            current = File(current, part)
            if (current.isSymbolicLink()) throw GpNextFailure("不允许通过符号链接访问文件")
            if (!current.exists()) return
        }
    }

    private fun requireSafeExisting(path: File) {
        ensureNoSymlink(path)
        require(path.exists()) { "路径不存在：${path.path}" }
    }

    private fun ensureSafeDirectory(path: File) {
        require(path.isInside(root)) { "GP-Next 路径超出 Loader 沙箱" }
        ensureNoSymlink(path)
        if (!path.exists()) require(path.mkdirs()) { "无法创建目录：${path.path}" }
        require(path.isDirectory) { "路径不是目录：${path.path}" }
        ensureNoSymlink(path)
    }

    private fun removeDirectoryTree(directory: File) {
        require(!directory.isSymbolicLink()) { "不允许操作符号链接" }
        directory.listFiles().orEmpty().forEach { child ->
            require(!child.isSymbolicLink()) { "不允许操作符号链接" }
            if (child.isDirectory) removeDirectoryTree(child)
            else require(child.delete()) { "无法删除文件：${child.path}" }
        }
        require(directory.delete()) { "无法删除目录：${directory.path}" }
    }

    private fun decodeFilePath(value: String): String {
        val trimmed = value.trim()
        if (!trimmed.startsWith("file:")) return trimmed
        return runCatching { Uri.parse(trimmed).path }.getOrNull()
            ?: throw GpNextFailure("GP-Next 文件路径无效")
    }

    private fun nestedOptions(args: JSONObject, options: JSONObject): JSONObject =
        args.optJSONObject("options") ?: options

    private fun recursive(options: JSONObject): Boolean = options.optBoolean("recursive", true)

    private fun safeFileName(value: String): String {
        val base = value.replace('\\', '/').substringAfterLast('/').trim()
        val cleaned = base.replace(Regex("[\\x00-\\x1f:*?\"<>|]"), "_")
        return cleaned.takeUnless { it.isBlank() || it == "." || it == ".." }
            ?: "gardendless-export.json"
    }

    private data class PendingWrite(
        val path: File,
        val temporary: File,
        val expectedBytes: Long,
        var written: Long = 0,
        var nextIndex: Int = 0,
    )

    companion object {
        private const val MAX_WRITE_CHUNK_BYTES = 96 * 1024
        private const val MAX_WRITE_BYTES = 512L * 1024 * 1024
    }
}

private class GpNextFailure(message: String) : IllegalArgumentException(message)

private fun File.isInside(root: File): Boolean =
    path == root.path || path.startsWith(root.path + File.separator)

private fun File.isSymbolicLink(): Boolean = runCatching {
    OsConstants.S_ISLNK(Os.lstat(path).st_mode)
}.getOrDefault(false) || hasCanonicalLinkTarget()

private fun File.hasCanonicalLinkTarget(): Boolean = runCatching {
    val parent = parentFile?.canonicalFile
    val lexical = if (parent == null) absoluteFile else File(parent, name).absoluteFile
    lexical.canonicalFile != lexical
}.getOrDefault(false)
