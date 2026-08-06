import Foundation

/// Confines every resource path to one directory while rejecting traversal,
/// symbolic links, double encoding, and unsafe components.
public struct PathSandbox {
  public let root: URL

  public init(root: URL) throws {
    let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw GameError.failed(.invalidPath, "Resource root is not a safe directory")
    }
    self.root = root.resolvingSymlinksInPath().standardizedFileURL
  }

  public func relativePath(for url: URL) -> String? {
    guard url.scheme == GameOrigin.scheme, url.host == GameOrigin.host,
          let encoded = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
          )?.percentEncodedPath,
          let decoded = encoded.removingPercentEncoding else {
      return nil
    }
    if decoded.range(
      of: "%(?:2e|2f|5c|25)",
      options: [.regularExpression, .caseInsensitive]
    ) != nil {
      return nil
    }
    let path = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
    let effective = path.isEmpty ? "index.html" : path
    let components = effective.split(
      separator: "/",
      omittingEmptySubsequences: false
    ).map(String.init)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
          !effective.contains("\\"),
          !effective.contains("\0") else {
      return nil
    }
    return components.joined(separator: "/")
  }

  public func resolve(_ relativePath: String) -> URL? {
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
    var cursor = root
    for component in relativePath.split(
      separator: "/",
      omittingEmptySubsequences: false
    ) {
      guard !component.isEmpty, component != ".", component != ".." else {
        return nil
      }
      cursor.appendPathComponent(String(component), isDirectory: false)
      if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink)
        == true {
        return nil
      }
    }
    let resolved = cursor.resolvingSymlinksInPath().standardizedFileURL
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard resolved.path.hasPrefix(rootPath),
          (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile)
            == true else {
      return nil
    }
    return resolved
  }

  public func fileProperties(_ file: URL) throws -> (length: Int64, etag: String) {
    let values = try file.resourceValues(
      forKeys: [.fileSizeKey, .contentModificationDateKey]
    )
    let length = Int64(values.fileSize ?? 0)
    let modified = Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
    return (length, "\"\(modified)-\(length)\"")
  }
}
