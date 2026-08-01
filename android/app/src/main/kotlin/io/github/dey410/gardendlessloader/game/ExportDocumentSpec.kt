package io.github.dey410.gardendlessloader.game

import java.util.Locale

internal object ExportDocumentSpec {
    const val OPAQUE_MIME_TYPE = "application/vnd.gardendless.export"

    fun resolveMimeType(
        fileName: String,
        declaredMimeType: String,
        mimeTypeForExtension: (String) -> String?,
    ): String {
        // DocumentsUI can append the MIME type's canonical extension when it
        // conflicts with the suggested name, so the name owns this decision.
        val extension = fileExtension(fileName)
        if (extension != null) {
            val mappedMimeType = normalizeMimeType(mimeTypeForExtension(extension).orEmpty())
            if (mappedMimeType.isConcrete() && mappedMimeType != "application/octet-stream") {
                return mappedMimeType
            }
            return OPAQUE_MIME_TYPE
        }

        val declared = normalizeMimeType(declaredMimeType)
        return declared.takeIf {
            it.isConcrete() && it != "text/plain" && it != "application/octet-stream"
        } ?: OPAQUE_MIME_TYPE
    }

    private fun fileExtension(fileName: String): String? {
        val dot = fileName.lastIndexOf('.')
        if (dot <= 0 || dot == fileName.lastIndex) return null
        return fileName.substring(dot + 1).lowercase(Locale.US)
    }

    private fun normalizeMimeType(value: String): String =
        value.substringBefore(';').trim().lowercase(Locale.US)

    private fun String.isConcrete(): Boolean {
        val separator = indexOf('/')
        return separator > 0 && separator < lastIndex && this != "*/*"
    }
}
