package io.github.dey410.gardendlessloader.game

import java.io.File
import java.io.RandomAccessFile
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

object GpNextPackArchiveNormalizer {
    fun prepare(source: File, directory: File, displayName: String): File {
        requireSafeCentralDirectory(source, displayName)
        return ZipFile(source).use { zip ->
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
    }

    private fun requireSafeCentralDirectory(source: File, displayName: String) {
        RandomAccessFile(source, "r").use { archive ->
            val size = archive.length()
            require(size >= 22) { "$displayName 不是有效的 ZIP" }
            val tailLength = minOf(size, 65_557L).toInt()
            val tail = ByteArray(tailLength)
            archive.seek(size - tailLength)
            archive.readFully(tail)
            val eocd = (tail.size - 22 downTo 0).firstOrNull { offset ->
                uint32LE(tail, offset) == 0x06054b50L &&
                    offset + 22 + uint16LE(tail, offset + 20) == tail.size
            } ?: throw IllegalArgumentException("$displayName 不是有效的 ZIP")
            val entryCount = uint16LE(tail, eocd + 10)
            val centralSize = uint32LE(tail, eocd + 12)
            val centralOffset = uint32LE(tail, eocd + 16)
            require(
                entryCount != 0xffff &&
                    centralSize != 0xffffffffL &&
                    centralOffset != 0xffffffffL,
            ) {
                "暂不支持 ZIP64 格式"
            }

            archive.seek(centralOffset)
            repeat(entryCount) {
                val header = ByteArray(46)
                archive.readFully(header)
                require(uint32LE(header, 0) == 0x02014b50L) {
                    "$displayName 的 ZIP 中央目录无效"
                }
                require(uint16LE(header, 8) and 0x0001 == 0) {
                    "$displayName 已加密，无法导入"
                }
                val externalAttributes = uint32LE(header, 38)
                val unixType = ((externalAttributes ushr 16).toInt() and 0xf000)
                require(unixType != 0xa000) { "$displayName 包含不支持的符号链接" }
                val nameLength = uint16LE(header, 28)
                val extraLength = uint16LE(header, 30)
                val commentLength = uint16LE(header, 32)
                archive.seek(archive.filePointer + nameLength + extraLength + commentLength)
            }
        }
    }

    private fun uint16LE(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8)

    private fun uint32LE(bytes: ByteArray, offset: Int): Long =
        (bytes[offset].toLong() and 0xff) or
            ((bytes[offset + 1].toLong() and 0xff) shl 8) or
            ((bytes[offset + 2].toLong() and 0xff) shl 16) or
            ((bytes[offset + 3].toLong() and 0xff) shl 24)

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
