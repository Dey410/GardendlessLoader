package io.github.dey410.gardendlessloader.logging

import android.content.Context
import android.os.Build
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedWriter
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONArray
import org.json.JSONObject

object AppLogStore {
    private const val channelName = "io.github.dey410.gardendlessloader/app_logger"
    private const val segmentSizeBytes = 2L * 1024L * 1024L
    private const val totalSizeBytes = 10L * 1024L * 1024L
    private const val recentCapacity = 500
    private const val queueCapacity = 1000
    private const val retentionDays = 7L
    private const val completedSessionLimit = 5

    private val lock = Any()
    private val writeFailureCount = AtomicInteger()
    private val dropped = mutableMapOf<String, Int>()
    private val recent = ArrayDeque<Map<String, Any?>>()
    private val executor = ThreadPoolExecutor(
        1,
        1,
        0L,
        TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(queueCapacity),
    )

    private var initialized = false
    private var degraded = false
    private lateinit var logsDirectory: File
    private lateinit var markerFile: File
    private lateinit var appSessionId: String
    private var monotonicOriginMs = 0L
    private var sequence = 0L
    private var segment = 0
    private var currentFile: File? = null
    private var writer: BufferedWriter? = null

    fun install(context: Context, messenger: BinaryMessenger) {
        initialize(context.applicationContext)
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> result.success(mapOf("appSessionId" to appSessionId))
                "emit" -> {
                    @Suppress("UNCHECKED_CAST")
                    val value = call.arguments as? Map<String, Any?>
                    if (value == null) {
                        result.error("invalid_log_event", "Log event must be a map", null)
                    } else {
                        emit(value)
                        result.success(null)
                    }
                }
                "snapshot" -> {
                    val limit = call.argument<Int>("limit") ?: recentCapacity
                    result.success(snapshot(limit))
                }
                "flush" -> {
                    flush(500)
                    result.success(null)
                }
                "deleteHistory" -> {
                    deleteHistory()
                    result.success(null)
                }
                "endSession" -> {
                    endSession()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun initialize(context: Context) {
        synchronized(lock) {
            if (initialized) return
            initialized = true
            logsDirectory = File(context.filesDir, "logs")
            markerFile = File(logsDirectory, "active-session.json")
            val previousSession = readPreviousSession()
            appSessionId = newSessionId()
            monotonicOriginMs = SystemClock.elapsedRealtime()
            runCatching { logsDirectory.mkdirs() }.onFailure { degrade() }
            writeMarker()
            cleanupLocked()
            emitImmediate(
                mutableMapOf(
                    "source" to "android",
                    "level" to "INFO",
                    "category" to "app.lifecycle",
                    "event" to "app_session_started",
                    "outcome" to "started",
                    "context" to mapOf(
                        "platform" to "android",
                        "appVersion" to appVersion(context),
                        "osVersion" to Build.VERSION.RELEASE,
                    ),
                ),
            )
            if (!previousSession.isNullOrBlank() && previousSession != appSessionId) {
                val previousLast = readLastEvent(previousSession)
                emitImmediate(
                    mutableMapOf(
                        "source" to "android",
                        "level" to "WARN",
                        "category" to "app.lifecycle",
                        "event" to "previous_run_unclean_shutdown",
                        "outcome" to "observed",
                        "code" to "previous_run_unclean_shutdown",
                        "context" to mapOf(
                            "previousAppSessionId" to previousSession,
                            "previousLastEvent" to previousLast?.optString("event"),
                            "previousLastCode" to previousLast?.optString("code"),
                            "previousLastTimestamp" to previousLast?.optString("timestampUtc"),
                        ),
                    ),
                )
            }
        }
    }

    fun emit(
        source: String,
        level: String,
        category: String,
        event: String,
        outcome: String,
        code: String? = null,
        message: String? = null,
        gameSessionId: String? = null,
        operationId: String? = null,
        durationMs: Long? = null,
        context: Map<String, Any?>? = null,
        error: Throwable? = null,
    ) {
        val value = mutableMapOf<String, Any?>(
            "source" to source,
            "level" to level,
            "category" to category,
            "event" to event,
            "outcome" to outcome,
        )
        if (code != null) value["code"] = code
        if (message != null) value["message"] = message
        if (gameSessionId != null) value["gameSessionId"] = gameSessionId
        if (operationId != null) value["operationId"] = operationId
        if (durationMs != null) value["durationMs"] = durationMs
        if (context != null) value["context"] = context
        if (error != null) {
            value["error"] = mapOf(
                "type" to error.javaClass.simpleName,
                "message" to (error.message ?: error.toString()),
                "stackTrace" to error.stackTraceToString(),
            )
        }
        emit(value)
    }

    fun emit(input: Map<String, Any?>) {
        if (!initialized) return
        val level = normalizedLevel(input["level"]?.toString())
        val task = LogTask(level, input)
        try {
            executor.execute(task)
        } catch (_: Exception) {
            if (level == "ERROR" || level == "FATAL") {
                val removable = executor.queue.firstOrNull {
                    it is LogTask && it.level != "ERROR" && it.level != "FATAL"
                }
                if (removable != null && executor.queue.remove(removable)) {
                    incrementDropped((removable as LogTask).level)
                    runCatching { executor.execute(task) }
                        .onFailure { incrementDropped(level) }
                } else {
                    incrementDropped(level)
                }
            } else {
                incrementDropped(level)
            }
        }
    }

    fun flush(timeoutMs: Long): Boolean {
        if (!initialized) return false
        val latch = CountDownLatch(1)
        return try {
            executor.execute {
                synchronized(lock) { runCatching { writer?.flush() }.onFailure { degrade() } }
                latch.countDown()
            }
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (_: Exception) {
            false
        }
    }

    fun endSession() {
        emit(
            source = "android",
            level = "INFO",
            category = "app.lifecycle",
            event = "app_session_ended",
            outcome = "succeeded",
        )
        flush(500)
        synchronized(lock) {
            runCatching { writer?.close() }
            writer = null
            if (markerFile.exists()) markerFile.delete()
        }
    }

    private fun snapshot(limit: Int): Map<String, Any?> = synchronized(lock) {
        val count = limit.coerceIn(1, recentCapacity)
        mapOf(
            "appSessionId" to appSessionId,
            "persisting" to !degraded,
            "degraded" to degraded,
            "logDirectory" to logsDirectory.path,
            "totalBytes" to (logsDirectory.listFiles()?.sumOf { it.length() } ?: 0L),
            "writeFailureCount" to writeFailureCount.get(),
            "droppedByLevel" to dropped.toMap(),
            "events" to recent.takeLast(count),
        )
    }

    private fun deleteHistory() {
        flush(500)
        synchronized(lock) {
            val currentPrefix = "app-$appSessionId-"
            logsDirectory.listFiles()
                ?.filter { it.name.endsWith(".jsonl") && !it.name.startsWith(currentPrefix) }
                ?.forEach { runCatching { it.delete() } }
        }
    }

    private class LogTask(val level: String, private val input: Map<String, Any?>) : Runnable {
        override fun run() {
            synchronized(lock) { emitImmediate(input.toMutableMap()) }
        }
    }

    private fun emitImmediate(value: MutableMap<String, Any?>) {
        sequence += 1
        val normalized = linkedMapOf<String, Any?>(
            "schemaVersion" to 1,
            "timestampUtc" to Instant.now().toString(),
            "monotonicMs" to (SystemClock.elapsedRealtime() - monotonicOriginMs),
            "sequence" to sequence,
            "level" to normalizedLevel(value["level"]?.toString()),
            "source" to sanitizeIdentifier(value["source"]?.toString(), "android"),
            "category" to sanitizeIdentifier(value["category"]?.toString(), "unknown"),
            "event" to sanitizeIdentifier(value["event"]?.toString(), "unknown_event"),
            "outcome" to sanitizeIdentifier(value["outcome"]?.toString(), "observed"),
            "appSessionId" to appSessionId,
        )
        copyOptional(value, normalized, "code")
        copyOptional(value, normalized, "message", 2048)
        copyOptional(value, normalized, "gameSessionId")
        copyOptional(value, normalized, "operationId")
        if (value["durationMs"] is Number) normalized["durationMs"] = (value["durationMs"] as Number).toLong()
        sanitizeMap(value["context"] as? Map<*, *>)?.let { normalized["context"] = it }
        sanitizeMap(value["error"] as? Map<*, *>)?.let { normalized["error"] = it }

        var line = JSONObject(normalized).toString()
        if (line.toByteArray(StandardCharsets.UTF_8).size > 16 * 1024) {
            normalized.remove("context")
            normalized["message"] = "Log event exceeded 16 KB and was truncated"
            line = JSONObject(normalized).toString()
        }
        val recentValue = jsonObjectToMap(JSONObject(line))
        recent.addLast(recentValue)
        while (recent.size > recentCapacity) recent.removeFirst()
        if (degraded) return
        runCatching {
            ensureWriter(line.toByteArray(StandardCharsets.UTF_8).size + 1)
            writer?.apply {
                write(line)
                newLine()
                if (normalized["level"] == "ERROR" || normalized["level"] == "FATAL") flush()
            }
        }.onFailure { degrade() }
    }

    private fun ensureWriter(nextBytes: Int) {
        val file = currentFile
        if (writer == null || file == null || file.length() + nextBytes > segmentSizeBytes) {
            writer?.flush()
            writer?.close()
            val target = File(logsDirectory, "app-$appSessionId-${segment.toString().padStart(3, '0')}.jsonl")
            segment += 1
            currentFile = target
            writer = BufferedWriter(OutputStreamWriter(FileOutputStream(target, true), StandardCharsets.UTF_8))
        }
    }

    private fun cleanupLocked() {
        val files = logsDirectory.listFiles()?.filter { it.name.endsWith(".jsonl") } ?: return
        val cutoff = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(retentionDays)
        files.filter { it.lastModified() < cutoff }.forEach { it.delete() }
        val groups = logsDirectory.listFiles()
            ?.filter { it.name.endsWith(".jsonl") }
            ?.groupBy { it.name.replace(Regex("-\\d{3}\\.jsonl$"), "") }
            ?.entries
            ?.sortedByDescending { entry -> entry.value.maxOfOrNull { it.lastModified() } ?: 0L }
            ?: return
        groups.drop(completedSessionLimit).forEach { entry -> entry.value.forEach { it.delete() } }
        var remaining = logsDirectory.listFiles()?.filter { it.name.endsWith(".jsonl") }?.sortedBy { it.lastModified() } ?: emptyList()
        var total = remaining.sumOf { it.length() }
        for (file in remaining) {
            if (total <= totalSizeBytes) break
            total -= file.length()
            file.delete()
        }
    }

    private fun readPreviousSession(): String? = runCatching {
        if (!markerFile.exists()) null else JSONObject(markerFile.readText()).optString("appSessionId").ifBlank { null }
    }.getOrNull()

    private fun readLastEvent(sessionId: String): JSONObject? = runCatching {
        val file = logsDirectory.listFiles()
            ?.filter { it.name.startsWith("app-$sessionId-") && it.name.endsWith(".jsonl") }
            ?.maxByOrNull { it.name }
            ?: return@runCatching null
        val line = file.useLines { lines -> lines.filter { it.isNotBlank() }.lastOrNull() }
        line?.let(::JSONObject)
    }.getOrNull()

    private fun writeMarker() {
        runCatching {
            logsDirectory.mkdirs()
            val temporary = File(logsDirectory, "${markerFile.name}.tmp")
            temporary.writeText(JSONObject(mapOf("appSessionId" to appSessionId)).toString())
            if (!temporary.renameTo(markerFile)) error("Unable to commit session marker")
        }.onFailure { degrade() }
    }

    private fun degrade() {
        degraded = true
        writeFailureCount.incrementAndGet()
        runCatching { writer?.close() }
        writer = null
    }

    private fun incrementDropped(level: String) = synchronized(lock) {
        dropped[level] = (dropped[level] ?: 0) + 1
    }

    private fun normalizedLevel(value: String?): String {
        val level = value?.uppercase() ?: "INFO"
        return if (level in setOf("DEBUG", "INFO", "WARN", "ERROR", "FATAL")) level else "INFO"
    }

    private fun sanitizeIdentifier(value: String?, fallback: String): String {
        val candidate = value?.take(128) ?: fallback
        return if (candidate.matches(Regex("[A-Za-z0-9._-]+"))) candidate else fallback
    }

    private fun copyOptional(source: Map<String, Any?>, target: MutableMap<String, Any?>, key: String, limit: Int = 256) {
        val value = source[key] as? String ?: return
        target[key] = sanitizeText(value, limit)
    }

    private fun sanitizeMap(value: Map<*, *>?): Map<String, Any?>? {
        if (value == null) return null
        val forbidden = Regex("password|passwd|secret|token|authorization|cookie|api.?key|private.?key", RegexOption.IGNORE_CASE)
        return value.entries.take(32).mapNotNull { entry ->
            val key = entry.key?.toString()?.take(64) ?: return@mapNotNull null
            if (forbidden.containsMatchIn(key)) return@mapNotNull null
            val sanitized = when (val item = entry.value) {
                is String -> sanitizeText(item, 4096)
                is Number, is Boolean -> item
                else -> null
            } ?: return@mapNotNull null
            key to sanitized
        }.toMap()
    }

    private fun sanitizeText(value: String, limit: Int): String {
        var result = value
            .replace(Regex("(?i)(token|authorization|cookie|password|passwd|secret|apiKey)\\s*[:=]\\s*[^\\s,;]+")) {
                "${it.groupValues[1]}=<redacted>"
            }
            .replace(Regex("[A-Za-z]:\\\\Users\\\\[^\\\\\\s]+"), "<user-home>")
            .replace(Regex("/(Users|home)/[^/\\s]+"), "/<user-home>")
        if (result.length > limit) result = result.take(limit) + "...[truncated]"
        return result
    }

    private fun jsonObjectToMap(value: JSONObject): Map<String, Any?> = value.keys().asSequence().associateWith { key ->
        when (val item = value.get(key)) {
            JSONObject.NULL -> null
            is JSONObject -> jsonObjectToMap(item)
            is JSONArray -> (0 until item.length()).map { item.get(it) }
            else -> item
        }
    }

    private fun newSessionId(): String {
        val timestamp = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
            .withZone(ZoneOffset.UTC)
            .format(Instant.now())
        return "$timestamp-${UUID.randomUUID().toString().take(6)}"
    }

    @Suppress("DEPRECATION")
    private fun appVersion(context: Context): String = runCatching {
        context.packageManager
            .getPackageInfo(context.packageName, 0)
            .versionName
            ?: "unknown"
    }.getOrDefault("unknown")
}
