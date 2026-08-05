import Foundation

struct GameResourceProperties {
  let length: Int64
  let etag: String
}

enum GameAudioContainer: Equatable {
  case mp3
  case m4a
  case unsupported
}

final class GameResourceLocator {
  let root: URL

  init(root: URL) throws {
    let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw GameSessionError.invalid("Resource root is not a safe directory")
    }
    self.root = root.resolvingSymlinksInPath().standardizedFileURL
  }

  func relativePath(for url: URL) -> String? {
    guard url.scheme == "gardendless-game", url.host == "localhost",
          let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
          let decoded = encoded.removingPercentEncoding else { return nil }
    if decoded.range(of: "%(?:2e|2f|5c|25)", options: [.regularExpression, .caseInsensitive]) != nil {
      return nil
    }
    let path = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
    let effective = path.isEmpty ? "index.html" : path
    let components = effective.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
          !effective.contains("\\"), !effective.contains("\0") else { return nil }
    return components.joined(separator: "/")
  }

  func resolve(_ relativePath: String) -> URL? {
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
    var cursor = root
    for component in relativePath.split(separator: "/", omittingEmptySubsequences: false) {
      guard !component.isEmpty, component != ".", component != ".." else { return nil }
      cursor.appendPathComponent(String(component), isDirectory: false)
      if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
        return nil
      }
    }
    let resolved = cursor.resolvingSymlinksInPath().standardizedFileURL
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard resolved.path.hasPrefix(rootPath),
          (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
      return nil
    }
    return resolved
  }

  func fileProperties(_ file: URL) throws -> GameResourceProperties {
    let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let length = Int64(values.fileSize ?? 0)
    return GameResourceProperties(
      length: length,
      etag: "\"\(Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0))-\(length)\""
    )
  }

  func audioContainer(_ file: URL) throws -> GameAudioContainer {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 16) ?? Data()
    let brands = ["ftypM4A", "ftypisom", "ftypmp42"]
    if brands.contains(where: { data.range(of: Data($0.utf8)) != nil }) {
      return .m4a
    }
    let bytes = [UInt8](data)
    if data.starts(with: Data("ID3".utf8)) ||
        (bytes.count >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
      return .mp3
    }
    return .unsupported
  }
}
