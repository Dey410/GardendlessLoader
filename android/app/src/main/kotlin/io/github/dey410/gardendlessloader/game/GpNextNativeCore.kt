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
    private val appRoot = File(session.appRoot).absoluteFile
    private val pendingExports = mutableSetOf<String>()

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
                    "plugin:fs|exists" -> exists(resolve(args.opt("path"), nestedOptions(args, options)))
                    "plugin:fs|remove" -> {
                        remove(resolve(args.opt("path"), nestedOptions(args, options)), recursive(nestedOptions(args, options)))
                        null
                    }
                    "plugin:fs|write_text_file" -> {
                        if (writeFile(requestId, request, args, options)) {
                            return@thread
                        }
                        null
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
        val candidate = if (normalizedRaw.startsWith('/')) {
            File(normalizedRaw).absoluteFile
        } else {
            File(appRoot, normalizedRaw).absoluteFile
        }
        require(!normalizedRaw.split('/').any { it == ".." }) { "GP-Next 路径超出 Loader 沙箱" }
        require(candidate.isInside(root)) { "GP-Next 路径超出 Loader 沙箱" }
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
