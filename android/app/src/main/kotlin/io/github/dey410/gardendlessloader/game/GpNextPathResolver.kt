package io.github.dey410.gardendlessloader.game

import java.io.File

internal fun resolveGpNextSandboxPath(root: File, rawValue: String): File {
    val normalizedRoot = root.absoluteFile
    val normalizedRaw = rawValue
        .trim()
        .removePrefix("file://")
        .replace('\\', '/')
    val parts = normalizedRaw.split('/').filter { it.isNotEmpty() }
    require(parts.none { it == "." || it == ".." }) {
        "GP-Next 路径超出 Loader 沙箱"
    }
    val namespaceIndex = parts.indexOf("gp-next")
    require(namespaceIndex >= 0 && (normalizedRaw.startsWith('/') || namespaceIndex == 0)) {
        "GP-Next 路径超出 Loader 沙箱"
    }
    return parts.drop(namespaceIndex + 1)
        .fold(normalizedRoot) { path, part -> File(path, part) }
        .absoluteFile
}
