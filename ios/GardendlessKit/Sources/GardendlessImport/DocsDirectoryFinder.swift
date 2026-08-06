import Foundation
import GardendlessCore

public enum DocsDirectoryFinder {
  public static func find(in entries: [ZipEntry]) throws -> String? {
    var filePaths = Set<String>()
    var directoryPaths = Set<String>()

    for entry in entries {
      if entry.isSymbolicLink {
        throw GameError.failed(.zipSymbolicLink, "选择的 ZIP 包含不支持的符号链接")
      }
      let archivePath = try safeArchivePath(entry.name)
      if entry.isDirectory {
        directoryPaths.insert(archivePath)
      } else {
        filePaths.insert(archivePath)
      }
    }

    var candidates = Set<String>()
    for path in filePaths where basename(path).lowercased() == "index.html" {
      candidates.insert(dirname(path))
    }

    return candidates.filter { candidate in
      func candidatePath(_ relativePath: String) -> String {
        candidate.isEmpty ? relativePath : "\(candidate)/\(relativePath)"
      }
      func hasFile(_ relativePath: String) -> Bool {
        filePaths.contains(candidatePath(relativePath))
      }
      func hasDirectory(_ relativePath: String) -> Bool {
        let path = candidatePath(relativePath)
        return directoryPaths.contains(path)
          || filePaths.contains { $0.hasPrefix("\(path)/") }
      }
      return hasFile("index.html")
        && hasFile("src/settings.json")
        && hasFile("src/import-map.json")
        && hasDirectory("assets")
        && hasDirectory("cocos-js")
        && hasDirectory("src")
    }
    .sorted { first, second in
      let firstIsDocs = basename(first) == "docs"
      let secondIsDocs = basename(second) == "docs"
      if firstIsDocs != secondIsDocs {
        return firstIsDocs
      }
      return first.count < second.count
    }
    .first
  }

  public static func safeArchivePath(_ path: String) throws -> String {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    if normalized.hasPrefix("/") {
      throw GameError.failed(.zipPathUnsafe, "选择的 ZIP 包含不安全路径")
    }
    let parts = normalized
      .split(separator: "/", omittingEmptySubsequences: false)
      .compactMap { part -> String? in
        let value = String(part)
        return value.isEmpty || value == "." ? nil : value
      }
    if parts.isEmpty || parts.contains("..") {
      throw GameError.failed(.zipPathUnsafe, "选择的 ZIP 包含不安全路径")
    }
    return parts.joined(separator: "/")
  }

  public static func isWithinArchivePrefix(_ path: String, prefix: String) -> Bool {
    prefix.isEmpty || path == prefix || path.hasPrefix("\(prefix)/")
  }

  private static func basename(_ path: String) -> String {
    path.split(separator: "/").last.map(String.init) ?? path
  }

  private static func dirname(_ path: String) -> String {
    guard let index = path.lastIndex(of: "/") else { return "" }
    return String(path[..<index])
  }
}
