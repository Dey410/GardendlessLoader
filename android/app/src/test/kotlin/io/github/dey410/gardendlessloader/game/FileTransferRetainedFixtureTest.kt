package io.github.dey410.gardendlessloader.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.File
import java.io.RandomAccessFile
import java.nio.file.Files

// Fixtures deliberately remain on disk: this suite never performs cleanup.
class FileTransferRetainedFixtureTest {
    @Test
    fun `atomic replacement preserves an open reader's original version`() {
        val directory = Files.createTempDirectory("gardendless-file-version-retained-").toFile()
        val destination = File(directory, "save.bin").apply { writeText("old-version") }
        val temporary = File(directory, ".transaction").apply { writeText("new-version") }
        RandomAccessFile(destination, "r").use { reader ->
            val first = ByteArray(4)
            reader.readFully(first)
            commitFileTransfer(temporary, destination)
            val rest = ByteArray((reader.length() - 4).toInt())
            reader.readFully(rest)
            assertEquals("old-version", (first + rest).decodeToString())
        }
        assertEquals("new-version", destination.readText())
    }

    @Test
    fun `empty replacement creates an empty committed file`() {
        val directory = Files.createTempDirectory("gardendless-file-empty-retained-").toFile()
        val destination = File(directory, "save.bin").apply { writeText("old-version") }
        val temporary = File(directory, ".transaction").apply { createNewFile() }
        FileTransferCursor(0).requireComplete()
        commitFileTransfer(temporary, destination)
        assertEquals(0L, destination.length())
    }

    @Test
    fun `cross directory transaction is rejected without changing the destination`() {
        val directory = Files.createTempDirectory("gardendless-file-cross-retained-").toFile()
        val destination = File(directory, "save.bin").apply { writeText("old-version") }
        val child = File(directory, "child").apply { mkdir() }
        val temporary = File(child, ".transaction").apply { writeText("new-version") }
        assertThrows(IllegalArgumentException::class.java) { commitFileTransfer(temporary, destination) }
        assertEquals("old-version", destination.readText())
        assertEquals("new-version", temporary.readText())
    }
}
