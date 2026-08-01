package io.github.dey410.gardendlessloader.game

import org.junit.Assert.assertEquals
import org.junit.Test

class ExportDocumentSpecTest {
    @Test
    fun `filename MIME replaces a conflicting plain text MIME`() {
        val result = ExportDocumentSpec.resolveMimeType(
            fileName = "save.json",
            declaredMimeType = "text/plain",
            mimeTypeForExtension = { extension ->
                if (extension == "json") "application/json" else null
            },
        )

        assertEquals("application/json", result)
    }

    @Test
    fun `custom extensions use an opaque Loader MIME`() {
        val result = ExportDocumentSpec.resolveMimeType(
            fileName = "save.garden",
            declaredMimeType = "text/plain",
            mimeTypeForExtension = { null },
        )

        assertEquals(ExportDocumentSpec.OPAQUE_MIME_TYPE, result)
    }

    @Test
    fun `extensionless text exports do not ask Android for txt files`() {
        val result = ExportDocumentSpec.resolveMimeType(
            fileName = "save",
            declaredMimeType = "text/plain; charset=utf-8",
            mimeTypeForExtension = { null },
        )

        assertEquals(ExportDocumentSpec.OPAQUE_MIME_TYPE, result)
    }

    @Test
    fun `extensionless concrete non-text MIME remains available to the picker`() {
        val result = ExportDocumentSpec.resolveMimeType(
            fileName = "cover",
            declaredMimeType = "image/png",
            mimeTypeForExtension = { null },
        )

        assertEquals("image/png", result)
    }

    @Test
    fun `generic platform extension mappings do not add bin suffixes`() {
        val result = ExportDocumentSpec.resolveMimeType(
            fileName = "save.dat",
            declaredMimeType = "application/octet-stream",
            mimeTypeForExtension = { "application/octet-stream" },
        )

        assertEquals(ExportDocumentSpec.OPAQUE_MIME_TYPE, result)
    }
}
