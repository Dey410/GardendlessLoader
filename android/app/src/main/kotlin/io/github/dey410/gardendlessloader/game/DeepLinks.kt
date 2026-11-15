package io.github.dey410.gardendlessloader.game

import android.os.SystemClock
import java.net.URI
import java.net.URLDecoder

/**
 * pvzge: links that GP-Next's websites open: a Nest one-click install, a
 * Daily Level and a GitHub level. Only these three exact forms pass; GP-Next
 * validates them again before it acts on one.
 */
object DeepLinks {
    private const val MAX_LENGTH = 4096
    private val VERSION = Regex("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")
    private val DATE = Regex("(\\d{4})-(\\d{2})-(\\d{2})")
    private val SLOT = Regex("[0-9]{1,9}")
    private val SLUG = Regex("[a-z0-9]+(?:-[a-z0-9]+)*")
    private val SHA1 = Regex("[a-f0-9]{40}")
    private val CONTROL = Regex("[\\\\\\x00-\\x1f\\x7f]")

    /** The link itself when it is one of the three supported forms, else null. */
    fun validate(raw: String?): String? {
        if (raw == null || raw.isEmpty() || raw.length > MAX_LENGTH) return null
        if (raw.any { it.code !in 0x21..0x7e }) return null
        val uri = runCatching { URI(raw) }.getOrNull() ?: return null
        if (uri.scheme != "pvzge" || uri.rawUserInfo != null || uri.port != -1 || uri.rawFragment != null) return null
        if (uri.rawAuthority != uri.host) return null
        val query = parseQuery(uri.rawQuery) ?: return null
        val valid = when (uri.host) {
            "nest" -> uri.rawPath == "/import" && query.keys == setOf("version") &&
                VERSION.matches(query.getValue("version"))
            "daily-level" -> uri.rawPath == "/open" && query.keys == setOf("date", "slot", "slug") &&
                isDate(query.getValue("date")) && SLOT.matches(query.getValue("slot")) &&
                query.getValue("slug").length <= 200 && SLUG.matches(query.getValue("slug"))
            "github-level" -> uri.rawPath == "/open" && query.keys == setOf("path", "sha") &&
                SHA1.matches(query.getValue("sha")) && isLevelPath(query.getValue("path"))
            else -> false
        }
        return raw.takeIf { valid }
    }

    /** Each key once; null for a malformed or repeated parameter. */
    private fun parseQuery(raw: String?): Map<String, String>? {
        if (raw.isNullOrEmpty()) return null
        val result = linkedMapOf<String, String>()
        for (pair in raw.split('&')) {
            val separator = pair.indexOf('=')
            if (separator <= 0) return null
            val key = decode(pair.substring(0, separator)) ?: return null
            val value = decode(pair.substring(separator + 1)) ?: return null
            if (result.put(key, value) != null) return null
        }
        return result
    }

    private fun decode(value: String): String? = runCatching { URLDecoder.decode(value, "UTF-8") }.getOrNull()

    private fun isDate(value: String): Boolean {
        val match = DATE.matchEntire(value) ?: return false
        val (yearText, monthText, dayText) = match.destructured
        val year = yearText.toInt()
        val month = monthText.toInt()
        val day = dayText.toInt()
        if (month !in 1..12 || day < 1) return false
        val leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        val days = intArrayOf(31, if (leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
        return day <= days[month - 1]
    }

    private fun isLevelPath(value: String): Boolean =
        value.isNotEmpty() && value.length <= 2048 && value.endsWith(".json", ignoreCase = true) &&
            !CONTROL.containsMatchIn(value) && value.split('/').none { it.isEmpty() || it == "." || it == ".." }
}

/**
 * Validated links wait here, in the app process, until a game page takes
 * them with host:takeDeepLinks. A link nobody takes within ten minutes is
 * dropped so it cannot surprise a later game.
 */
object DeepLinkInbox {
    private const val MAX_LINKS = 8
    private const val LIFETIME_MS = 10 * 60 * 1000L

    private class Entry(val url: String, val receivedAt: Long)

    private val entries = ArrayDeque<Entry>()

    /** Set by the running game; told on the main thread that a link arrived. */
    @Volatile
    var onAvailable: (() -> Unit)? = null

    fun offer(url: String) {
        synchronized(this) {
            prune()
            entries.removeAll { it.url == url }
            entries.addLast(Entry(url, SystemClock.elapsedRealtime()))
            while (entries.size > MAX_LINKS) entries.removeFirst()
        }
        onAvailable?.invoke()
    }

    fun drain(): List<String> = synchronized(this) {
        prune()
        entries.map { it.url }.also { entries.clear() }
    }

    private fun prune() {
        val now = SystemClock.elapsedRealtime()
        entries.removeAll { now - it.receivedAt > LIFETIME_MS }
    }
}
