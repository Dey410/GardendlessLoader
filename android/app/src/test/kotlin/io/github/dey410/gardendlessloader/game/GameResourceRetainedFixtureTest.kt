package io.github.dey410.gardendlessloader.game

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.nio.file.Files

// These fixtures are retained; no test lifecycle removes files or directories.
class GameResourceRetainedFixtureTest {
    @Test
    fun `native audio MIME matches m4a aac and legacy disguised containers`() {
        val directory = Files.createTempDirectory("gardendless-audio-mime-retained-").toFile()
        val mp4 = byteArrayOf(0, 0, 0, 28) + "ftypM4A ".toByteArray() + ByteArray(16)
        File(directory, "music.m4a").writeBytes(mp4)
        File(directory, "music.aac").writeBytes(byteArrayOf(0xff.toByte(), 0xf1.toByte(), 0, 0))
        File(directory, "legacy.mp3").writeBytes(mp4)
        File(directory, "adts.mp3").writeBytes(byteArrayOf(0xff.toByte(), 0xf1.toByte(), 0, 0))
        val resolver = GameResourceResolver(directory)
        for ((path, mime) in mapOf("music.m4a" to "audio/mp4", "music.aac" to "audio/aac",
            "legacy.mp3" to "audio/mp4", "adts.mp3" to "audio/aac")) {
            val response = resolver.resolve("https://appassets.androidplatform.net/$path", "HEAD")
            assertEquals(path, mime, response.mimeType)
            response.body.close()
        }
    }

    @Test
    fun `package metadata is never exposed through the game origin`() {
        val directory = Files.createTempDirectory("gardendless-resource-metadata-retained-").toFile()
        val metadata = File(directory, "__gardendless/package").apply { mkdirs() }
        File(metadata, "resource-manifest.json").writeText("{}")
        val resolver = GameResourceResolver(directory)
        for (path in listOf("__gardendless", "%5f%5fgardendless")) {
            val response = resolver.resolve("https://appassets.androidplatform.net/$path/package/resource-manifest.json", "GET")
            assertEquals(403, response.statusCode)
            response.body.close()
        }
    }

    @Test
    fun `matching conditional requests return an Android legal complete 200 response`() {
        val directory = Files.createTempDirectory("gardendless-resource-conditional-retained-").toFile()
        File(directory, "index.html").writeText("version-one")
        val resolver = GameResourceResolver(directory)
        val first = resolver.resolve("https://appassets.androidplatform.net/", "GET")
        first.body.close()
        val cached = resolver.resolve(
            "https://appassets.androidplatform.net/", "GET", mapOf("If-None-Match" to first.headers.getValue("ETag")),
        )
        assertEquals(200, cached.statusCode)
        assertEquals("11", cached.headers["Content-Length"])
        cached.body.use { assertEquals("version-one", it.readBytes().decodeToString()) }
    }

    @Test
    fun `conditional HEAD and ranges preserve their body and length contracts`() {
        val directory = Files.createTempDirectory("gardendless-resource-range-retained-").toFile()
        File(directory, "index.html").writeText("0123456789")
        val resolver = GameResourceResolver(directory)
        val first = resolver.resolve("https://appassets.androidplatform.net/", "HEAD")
        first.body.use { assertEquals(0, it.readBytes().size) }
        val headers = mapOf("If-None-Match" to first.headers.getValue("ETag"), "Range" to "bytes=2-5")
        val range = resolver.resolve("https://appassets.androidplatform.net/", "GET", headers)
        assertEquals(206, range.statusCode)
        assertEquals("bytes 2-5/10", range.headers["Content-Range"])
        range.body.use { assertEquals("2345", it.readBytes().decodeToString()) }
    }
}
