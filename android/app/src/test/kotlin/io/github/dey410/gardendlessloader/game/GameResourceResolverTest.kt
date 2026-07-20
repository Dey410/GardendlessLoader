package io.github.dey410.gardendlessloader.game

import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class GameResourceResolverTest {
    private lateinit var root: File
    private lateinit var resolver: GameResourceResolver

    @Before
    fun setUp() {
        root = Files.createTempDirectory("gardendless-resource-").toFile()
        File(root, "index.html").writeText("index")
        File(root, "src").mkdirs()
        File(root, "src/settings.json").writeText("{}")
        File(root, "assets").mkdirs()
        File(root, "assets/chunk.1234abcd.js").writeText("0123456789")
        File(root, "assets/向日葵.png").writeBytes(byteArrayOf(1, 2, 3))
        resolver = GameResourceResolver(root)
    }

    @After
    fun tearDown() {
        root.walkBottomUp().forEach { it.delete() }
    }

    @Test
    fun `root maps to index and HEAD streams no body`() {
        val get = resolver.resolve("https://appassets.androidplatform.net/", "GET")
        assertEquals(200, get.statusCode)
        assertEquals("text/html", get.mimeType)
        assertEquals("index", get.body.readBytes().decodeToString())

        val head = resolver.resolve("https://appassets.androidplatform.net/", "HEAD")
        assertEquals("5", head.headers["Content-Length"])
        assertEquals(0, head.body.readBytes().size)
    }

    @Test
    fun `supports ranges etag and immutable cache`() {
        val url = "https://appassets.androidplatform.net/assets/chunk.1234abcd.js"
        val partial = resolver.resolve(url, "GET", mapOf("Range" to "bytes=2-5"))
        assertEquals(206, partial.statusCode)
        assertEquals("bytes 2-5/10", partial.headers["Content-Range"])
        assertEquals("2345", partial.body.readBytes().decodeToString())
        assertEquals("public, max-age=31536000, immutable", partial.headers["Cache-Control"])

        val cached = resolver.resolve(
            url,
            "GET",
            mapOf("If-None-Match" to partial.headers.getValue("ETag")),
        )
        assertEquals(304, cached.statusCode)
    }

    @Test
    fun `returns 416 for an unsatisfiable range and 405 for writes`() {
        val url = "https://appassets.androidplatform.net/index.html"
        assertEquals(416, resolver.resolve(url, "GET", mapOf("Range" to "bytes=99-100")).statusCode)
        assertEquals(405, resolver.resolve(url, "POST").statusCode)
        assertEquals(416, resolver.resolve(url, "GET", mapOf("Range" to "bytes=0-nope")).statusCode)
    }

    @Test
    fun `streams large files across concurrent range requests`() {
        val large = File(root, "assets/large.bin")
        val bytes = ByteArray(4 * 1024 * 1024) { (it % 251).toByte() }
        large.writeBytes(bytes)
        val executor = Executors.newFixedThreadPool(8)
        try {
            val futures = (0 until 32).map { index ->
                executor.submit<ByteArray> {
                    val start = (index * 4096).toLong()
                    resolver.resolve(
                        "https://appassets.androidplatform.net/assets/large.bin",
                        "GET",
                        mapOf("Range" to "bytes=$start-${start + 4095}"),
                    ).body.use { it.readBytes() }
                }
            }
            futures.forEachIndexed { index, future ->
                val start = index * 4096
                assertArrayEquals(bytes.copyOfRange(start, start + 4096), future.get(10, TimeUnit.SECONDS))
            }
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `decodes unicode paths`() {
        val response = resolver.resolve(
            "https://appassets.androidplatform.net/assets/%E5%90%91%E6%97%A5%E8%91%B5.png",
            "GET",
        )
        assertEquals(200, response.statusCode)
        assertArrayEquals(byteArrayOf(1, 2, 3), response.body.readBytes())
    }

    @Test
    fun `rejects traversal double encoding and foreign origins`() {
        assertEquals(
            403,
            resolver.resolve("https://appassets.androidplatform.net/%2e%2e/secret", "GET").statusCode,
        )
        assertEquals(
            403,
            resolver.resolve("https://appassets.androidplatform.net/%252e%252e/secret", "GET").statusCode,
        )
        assertEquals(403, resolver.resolve("https://example.com/index.html", "GET").statusCode)
    }

    @Test
    fun `rejects symbolic links`() {
        val outside = Files.createTempFile("gardendless-outside-", ".bin")
        try {
            Files.createSymbolicLink(File(root, "assets/link.bin").toPath(), outside)
            assertEquals(
                404,
                resolver.resolve(
                    "https://appassets.androidplatform.net/assets/link.bin",
                    "GET",
                ).statusCode,
            )
        } finally {
            Files.deleteIfExists(outside)
        }
    }

    @Test
    fun `rejects a symbolic link resource root`() {
        val parent = requireNotNull(root.parentFile)
        val linkedRoot = File(parent, "gardendless-linked-root-${System.nanoTime()}")
        try {
            Files.createSymbolicLink(linkedRoot.toPath(), root.toPath())
            runCatching { GameResourceResolver(linkedRoot) }
                .onSuccess { throw AssertionError("symbolic link root was accepted") }
        } finally {
            Files.deleteIfExists(linkedRoot.toPath())
        }
    }
}
