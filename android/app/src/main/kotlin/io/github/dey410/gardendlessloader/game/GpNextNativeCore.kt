package io.github.dey410.gardendlessloader.game

import android.net.Uri
import android.system.Os
import android.system.OsConstants
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.RandomAccessFile
import java.util.UUID
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

class GpNextNativeCore(
    private val activity: GameActivity,
    private val session: NativeGameSession,
    private val bridge: GameBridge,
) {
    private val root = File(session.gpNextRoot).absoluteFile
    private val pendingExports = mutableSetOf<String>()
    private val handles = mutableMapOf<String, FileTransfer>()
    private data class FinishedTransfer(val mode: String, val terminal: String)
    private val finished = linkedMapOf<String, FinishedTransfer>()
    private val openingPaths = mutableSetOf<String>()
    private val resources = mutableMapOf<Closeable, String?>()
    private val queue = LinkedBlockingDeque<Runnable>(MAX_QUEUED_TASKS)
    private val executor = ThreadPoolExecutor(2, 2, 0L, TimeUnit.MILLISECONDS, queue)
    private val timer = ScheduledThreadPoolExecutor(1)
    private val lifetime = FileCommitGate()
    private val destroyed: Boolean get() = !lifetime.active

    init {
        executor.prestartAllCoreThreads()
        timer.scheduleAtFixedRate({
            execute(null, control = true) { expireHandles() }
        }, 1, 1, TimeUnit.MINUTES)
    }

    fun dispatch(requestId: String, request: JSONObject) {
        val command = request.optString("command")
        val args = request.optJSONObject("args") ?: JSONObject()
        val control = command == "file:finish" && args.optString("action") in setOf("close", "cancel")
        execute(requestId, control) {
            val options = request.optJSONObject("options") ?: JSONObject()
            if (!command.startsWith("file:")) { requireGpNext(); ensureGpDirectories() }
            val value: Any? = when (command) {
                "file:begin" -> beginFile(args)
                "file:chunk" -> chunkFile(args)
                "file:finish" -> {
                    if (finishFile(requestId, args)) return@execute
                    null
                }
                "plugin:fs|mkdir" -> {
                    ensureSafeDirectory(resolve(args.opt("path"), nestedOptions(args, options)))
                    null
                }
                "plugin:fs|read_dir" -> readDirectory(resolve(args.opt("path"), nestedOptions(args, options)))
                "plugin:fs|lstat" -> fileInfo(resolve(args.opt("path"), nestedOptions(args, options)))
                "plugin:fs|exists" -> exists(resolve(args.opt("path"), nestedOptions(args, options)))
                "plugin:fs|remove" -> {
                    remove(resolve(args.opt("path"), nestedOptions(args, options)), recursive(nestedOptions(args, options)))
                    null
                }
                "plugin:fs|rename" -> {
                    rename(args, nestedOptions(args, options))
                    null
                }
                "plugin:dialog|open" -> {
                    val dialogOptions = args.optJSONObject("options") ?: JSONObject()
                    require(!dialogOptions.optBoolean("multiple", false)) { "GP-Next 仅支持选择一个 Mod 包" }
                    postIfActive { activity.beginGpNextSelection(requestId, dialogOptions.optBoolean("directory", false)) }
                    return@execute
                }
                "plugin:dialog|save" -> prepareExport(args)
                "plugin:opener|open_url" -> {
                    postIfActive { activity.openGpNextUrl(args.optString("url"), requestId) }
                    return@execute
                }
                "plugin:opener|open_path" -> {
                    postIfActive { activity.beginGpNextPackageImport(requestId) }
                    return@execute
                }
                else -> throw FileFailure("unsupported", "未兼容的命令：$command")
            }
            checkActive()
            bridge.complete(requestId, value)
        }
    }

    // Picker staging and document copies share the same bounded host IO workers.
    fun execute(requestId: String?, control: Boolean = false, onRejected: (() -> Unit)? = null, operation: () -> Unit) {
        val task = RequestTask(requestId, operation, onRejected)
        if (destroyed) { task.reject("host_destroyed"); return }
        try {
            if (control) {
                synchronized(queue) {
                    if (!queue.offerFirst(task)) {
                        (queue.pollLast() as? RequestTask)?.reject("resource_limit_exceeded")
                        if (!queue.offerFirst(task)) throw RejectedExecutionException()
                    }
                    if (destroyed && queue.remove(task)) task.reject("host_destroyed")
                }
            } else executor.execute(task)
        } catch (_: RejectedExecutionException) {
            task.reject(if (destroyed) "host_destroyed" else "resource_limit_exceeded")
        }
    }

    fun postIfActive(operation: () -> Unit) {
        activity.runOnUiThread { if (!destroyed) operation() }
    }

    fun <T : Closeable, R> useResource(resource: T, handle: String? = null, operation: (T) -> R): R {
        synchronized(resources) {
            if (destroyed) { resource.close(); throw FileFailure("host_destroyed", "Game host was destroyed") }
            resources[resource] = handle
        }
        return try { checkActive(); operation(resource) } finally {
            synchronized(resources) { resources.remove(resource) }
            resource.close()
        }
    }

    private inner class RequestTask(val requestId: String?, val operation: () -> Unit, val onRejected: (() -> Unit)?) : Runnable {
        override fun run() {
            try { checkActive(); operation() } catch (error: Exception) {
                requestId?.let { bridge.fail(it, (error as? FileFailure)?.code ?: if (error is IllegalArgumentException) "invalid_file_transfer" else "io_failed",
                    if (error is FileFailure) error.message ?: "File operation failed" else "File operation failed") }
            }
        }
        fun reject(code: String) {
            onRejected?.invoke()
            requestId?.let { bridge.fail(it, code, "Host file task was rejected") }
        }
    }

    private fun checkActive() {
        if (destroyed || Thread.currentThread().isInterrupted) throw FileFailure("host_destroyed", "Game host was destroyed")
    }

    private fun ensureGpDirectories() {
        ensureSafeDirectory(root)
        ensureSafeDirectory(File(root, "packs"))
        ensureSafeDirectory(File(root, "patches"))
    }

    private fun requireGpNext() {
        if (!session.hasGpNext || !session.gpNextCompatible) throw FileFailure("gp_next_unavailable", "GP-Next compatibility is unavailable")
    }

    private fun beginFile(args: JSONObject): JSONObject {
        checkActive()
        val mode = args.optString("mode")
        require(mode == "read" || mode == "write") { "Invalid file mode" }
        val destination = args.optString("destination")
        require(destination == "gp-next" || destination == "export") { "Invalid file destination" }
        val options = args.optJSONObject("options") ?: JSONObject()
        require(!options.optBoolean("append", false)) { "Append writes are unsupported" }
        val token = UUID.randomUUID().toString()
        val path: File
        var export = destination == "export"
        if (destination == "gp-next") {
            requireGpNext()
            ensureGpDirectories()
            path = resolve(args.opt("path"), options)
            export = synchronized(this) { pendingExports.contains(path.path) }
        } else {
            require(mode == "write") { "Export destination is write-only" }
            val directory = File(session.exportTemporaryRoot).absoluteFile
            ensureSafeDirectory(directory)
            path = File(directory, ".export-$token")
        }
        require(mode == "write" || !export) { "Export destination is write-only" }
        val name = ExportDocumentSpec.safeFileName(args.optString("suggestedFilename").ifBlank { if (destination == "export") "gardendless-export.json" else path.name })
        val mime = args.optString("mimeType").ifBlank { "application/octet-stream" }
        synchronized(this) {
            checkActive()
            if (handles.size + openingPaths.size >= MAX_HANDLES) throw FileFailure("resource_limit_exceeded", "Too many open files")
            require(!openingPaths.contains(path.path)) { "File is already being opened" }
            if (mode == "write") require(handles.values.none { it.path == path && it.mode == "write" }) { "File already has an active writer" }
            openingPaths.add(path.path)
        }
        var descriptor: RandomAccessFile? = null
        var temporary: File? = null
        try {
            val size: Long
            if (mode == "read") {
                requireSafeExisting(path)
                require(path.isFile) { "File does not exist" }
                descriptor = RandomAccessFile(path, "r")
                size = descriptor.length()
            } else {
                size = integer(args, "totalBytes", MAX_FILE_BYTES)
                require(size in 0..MAX_FILE_BYTES) { "Invalid file size" }
                ensureSafeDirectory(requireNotNull(path.parentFile))
                ensureNoSymlink(path)
                temporary = File(path.parentFile, ".gardendless-write-$token")
                require(temporary.createNewFile()) { "File transaction already exists" }
                descriptor = RandomAccessFile(temporary, "rw")
            }
            if (size !in 0..MAX_FILE_BYTES) throw FileFailure("resource_limit_exceeded", "File exceeds 512 MiB")
            synchronized(this) {
                checkActive()
                handles[token] = FileTransfer(path, temporary, descriptor, mode, export, name, mime, FileTransferCursor(size))
                descriptor = null
            }
            return JSONObject().put("handle", token).put("sizeBytes", size)
        } catch (error: Exception) {
            runCatching { descriptor?.close() }
            temporary?.let { runCatching { it.delete() } }
            throw error
        } finally { synchronized(this) { openingPaths.remove(path.path) } }
    }

    private fun chunkFile(args: JSONObject): Any? {
        val state = getHandle(args.getString("handle"))
        synchronized(state) {
            checkTransfer(state)
            require(!state.exportPending) { "File commit is already pending" }
            val index = integer(args, "index", MAX_FILE_BYTES).toInt()
            val offset = integer(args, "offset", MAX_FILE_BYTES)
            val bytes: ByteArray
            if (state.mode == "read") {
                val length = integer(args, "length", MAX_CHUNK_BYTES.toLong()).toInt()
                state.cursor.validate(index, offset, length)
                bytes = ByteArray(length)
                state.descriptor.readFully(bytes)
            } else {
                val data = args.getString("data")
                require(data.length <= MAX_ENCODED_CHUNK && BASE64.matches(data)) { "Invalid Base64 chunk" }
                bytes = Base64.decode(data, Base64.NO_WRAP)
                require(Base64.encodeToString(bytes, Base64.NO_WRAP) == data) { "Non-canonical Base64 chunk" }
                state.cursor.validate(index, offset, bytes.size)
                state.descriptor.write(bytes)
            }
            checkTransfer(state)
            state.cursor.advance(bytes.size)
            return if (state.mode == "read") JSONObject().put("data", Base64.encodeToString(bytes, Base64.NO_WRAP)) else null
        }
    }

    private fun finishFile(requestId: String, args: JSONObject): Boolean {
        val token = args.getString("handle")
        val action = args.getString("action")
        require(action in setOf("close", "commit", "cancel")) { "Invalid file finish action" }
        val state = synchronized(this) {
            finished[token]?.let { completed ->
                validateFinished(completed.mode, completed.terminal, action)
                return false
            }
            handles[token] ?: throw FileFailure("invalid_file_transfer", "File handle is not active")
        }
        synchronized(state) {
            state.terminal.get()?.let { terminal ->
                validateFinished(state.mode, terminal, action)
                return false
            }
            checkTransfer(state)
            if (action == "cancel") {
                if (!state.terminal.compareAndSet(null, "cancelled")) return false
                state.cancelled = true
                closeResources(token)
                state.descriptor.close()
                finishHandle(token, state, "cancelled")
                state.commitRequestId?.let { bridge.fail(it, "cancelled", "Export was cancelled") }
                postIfActive { activity.cancelFileExport(token) }
                return false
            }
            require(!state.exportPending) { "File commit is already pending" }
            require((state.mode == "read" && action == "close") || (state.mode == "write" && action == "commit")) { "Invalid finish action for file mode" }
            if (action == "close") {
                check(state.terminal.compareAndSet(null, "closed"))
                state.descriptor.close()
                finishHandle(token, state, "closed")
                return false
            }
            state.cursor.requireComplete()
            state.descriptor.fd.sync()
            state.descriptor.close()
            checkActive()
            if (state.export) {
                state.exportPending = true
                state.commitRequestId = requestId
                postIfActive {
                    activity.beginExistingFileExport(requestId, token, requireNotNull(state.temporary), state.fileName, state.mimeType)
                }
                return true
            }
            ensureNoSymlink(state.path)
            try {
                lifetime.commit {
                    checkActive()
                    if (!state.terminal.compareAndSet(null, "committing")) throw FileFailure("cancelled", "File transaction was cancelled")
                    commitFileTransfer(requireNotNull(state.temporary), state.path)
                    state.terminal.set("committed")
                    finishHandle(token, state, "committed")
                }
            } catch (error: Exception) {
                state.terminal.set("failed")
                finishHandle(token, state, "failed")
                throw error
            }
            return false
        }
    }

    private fun validateFinished(mode: String, terminal: String, action: String) {
        require(action == "cancel" || (mode == "read" && action == "close") ||
            (mode == "write" && action == "commit")) { "Invalid finish action for file mode" }
        if (terminal == "cancelled" && action != "cancel") throw FileFailure("cancelled", "File transaction was cancelled")
        if (terminal == "failed") throw FileFailure("io_failed", "File transaction failed")
        check(terminal in setOf("closed", "committed", "cancelled")) { "File commit is still in progress" }
    }

    fun exportFinished(token: String, failureCode: String? = null, message: String? = null) {
        val state = synchronized(this) { handles[token] } ?: return
        synchronized(state) {
            if (destroyed || state.cancelled) return
            val requestId = state.commitRequestId ?: return
            val terminal = if (failureCode == null) "committed" else "failed"
            if (!state.terminal.compareAndSet(null, terminal)) return
            finishHandle(token, state, terminal)
            if (failureCode == null) bridge.complete(requestId, null)
            else bridge.fail(requestId, failureCode, message ?: "Export failed")
        }
    }

    fun isFileActive(token: String): Boolean = synchronized(this) { handles[token]?.let { !it.cancelled } == true && !destroyed }

    @Synchronized
    private fun getHandle(token: String): FileTransfer = handles[token]
        ?: throw FileFailure("invalid_file_transfer", "File handle is not active")

    private fun checkTransfer(state: FileTransfer) {
        checkActive()
        if (state.cancelled || state.terminal.get() != null) throw FileFailure("cancelled", "File transaction was cancelled")
        if (System.nanoTime() > state.deadlineNanos) throw FileFailure("deadline_exceeded", "File transaction expired")
    }

    private fun finishHandle(token: String, state: FileTransfer, terminal: String) {
        synchronized(this) {
            handles.remove(token)
            if (terminal == "committed") pendingExports.remove(state.path.path)
            finished[token] = FinishedTransfer(state.mode, terminal)
            while (finished.size > MAX_FINISHED_HANDLES) finished.remove(finished.keys.first())
        }
        state.temporary?.let { runCatching { if (it.exists()) it.delete() } }
    }

    private fun expireHandles() {
        val expired = synchronized(this) { handles.filterValues { System.nanoTime() > it.deadlineNanos }.toList() }
        expired.forEach { (token, state) -> synchronized(state) {
            if (!state.terminal.compareAndSet(null, "failed")) return@synchronized
            state.cancelled = true
            closeResources(token)
            runCatching { state.descriptor.close() }
            finishHandle(token, state, "failed")
            state.commitRequestId?.let { bridge.fail(it, "deadline_exceeded", "File transaction expired") }
            postIfActive { activity.cancelFileExport(token) }
        } }
    }

    fun destroy() {
        if (!lifetime.stop()) return
        timer.shutdownNow()
        executor.shutdownNow().filterIsInstance<RequestTask>().forEach { it.reject("host_destroyed") }
        val transfers = synchronized(this) { handles.values.toList().also { handles.clear(); pendingExports.clear() } }
        transfers.forEach { if (it.terminal.compareAndSet(null, "cancelled")) it.cancelled = true }
        // Closing descriptors interrupts in-flight IO; teardown itself never blocks the UI.
        thread(name = "GardendlessFileClose") {
            transfers.forEach { state ->
                runCatching { state.descriptor.close() }
                if (state.terminal.get() != "committing") state.temporary?.let { runCatching { it.delete() } }
            }
            synchronized(resources) { resources.keys.toList().also { resources.clear() } }
                .forEach { runCatching { it.close() } }
        }
    }

    private fun closeResources(handle: String) {
        val closing = synchronized(resources) {
            resources.filterValues { it == handle }.keys.toList().also { values -> values.forEach { resources.remove(it) } }
        }
        closing.forEach { runCatching { it.close() } }
    }

    private fun integer(args: JSONObject, name: String, maximum: Long): Long {
        val value = args.get(name)
        require(value is Number && value.toDouble().isFinite()) { "Invalid file integer" }
        val number = value.toLong()
        require(number in 0..maximum && value.toDouble() == number.toDouble()) { "Invalid file integer" }
        return number
    }

    private fun prepareExport(args: JSONObject): String {
        val requested = args.optJSONObject("options")?.optString("defaultPath")?.takeIf { it.isNotBlank() }
            ?: "gardendless-export.json"
        val directory = File(session.exportTemporaryRoot).absoluteFile
        ensureSafeDirectory(directory)
        val path = File(directory, ExportDocumentSpec.safeFileName(requested)).absoluteFile
        synchronized(this) {
            require(pendingExports.size < MAX_HANDLES || path.path in pendingExports) { "Too many pending exports" }
            pendingExports.add(path.path)
        }
        return path.path
    }

    private fun readDirectory(path: File): JSONArray {
        requireSafeExisting(path)
        require(path.isDirectory) { "目录不存在" }
        val result = JSONArray()
        path.listFiles().orEmpty().sortedBy { it.name }.forEach { child ->
            val symlink = child.isSymbolicLink()
            result.put(JSONObject().put("name", child.name).put("isFile", !symlink && child.isFile)
                .put("isDirectory", !symlink && child.isDirectory).put("isSymlink", symlink))
        }
        return result
    }

    private fun fileInfo(path: File): JSONObject {
        requireSafeExisting(path)
        val symlink = path.isSymbolicLink()
        return JSONObject().put("isFile", !symlink && path.isFile).put("isDirectory", !symlink && path.isDirectory)
            .put("isSymlink", symlink).put("size", if (path.isFile) path.length() else 0)
            .put("mtime", JSONObject.NULL).put("atime", JSONObject.NULL).put("birthtime", JSONObject.NULL)
            .put("readonly", !path.canWrite()).put("fileAttributes", JSONObject.NULL)
            .put("dev", 0).put("ino", 0).put("mode", 0).put("nlink", 0).put("uid", 0).put("gid", 0)
            .put("rdev", 0).put("blksize", 0).put("blocks", 0)
    }

    private fun exists(path: File): Boolean { ensureNoSymlink(path); return path.exists() }

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
        if (!path.exists()) require(path.mkdirs() || path.isDirectory) { "无法创建目录" }
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

    private data class FileTransfer(
        val path: File,
        val temporary: File?,
        val descriptor: RandomAccessFile,
        val mode: String,
        val export: Boolean,
        val fileName: String,
        val mimeType: String,
        val cursor: FileTransferCursor,
        val deadlineNanos: Long = System.nanoTime() + TimeUnit.MINUTES.toNanos(10),
        val terminal: AtomicReference<String?> = AtomicReference(null),
        @Volatile var cancelled: Boolean = false,
        var exportPending: Boolean = false,
        var commitRequestId: String? = null,
    )

    companion object {
        internal const val MAX_CHUNK_BYTES = 64 * 1024
        internal const val MAX_FILE_BYTES = 512L * 1024 * 1024
        private const val MAX_ENCODED_CHUNK = ((MAX_CHUNK_BYTES + 2) / 3) * 4
        private const val MAX_HANDLES = 8
        private const val MAX_FINISHED_HANDLES = 128
        private const val MAX_QUEUED_TASKS = 16
        private val BASE64 = Regex("[A-Za-z0-9+/]*={0,2}")
    }
}

// The transaction's cursor is shared by read and write; validation precedes IO.
internal class FileTransferCursor(val expectedBytes: Long) {
    var offset = 0L
        private set
    var nextIndex = 0
        private set

    fun validate(index: Int, suppliedOffset: Long, count: Int) {
        require(index == nextIndex && suppliedOffset == offset) { "File chunk sequence is invalid" }
        require(count in 1..GpNextNativeCore.MAX_CHUNK_BYTES) { "File chunk size is invalid" }
        require(count.toLong() <= expectedBytes - offset) { "File chunk exceeds declared size" }
    }

    fun advance(count: Int) { offset += count; nextIndex += 1 }
    fun requireComplete() { require(offset == expectedBytes) { "File transaction is incomplete" } }
}

// Android's same-directory rename replaces the destination atomically and keeps
// already-open read descriptors on their original file version.
internal fun commitFileTransfer(temporary: File, destination: File) {
    require(temporary.parentFile == destination.parentFile) { "File commit must remain in one directory" }
    check(temporary.renameTo(destination)) { "Cannot commit file transaction" }
}

private class FileFailure(val code: String, message: String) : IllegalArgumentException(message)

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
