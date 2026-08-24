package io.github.dey410.gardendlessloader.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
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

    private fun writeZip(file: File, entries: Map<String, String>) {
        ZipOutputStream(file.outputStream().buffered()).use { output ->
            for ((name, value) in entries) {
                output.putNextEntry(ZipEntry(name))
                output.write(value.toByteArray())
                output.closeEntry()
            }
        }
    }
}
