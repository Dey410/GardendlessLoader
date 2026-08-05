import Foundation
import GardendlessCore

public final class GpNextFileSystem {
  private let resolver: GpNextPathResolver
  private let gpNextRoot: URL

  public init(session: GameSession) throws {
    let root = session.gpNextRoot
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("packs", isDirectory: true),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("patches", isDirectory: true),
      withIntermediateDirectories: true
    )
    resolver = try GpNextPathResolver(
      appRoot: session.appRoot,
      gpNextRoot: root
    )
    gpNextRoot = root.standardizedFileURL
  }

  public func mkdir(path: String, options: [String: Any]) throws {
    let url = try resolver.resolve(path, options: options)
    try resolver.assertNoSymlink(url)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
    try resolver.assertNoSymlink(url)
  }

  public func readDirectory(
    path: String,
    options: [String: Any]
  ) throws -> [[String: Any]] {
    let url = try resolver.resolve(path, options: options)
    try resolver.assertNoSymlink(url)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: url.path,
      isDirectory: &isDirectory
    ), isDirectory.boolValue else {
      throw GameError.failed(.gpNextForbidden, "目录不存在：\(url.path)")
    }
    return try FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
      ]
    )
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .map { child in
      let values = try child.resourceValues(
        forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
      )
      return [
        "name": child.lastPathComponent,
        "isFile": values.isRegularFile == true,
        "isDirectory": values.isDirectory == true,
        "isSymlink": values.isSymbolicLink == true,
      ]
    }
  }

  public func readFile(path: String, options: [String: Any]) throws -> [UInt8] {
    let url = try resolver.resolve(path, options: options)
    try resolver.assertNoSymlink(url)
    return Array(try Data(contentsOf: url))
  }

  public func exists(path: String, options: [String: Any]) throws -> Bool {
    let url = try resolver.resolve(path, options: options)
    return FileManager.default.fileExists(atPath: url.path)
  }

  public func remove(path: String, options: [String: Any]) throws {
    let url = try resolver.resolve(path, options: options)
    try resolver.assertNoSymlink(url)
    guard url != gpNextRoot else {
      throw GameError.failed(.gpNextForbidden, "不允许删除 GP-Next 根目录")
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: url.path,
      isDirectory: &isDirectory
    ) else {
      return
    }
    let recursive = options["recursive"] as? Bool ?? true
    if isDirectory.boolValue && !recursive {
      throw GameError.failed(.gpNextForbidden, "目录删除需要 recursive=true")
    }
    if isDirectory.boolValue {
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )
      while let child = enumerator?.nextObject() as? URL {
        if try child.resourceValues(forKeys: [.isSymbolicLinkKey])
          .isSymbolicLink == true {
          throw GameError.failed(.gpNextForbidden, "不允许操作符号链接")
        }
      }
    }
    try FileManager.default.removeItem(at: url)
  }

  public func writeFile(
    path: String,
    bytes: [UInt8],
    options: [String: Any]
  ) throws {
    let url = try resolver.resolve(path, options: options)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try resolver.assertNoSymlink(url)
    try Data(bytes).write(to: url, options: .atomic)
  }

  /// Mirrors the GP-Next bridge write shape: the effective path can arrive in
  /// `headers.path` (percent-encoded) with Tauri options carried in
  /// `headers.options` as an encoded JSON string.
  @discardableResult
  public func writeFileAndReturnPath(
    rawPath: String?,
    bytes: [NSNumber],
    options: [String: Any]
  ) throws -> URL {
    let headers = options["headers"] as? [String: Any] ?? [:]
    let headerOptions: [String: Any]
    if let raw = headers["options"] as? String,
       raw != "undefined",
       let data = raw.data(using: .utf8),
       let decoded = try? JSONSerialization.jsonObject(with: data)
         as? [String: Any] {
      headerOptions = decoded
    } else {
      headerOptions = [:]
    }
    let resolvedPath = (headers["path"] as? String)?.removingPercentEncoding
      ?? rawPath
    guard let resolvedPath, !resolvedPath.isEmpty else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 写入路径为空")
    }
    let url = try resolver.resolve(resolvedPath, options: headerOptions)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try resolver.assertNoSymlink(url)
    try Data(bytes.map { UInt8(truncating: $0) }).write(
      to: url,
      options: .atomic
    )
    return url
  }
}
