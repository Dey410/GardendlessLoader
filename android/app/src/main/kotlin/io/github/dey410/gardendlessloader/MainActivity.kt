package io.github.dey410.gardendlessloader

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val documentPickerChannel = "io.github.dey410.gardendlessloader/document_picker"
    private val pickDocsRequestCode = 4100

    private var pendingResult: MethodChannel.Result? = null
    private var pendingTargetDirectory: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            documentPickerChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDocsDirectory" -> pickDocsDirectory(call, result)
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickDocsRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingResult ?: return
        val targetDirectory = pendingTargetDirectory
        pendingResult = null
        pendingTargetDirectory = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val treeUri = data?.data
        if (treeUri == null || targetDirectory == null) {
            result.error("missing_directory", "Failed to read the selected docs directory", null)
            return
        }

        try {
            persistReadPermission(treeUri, data)
            val selectedDocumentUri = DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
            val docsUri = resolveDocsDirectory(treeUri, selectedDocumentUri)
            if (docsUri == null) {
                result.error(
                    "invalid_docs_directory",
                    "Select the docs directory, or a parent directory that contains docs",
                    null,
                )
                return
            }

            val safeTarget = requireAppPrivateTarget(targetDirectory)
            copyDocsDirectory(treeUri, docsUri, safeTarget)
            result.success(safeTarget.absolutePath)
        } catch (error: Exception) {
            result.error("copy_docs_failed", error.message ?: error.toString(), null)
        }
    }

    private fun pickDocsDirectory(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("picker_active", "A docs picker is already running", null)
            return
        }

        val targetPath = call.argument<String>("targetDirectory")
        if (targetPath.isNullOrBlank()) {
            result.error("missing_target_directory", "Missing app-private import directory", null)
            return
        }

        try {
            pendingTargetDirectory = requireAppPrivateTarget(File(targetPath))
            pendingResult = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }
            startActivityForResult(intent, pickDocsRequestCode)
        } catch (error: Exception) {
            pendingTargetDirectory = null
            pendingResult = null
            result.error("open_picker_failed", error.message ?: error.toString(), null)
        }
    }

    private fun persistReadPermission(treeUri: Uri, data: Intent) {
        val readFlag = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (readFlag == 0) {
            return
        }
        try {
            contentResolver.takePersistableUriPermission(treeUri, readFlag)
        } catch (_: SecurityException) {
            // Immediate import only needs the transient grant returned with this picker result.
        }
    }

    private fun resolveDocsDirectory(treeUri: Uri, selectedUri: Uri): Uri? {
        if (hasChildNamed(treeUri, selectedUri, "index.html", requireDirectory = false)) {
            return selectedUri
        }

        val nestedDocs = listChildren(treeUri, selectedUri).firstOrNull {
            it.name == "docs" && it.mimeType == Document.MIME_TYPE_DIR
        } ?: return null

        return if (hasChildNamed(treeUri, nestedDocs.uri, "index.html", requireDirectory = false)) {
            nestedDocs.uri
        } else {
            null
        }
    }

    private fun copyDocsDirectory(treeUri: Uri, sourceUri: Uri, targetDirectory: File) {
        if (targetDirectory.exists() && !targetDirectory.deleteRecursively()) {
            throw IllegalStateException(
                "Failed to clear import directory: ${targetDirectory.absolutePath}",
            )
        }
        if (!targetDirectory.mkdirs() && !targetDirectory.isDirectory) {
            throw IllegalStateException(
                "Failed to create import directory: ${targetDirectory.absolutePath}",
            )
        }

        copyChildren(treeUri, sourceUri, targetDirectory)
    }

    private fun copyChildren(treeUri: Uri, sourceUri: Uri, targetDirectory: File) {
        for (child in listChildren(treeUri, sourceUri)) {
            val childName = sanitizeFileName(child.name)
            val output = safeChild(targetDirectory, childName)
            if (child.mimeType == Document.MIME_TYPE_DIR) {
                if (!output.mkdirs() && !output.isDirectory) {
                    throw IllegalStateException("Failed to create directory: ${output.absolutePath}")
                }
                copyChildren(treeUri, child.uri, output)
            } else {
                output.parentFile?.mkdirs()
                contentResolver.openInputStream(child.uri).use { input ->
                    if (input == null) {
                        throw IllegalStateException("Failed to read file: ${child.name}")
                    }
                    FileOutputStream(output).use { outputStream ->
                        input.copyTo(outputStream)
                    }
                }
            }
        }
    }

    private fun hasChildNamed(
        treeUri: Uri,
        directoryUri: Uri,
        name: String,
        requireDirectory: Boolean,
    ): Boolean {
        return listChildren(treeUri, directoryUri).any {
            it.name == name && (!requireDirectory || it.mimeType == Document.MIME_TYPE_DIR)
        }
    }

    private fun listChildren(treeUri: Uri, directoryUri: Uri): List<DocumentChild> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getDocumentId(directoryUri),
        )
        val projection = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
        )
        val children = mutableListOf<DocumentChild>()
        val cursor: Cursor? = contentResolver.query(childrenUri, projection, null, null, null)
        cursor.use {
            if (it == null) {
                return children
            }
            val idColumn = it.getColumnIndexOrThrow(Document.COLUMN_DOCUMENT_ID)
            val nameColumn = it.getColumnIndexOrThrow(Document.COLUMN_DISPLAY_NAME)
            val mimeColumn = it.getColumnIndexOrThrow(Document.COLUMN_MIME_TYPE)
            while (it.moveToNext()) {
                val documentId = it.getString(idColumn)
                children.add(
                    DocumentChild(
                        uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId),
                        name = it.getString(nameColumn),
                        mimeType = it.getString(mimeColumn),
                    ),
                )
            }
        }
        return children
    }

    private fun requireAppPrivateTarget(targetDirectory: File): File {
        val target = targetDirectory.canonicalFile
        val allowedRoots = listOfNotNull(
            getExternalFilesDir(null),
            filesDir,
            cacheDir,
        ).map { it.canonicalFile }

        val isAllowed = allowedRoots.any { root ->
            target.path == root.path || target.path.startsWith(root.path + File.separator)
        }
        if (!isAllowed) {
            throw SecurityException(
                "Target directory is outside app-private storage: ${target.absolutePath}",
            )
        }
        return target
    }

    private fun safeChild(parent: File, childName: String): File {
        val child = File(parent, childName).canonicalFile
        val parentPath = parent.canonicalFile.path + File.separator
        if (!child.path.startsWith(parentPath)) {
            throw SecurityException("Invalid file name: $childName")
        }
        return child
    }

    private fun sanitizeFileName(name: String?): String {
        val sanitized = (name ?: "unnamed")
            .replace("/", "_")
            .replace("\\", "_")
            .trim()
        return if (sanitized.isEmpty() || sanitized == "." || sanitized == "..") {
            "unnamed"
        } else {
            sanitized
        }
    }

    private data class DocumentChild(
        val uri: Uri,
        val name: String?,
        val mimeType: String?,
    )
}
