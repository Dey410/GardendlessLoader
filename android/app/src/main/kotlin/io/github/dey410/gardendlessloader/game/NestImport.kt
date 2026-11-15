package io.github.dey410.gardendlessloader.game

import org.json.JSONObject
import java.net.URI
import java.net.URL

/**
 * GP-Next's download_nest_import contract. Nest answers
 * https://nest.pvzge.com/api/game-imports/<version> with a descriptor that
 * names a short-lived package URL, its SHA-256 and its size. GP-Next expects
 * the package framed as a little-endian u32 descriptor length, the descriptor
 * JSON and the package bytes, and validates all three again.
 */
internal object NestImport {
    const val MAX_PACKAGE_BYTES = 100L * 1024 * 1024
    const val MAX_DESCRIPTOR_BYTES = 64 * 1024
    private const val MAX_LEVEL_BYTES = 10_000_000L
    private const val MAX_HEADER_BYTES = 16 * 1024
    private val UUID = Regex("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")
    private val SHA256 = Regex("[a-f0-9]{64}")

    class Descriptor(val header: ByteArray, val url: URL, val sha256: String, val byteLength: Long)

    fun isVersionId(value: String): Boolean = UUID.matches(value)

    fun descriptorUrl(versionId: String): URL {
        require(isVersionId(versionId)) { "NEST_INTENT" }
        return URL("https://nest.pvzge.com/api/game-imports/$versionId")
    }

    /** Nest's JSON error code, such as game-import-unsupported. */
    fun errorCode(body: ByteArray): String? = runCatching {
        JSONObject(body.toString(Charsets.UTF_8)).optString("error")
    }.getOrNull()?.takeIf { it.matches(Regex("[a-z0-9-]{1,64}")) }

    fun parse(body: ByteArray, versionId: String): Descriptor {
        val json = runCatching { JSONObject(body.toString(Charsets.UTF_8)) }.getOrNull() ?: failure("NEST_DESCRIPTOR")
        val projectId = json.optString("projectId")
        val type = json.optString("type")
        val format = json.optString("format")
        val sha256 = json.optString("sha256")
        val byteLength = json.opt("byteLength") as? Number ?: failure("NEST_DESCRIPTOR")
        val size = byteLength.toLong()
        if (json.opt("protocolVersion") != 1 || json.optString("versionId") != versionId ||
            !projectId.startsWith("prj_") || !UUID.matches(projectId.removePrefix("prj_")) ||
            (json.opt("name") as? String).isNullOrEmpty() || (json.opt("version") as? String).isNullOrEmpty() ||
            !SHA256.matches(sha256) || byteLength.toDouble() != size.toDouble() || size <= 0 ||
            (json.opt("expiresAt") as? String).isNullOrEmpty()
        ) failure("NEST_DESCRIPTOR")
        val level = type == "level" && format in setOf("json", "json5")
        val archive = type in setOf("datapack", "mod") && format == "zip"
        if (!level && !archive) failure("NEST_UNSUPPORTED_FORMAT")
        if (size > (if (level) MAX_LEVEL_BYTES else MAX_PACKAGE_BYTES)) failure("NEST_LENGTH")
        val url = downloadUrl(json.optString("url")) ?: failure("NEST_DOWNLOAD_URL")
        // Only the fields GP-Next reads travel on; the signed URL stays here.
        val header = JSONObject()
            .put("protocolVersion", 1)
            .put("versionId", versionId)
            .put("projectId", projectId)
            .put("type", type)
            .put("format", format)
            .put("version", json.getString("version"))
            .put("name", json.getString("name"))
            .put("expiresAt", json.getString("expiresAt"))
            .put("sha256", sha256)
            .put("byteLength", size)
            .toString()
            .toByteArray(Charsets.UTF_8)
        if (header.size > MAX_HEADER_BYTES) failure("NEST_DESCRIPTOR")
        return Descriptor(header, url, sha256, size)
    }

    /**
     * Nest serves packages from its Cloudflare R2 bucket through presigned
     * HTTPS URLs; the bytes must still match the descriptor's SHA-256.
     */
    fun downloadUrl(raw: String): URL? {
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        val host = uri.host?.lowercase() ?: return null
        if (uri.scheme != "https" || uri.rawUserInfo != null || uri.rawFragment != null ||
            (uri.port != -1 && uri.port != 443)
        ) return null
        if (host != "nest.pvzge.com" && !host.endsWith(".r2.cloudflarestorage.com")) return null
        return runCatching { uri.toURL() }.getOrNull()
    }

    private fun failure(code: String): Nothing = throw NestImportFailure(code)
}

/** Its message is the GP-Next-facing reason, such as NEST_HASH. */
internal class NestImportFailure(message: String) : Exception(message)
