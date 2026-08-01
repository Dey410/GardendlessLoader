package io.github.dey410.gardendlessloader.game

import org.json.JSONArray
import org.json.JSONObject

data class NativeGameSession(
    val sessionId: String,
    val resourceRoot: String,
    val origin: String,
    val entryUrl: String,
    val activationGeneration: Long,
    val hasGpNext: Boolean,
    val gpNextCompatible: Boolean,
    val gpNextVersion: String?,
    val watermarkEnabled: Boolean,
    val autoCollectSunEnabled: Boolean,
    val allowedRemoteHosts: Set<String>,
    val gpNextRoot: String,
    val exportTemporaryRoot: String,
) {
    val appRoot: String
        get() = java.io.File(resourceRoot).parentFile?.absolutePath
            ?: throw IllegalArgumentException("resourceRoot has no parent")
}

object GameSessionCodec {
    const val ORIGIN = "https://appassets.androidplatform.net"

    fun decode(raw: String): NativeGameSession {
        require(raw.length <= 1024 * 1024) { "Game session is too large" }
        val json = JSONObject(raw)
        require(json.optInt("schemaVersion") == 1) { "Unsupported game session schema" }
        require(json.getString("platform") == "android") { "Game session platform mismatch" }
        require(json.getString("origin") == ORIGIN) { "Game session origin mismatch" }
        val entryUrl = json.getString("entryUrl")
        require(entryUrl.startsWith("$ORIGIN/")) { "Entry URL escaped the game origin" }
        val remoteHosts = json.optJSONArray("allowedRemoteHosts") ?: JSONArray()
        return NativeGameSession(
            sessionId = json.requiredString("sessionId"),
            resourceRoot = json.requiredString("resourceRoot"),
            origin = ORIGIN,
            entryUrl = entryUrl,
            activationGeneration = json.getLong("activationGeneration"),
            hasGpNext = json.getBoolean("hasGpNext"),
            gpNextCompatible = json.getBoolean("gpNextCompatible"),
            gpNextVersion = json.optString("gpNextVersion").takeIf { it.isNotBlank() },
            watermarkEnabled = json.getBoolean("watermarkEnabled"),
            autoCollectSunEnabled = json.getBoolean("autoCollectSunEnabled"),
            allowedRemoteHosts = buildSet {
                for (index in 0 until remoteHosts.length()) {
                    val host = remoteHosts.getString(index).lowercase()
                    require(isValidRemoteHost(host)) { "Invalid remote host" }
                    add(host)
                }
            },
            gpNextRoot = json.requiredString("gpNextRoot"),
            exportTemporaryRoot = json.requiredString("exportTemporaryRoot"),
        )
    }

    private fun JSONObject.requiredString(key: String): String {
        return getString(key).also { require(it.isNotBlank()) { "$key is empty" } }
    }
}

private fun isValidRemoteHost(host: String): Boolean {
    if (host.isEmpty() || host.length > 253) return false
    return host.split('.').all { label ->
        label.isNotEmpty() &&
            label.length <= 63 &&
            label.first().isLetterOrDigit() &&
            label.last().isLetterOrDigit() &&
            label.all { it.isLetterOrDigit() || it == '-' }
    }
}
