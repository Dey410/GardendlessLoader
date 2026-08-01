package io.github.dey410.gardendlessloader.game

import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile
import java.net.URI
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import android.system.Os
import android.system.OsConstants

data class GameResourceResponse(
    val statusCode: Int,
    val reason: String,
    val mimeType: String,
    val encoding: String?,
    val headers: Map<String, String>,
    val body: InputStream,
)

class GameResourceResolver(root: File) {
    private val canonicalRoot = root.absoluteFile.also {
        require(!it.isSymbolicLink()) { "Resource root must not be a symbolic link" }
    }.canonicalFile.also {
        require(it.isDirectory) { "Resource root is not a directory" }
    }

    fun resolve(
        url: String,
        method: String,
        requestHeaders: Map<String, String> = emptyMap(),
    ): GameResourceResponse {
        if (method != "GET" && method != "HEAD") {
            return error(405, "Method Not Allowed", mapOf("Allow" to "GET, HEAD"))
        }
        val uri = runCatching { URI(url) }.getOrNull()
            ?: return error(400, "Bad Request")
        if (uri.scheme != "https" || uri.host != "appassets.androidplatform.net") {
            return error(403, "Forbidden")
        }
        val relativePath = decodePath(uri.rawPath ?: "/")
            ?: return error(403, "Forbidden")
        val file = resolveFile(relativePath) ?: return error(404, "Not Found")
        val length = file.length()
        val etag = etag(file, length)
        val commonHeaders = linkedMapOf(
            "Accept-Ranges" to "bytes",
            "ETag" to etag,
            "Cache-Control" to cacheControl(relativePath),
            "X-Content-Type-Options" to "nosniff",
        )
        if (requestHeaders.value("If-None-Match") == etag) {
            return GameResourceResponse(
                statusCode = 304,
                reason = "Not Modified",
                mimeType = mimeFor(relativePath),
                encoding = encodingFor(relativePath),
                headers = commonHeaders,
                body = ByteArrayInputStream(ByteArray(0)),
            )
        }
        val rangeHeader = requestHeaders.value("Range")
        val range = rangeHeader?.let { parseRange(it, length) }
        if (rangeHeader != null && range == null) {
            return error(
                416,
                "Range Not Satisfiable",
                commonHeaders + ("Content-Range" to "bytes */$length"),
            )
        }
        val start = range?.first ?: 0L
        val end = range?.last ?: (length - 1L)
        val responseLength = if (length == 0L) 0L else end - start + 1L
        val headers = linkedMapOf<String, String>().apply {
            putAll(commonHeaders)
            put("Content-Length", responseLength.toString())
            if (range != null) {
                put("Content-Range", "bytes $start-$end/$length")
            }
        }
        val body = if (method == "HEAD" || responseLength == 0L) {
            ByteArrayInputStream(ByteArray(0))
        } else {
            RangedFileInputStream(file, start, responseLength)
        }
        return GameResourceResponse(
            statusCode = if (range == null) 200 else 206,
            reason = if (range == null) "OK" else "Partial Content",
            mimeType = mimeFor(relativePath),
            encoding = encodingFor(relativePath),
            headers = headers,
            body = body,
        )
    }

    private fun resolveFile(relativePath: String): File? {
        val candidate = File(canonicalRoot, relativePath)
        var cursor: File? = candidate
        while (cursor != null && cursor != canonicalRoot) {
            if (cursor.isSymbolicLink()) return null
            cursor = cursor.parentFile
        }
        if (cursor == null) return null
        val canonical = runCatching { candidate.canonicalFile }.getOrNull() ?: return null
        if (canonical != canonicalRoot && !canonical.path.startsWith(canonicalRoot.path + File.separator)) return null
        return canonical.takeIf { it.isFile }
    }

    private fun decodePath(rawPath: String): String? {
        val decoded = percentDecode(rawPath) ?: return null
        if (encodedEscape.containsMatchIn(decoded)) return null
        val path = decoded.removePrefix("/").ifEmpty { "index.html" }
        if (path.contains('\\') || path.indexOf('\u0000') >= 0) return null
        val segments = path.split('/')
        if (segments.any { it.isEmpty() || it == "." || it == ".." }) return null
        return segments.joinToString(File.separator)
    }

    private fun percentDecode(value: String): String? {
        val output = java.io.ByteArrayOutputStream(value.length)
        var index = 0
        while (index < value.length) {
            val char = value[index]
            if (char == '%') {
                if (index + 2 >= value.length) return null
                val byte = value.substring(index + 1, index + 3).toIntOrNull(16)
                    ?: return null
                output.write(byte)
                index += 3
            } else {
                output.write(char.toString().toByteArray(StandardCharsets.UTF_8))
                index += 1
            }
        }
        return output.toString(StandardCharsets.UTF_8.name())
    }

    private fun parseRange(value: String, length: Long): LongRange? {
        if (length <= 0L || !value.startsWith("bytes=") || value.contains(',')) return null
        val parts = value.removePrefix("bytes=").split('-', limit = 2)
        if (parts.size != 2) return null
        if (parts[0].isEmpty()) {
            val suffix = parts[1].toLongOrNull() ?: return null
            if (suffix <= 0L) return null
            val start = (length - suffix).coerceAtLeast(0L)
            return start..(length - 1L)
        }
        val start = parts[0].toLongOrNull() ?: return null
        if (start < 0L || start >= length) return null
        val requestedEnd = if (parts[1].isEmpty()) {
            length - 1L
        } else {
            parts[1].toLongOrNull() ?: return null
        }
        if (requestedEnd < start) return null
        return start..requestedEnd.coerceAtMost(length - 1L)
    }

    private fun etag(file: File, length: Long): String {
        val value = "${file.lastModified()}:$length".toByteArray()
        val digest = MessageDigest.getInstance("SHA-256").digest(value)
        return digest.take(12).joinToString(prefix = "\"", postfix = "\"") {
            "%02x".format(it)
        }
    }

    private fun cacheControl(relativePath: String): String {
        val normalized = relativePath.replace(File.separatorChar, '/')
        if (normalized == "index.html" ||
            normalized == "src/settings.json" ||
            normalized == "src/import-map.json"
        ) {
            return "no-cache"
        }
        if (contentHash.containsMatchIn(normalized.substringAfterLast('/'))) {
            return "public, max-age=31536000, immutable"
        }
        return when (normalized.substringAfterLast('.', "").lowercase(Locale.US)) {
            "png", "jpg", "jpeg", "gif", "webp", "svg", "mp3", "ogg", "wav",
            "mp4", "webm", "wasm", "bin" -> "public, max-age=86400"
            else -> "no-cache"
        }
    }

    private fun mimeFor(path: String): String = when (path.substringAfterLast('.', "").lowercase(Locale.US)) {
        "html", "htm" -> "text/html"
        "js", "mjs" -> "application/javascript"
        "css" -> "text/css"
        "json", "json5" -> "application/json"
        "wasm" -> "application/wasm"
        "svg" -> "image/svg+xml"
        "png" -> "image/png"
        "jpg", "jpeg" -> "image/jpeg"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "mp3" -> "audio/mpeg"
        "ogg" -> "audio/ogg"
        "wav" -> "audio/wav"
        "mp4" -> "video/mp4"
        "webm" -> "video/webm"
        "woff" -> "font/woff"
        "woff2" -> "font/woff2"
        "ttf" -> "font/ttf"
        else -> "application/octet-stream"
    }

    private fun encodingFor(path: String): String? = when (mimeFor(path)) {
        "text/html", "application/javascript", "text/css", "application/json",
        "image/svg+xml" -> "UTF-8"
        else -> null
    }

    private fun error(
        status: Int,
        reason: String,
        headers: Map<String, String> = emptyMap(),
    ) = GameResourceResponse(
        statusCode = status,
        reason = reason,
        mimeType = "text/plain",
        encoding = "UTF-8",
        headers = headers + ("Content-Length" to "0"),
        body = ByteArrayInputStream(ByteArray(0)),
    )

    private fun Map<String, String>.value(name: String): String? {
        return entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
    }

    companion object {
        private val encodedEscape = Regex("(?i)%(?:2e|2f|5c|25)")
        private val contentHash = Regex("(?i)(?:^|[._-])[0-9a-f]{8,}(?:[._-]|$)")
    }
}

private fun File.isSymbolicLink(): Boolean = runCatching {
    OsConstants.S_ISLNK(Os.lstat(path).st_mode)
}.getOrDefault(false) || hasCanonicalLinkTarget()

private fun File.hasCanonicalLinkTarget(): Boolean = runCatching {
    val parent = parentFile?.canonicalFile
    val lexical = if (parent == null) absoluteFile else File(parent, name).absoluteFile
    lexical.canonicalFile != lexical
}.getOrDefault(false)

private class RangedFileInputStream(
    file: File,
    start: Long,
    private var remaining: Long,
) : InputStream() {
    private val source = RandomAccessFile(file, "r").apply { seek(start) }

    override fun read(): Int {
        if (remaining <= 0L) return -1
        val value = source.read()
        if (value >= 0) remaining -= 1
        return value
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (remaining <= 0L) return -1
        val count = source.read(buffer, offset, minOf(length.toLong(), remaining).toInt())
        if (count > 0) remaining -= count
        return count
    }

    override fun close() {
        source.close()
    }
}
