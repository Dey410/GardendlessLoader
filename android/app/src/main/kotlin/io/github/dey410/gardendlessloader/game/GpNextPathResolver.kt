package io.github.dey410.gardendlessloader.game

import java.io.File

internal fun resolveGpNextSandboxPath(root: File, rawValue: String): File {
    val normalizedRoot = root.absoluteFile
    val normalizedRaw = rawValue.replace('\\', '/')
    val parts = normalizedRaw.split('/').filter { it.isNotEmpty() }
    require(parts.none { it == "." || it == ".." }) {
        "GP-Next 路径超出 Loader 沙箱"
    }
    val candidate = if (normalizedRaw.startsWith('/')) {
        File(normalizedRaw).absoluteFile
    } else {
        require(parts.firstOrNull() == "gp-next") { "GP-Next 路径超出 Loader 沙箱" }
        parts.drop(1).fold(normalizedRoot) { path, part -> File(path, part) }.absoluteFile
    }
    require(candidate.isInsideGpNextRoot(normalizedRoot)) {
        "GP-Next 路径超出 Loader 沙箱"
    }
    return candidate
}

private fun File.isInsideGpNextRoot(root: File): Boolean =
    path == root.path || path.startsWith(root.path + File.separator)
