package io.github.dey410.gardendlessloader.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.RandomAccessFile
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

class GpNextPackArchiveNormalizerTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `normalizes one wrapper directory and drops metadata artifacts`() {
        val source = temporaryFolder.newFile("wrapped.zip")
        writeZip(
            source,
            mapOf(
                "Amber 2.0/pack.json" to "{\"name\":\"Amber\"}",
                "Amber 2.0/jsons/config/patching.json" to "{\"defaultMode\":\"merge\"}",
                "Amber 2.0/jsons/.DS_Store" to "junk",
                "__MACOSX/._Amber 2.0" to "junk",
            ),
        )

        val prepared = GpNextPackArchiveNormalizer.prepare(
            source,
            temporaryFolder.root,
            "wrapped.zip",
        )

        assertNotEquals(source, prepared)
        ZipFile(prepared).use { zip ->
            val names = zip.entries().asSequence().map { it.name }.sorted().toList()
            assertEquals(listOf("jsons/config/patching.json", "pack.json"), names)
            assertEquals(
                "{\"name\":\"Amber\"}",
                zip.getInputStream(zip.getEntry("pack.json")).bufferedReader().readText(),
            )
        }
    }

    @Test
    fun `keeps an existing root pack unchanged`() {
        val source = temporaryFolder.newFile("root.zip")
        writeZip(source, mapOf("pack.json" to "{}", "mod.js" to "export{}"))

        val prepared = GpNextPackArchiveNormalizer.prepare(
            source,
            temporaryFolder.root,
            "root.zip",
        )

        assertSame(source, prepared)
    }

    @Test
    fun `rejects ambiguous wrapper directories`() {
        val source = temporaryFolder.newFile("ambiguous.zip")
        writeZip(
            source,
            mapOf(
                "Amber/pack.json" to "{}",
                "Other/readme.txt" to "other",
            ),
        )

        assertThrows(IllegalArgumentException::class.java) {
            GpNextPackArchiveNormalizer.prepare(
                source,
                temporaryFolder.root,
                "ambiguous.zip",
            )
        }
    }

    @Test
    fun `rejects unsafe archive paths`() {
        val unsafe = temporaryFolder.newFile("unsafe.zip")
        writeZip(
            unsafe,
            mapOf(
                "Amber/pack.json" to "{}",
                "Amber/../outside.json" to "{}",
            ),
        )
        assertThrows(IllegalArgumentException::class.java) {
            GpNextPackArchiveNormalizer.prepare(
                unsafe,
                temporaryFolder.root,
                "unsafe.zip",
            )
        }
    }

    @Test
    fun `rejects paths that collide after normalization`() {
        val duplicate = temporaryFolder.newFile("duplicate.zip")
        writeZip(
            duplicate,
            mapOf(
                "Amber/pack.json" to "{}",
                "Amber/jsons/a.json" to "{}",
                "Amber/jsons/./a.json" to "{}",
            ),
        )
        assertThrows(IllegalArgumentException::class.java) {
            GpNextPackArchiveNormalizer.prepare(
                duplicate,
                temporaryFolder.root,
                "duplicate.zip",
            )
        }
    }

    @Test
    fun `rejects symbolic link entries`() {
        val source = temporaryFolder.newFile("symlink.zip")
        writeZip(source, mapOf("pack.json" to "../../outside"))
        markFirstEntryAsSymbolicLink(source)

        assertThrows(IllegalArgumentException::class.java) {
            GpNextPackArchiveNormalizer.prepare(
                source,
                temporaryFolder.root,
                "symlink.zip",
            )
        }
    }

    private fun writeZip(file: File, entries: Map<String, String>) {
        ZipOutputStream(file.outputStream().buffered()).use { output ->
            for ((name, value) in entries) {
                output.putNextEntry(ZipEntry(name))
                output.write(value.toByteArray())
                output.closeEntry()
            }
        }
    }

    private fun markFirstEntryAsSymbolicLink(file: File) {
        RandomAccessFile(file, "rw").use { archive ->
            val bytes = ByteArray(archive.length().toInt())
            archive.readFully(bytes)
            val central = bytes.indices.first { index ->
                index + 4 <= bytes.size &&
                    (bytes[index].toInt() and 0xff) == 0x50 &&
                    (bytes[index + 1].toInt() and 0xff) == 0x4b &&
                    (bytes[index + 2].toInt() and 0xff) == 0x01 &&
                    (bytes[index + 3].toInt() and 0xff) == 0x02
            }
            val attributes = 0xa000 shl 16
            archive.seek((central + 38).toLong())
            archive.write(
                byteArrayOf(
                    attributes.toByte(),
                    (attributes ushr 8).toByte(),
                    (attributes ushr 16).toByte(),
                    (attributes ushr 24).toByte(),
                ),
            )
        }
    }
}
