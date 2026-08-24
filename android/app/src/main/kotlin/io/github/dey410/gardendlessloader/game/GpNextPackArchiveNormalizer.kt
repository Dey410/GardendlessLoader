package io.github.dey410.gardendlessloader.game

import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

object GpNextPackArchiveNormalizer {
    fun prepare(source: File, directory: File, displayName: String): File =
        ZipFile(source).use { zip ->
            val meaningful = zip.entries().asSequence().mapNotNull { entry ->
                val path = safeArchivePath(entry.name)
                if (isMetadataArtifact(path)) null else ArchiveEntry(entry, path)
            }.toList()

            if (meaningful.any { !it.entry.isDirectory && it.path == "pack.json" }) {
                return source
            }

            val candidates = meaningful.mapNotNull { item ->
                if (item.entry.isDirectory) return@mapNotNull null
                val parts = item.path.split('/')
                if (parts.size == 2 && parts[1] == "pack.json") parts[0] else null
            }.toSet()
            val wrapper = candidates.singleOrNull()
                ?: throw missingRootPack(displayName)
            val prefix = "$wrapper/"
            require(meaningful.all { it.path == wrapper || it.path.startsWith(prefix) }) {
                missingRootPackMessage(displayName)
            }

            val normalized = mutableListOf<ArchiveEntry>()
            val names = mutableSetOf<String>()
            for (item in meaningful) {
                if (!item.path.startsWith(prefix)) continue
                var name = item.path.removePrefix(prefix)
                if (name.isEmpty()) continue
                if (item.entry.isDirectory) name += "/"
                require(names.add(name)) { "$displayName 规范化后包含重复路径" }
                normalized.add(item.copy(path = name))
            }
            require(normalized.any { !it.entry.isDirectory && it.path == "pack.json" }) {
                missingRootPackMessage(displayName)
            }

            directory.mkdirs()
            val output = File(directory, ".$displayName.normalized-${System.nanoTime()}")
            try {
                ZipOutputStream(output.outputStream().buffered()).use { writer ->
                    for (item in normalized) {
                        val outputEntry = ZipEntry(item.path)
                        if (item.entry.time >= 0) outputEntry.time = item.entry.time
                        writer.putNextEntry(outputEntry)
                        if (!item.entry.isDirectory) {
                            zip.getInputStream(item.entry).use { input ->
                                input.copyTo(writer, 64 * 1024)
                            }
                        }
                        writer.closeEntry()
                    }
                }
                output
            } catch (error: Exception) {
                if (output.exists()) output.delete()
                throw error
            }
        }

    private fun safeArchivePath(value: String): String {
        val normalized = value.replace('\\', '/')
        require(!normalized.startsWith('/')) { "GP-Next ZIP 包含不安全路径" }
        val parts = normalized.split('/').filter { it.isNotEmpty() && it != "." }
        require(parts.isNotEmpty() && ".." !in parts) { "GP-Next ZIP 包含不安全路径" }
        return parts.joinToString("/")
    }

    private fun isMetadataArtifact(path: String): Boolean {
        val parts = path.split('/')
        return "__MACOSX" in parts || parts.last() == ".DS_Store"
    }

    private fun missingRootPack(displayName: String): IllegalArgumentException =
        IllegalArgumentException(missingRootPackMessage(displayName))

    private fun missingRootPackMessage(displayName: String): String =
        "$displayName 缺少根目录 pack.json，且未找到唯一的单层外壳目录"

    private data class ArchiveEntry(val entry: ZipEntry, val path: String)
}
