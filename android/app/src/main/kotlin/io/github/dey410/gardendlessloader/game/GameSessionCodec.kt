package io.github.dey410.gardendlessloader.game

import org.json.JSONArray
import org.json.JSONObject

/**
 * How the game viewport fits the screen. The game shows 16:10 to 17:9 without
 * distortion and its whole picture at 17:9.
 */
enum class GameScreenFit(val wireName: String) {
    /** Clamps the viewport to 16:10–17:9: trims some of the picture for smaller black bars. */
    BALANCED("balanced"),

    /** Keeps the viewport at 17:9 so the whole picture shows, with larger black bars. */
    SHOW_ALL("showAll"),

    /** Stretches the balanced viewport over the whole screen. */
    STRETCH("stretch"),
}

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
    val detailedAudioDiagnosticsEnabled: Boolean = false,
    val renderScale: Double? = null,
    val screenFit: GameScreenFit = GameScreenFit.BALANCED,
    val packageId: String = "unknown",
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
        val packageId = json.optString("packageId", "unknown")
        require(packageId == "unknown" || packageId.matches(Regex("sha256:[a-f0-9]{64}"))) { "Invalid package identity" }
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
            detailedAudioDiagnosticsEnabled = json.optBoolean("detailedAudioDiagnosticsEnabled", false),
            renderScale = if (json.isNull("renderScale")) null else {
                json.getDouble("renderScale").also {
                    require(it > 0) { "Invalid render scale" }
                }
            },
            screenFit = json.optString("screenFit", GameScreenFit.BALANCED.wireName).let { name ->
                requireNotNull(GameScreenFit.entries.firstOrNull { it.wireName == name }) { "Invalid screen fit" }
            },
            packageId = packageId,
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
