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
    resolver = try GpNextPathResolver(gpNextRoot: root)
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

  public func resolveReadPath(path: String, options: [String: Any]) throws -> URL {
    let url = try resolver.resolve(path, options: options)
    try resolver.assertNoSymlink(url)
    let values = try url.resourceValues(forKeys: [.isRegularFileKey])
    guard values.isRegularFile == true else {
      throw GameError.failed(.gpNextForbidden, "GP-Next path is not a regular file")
    }
    return url
  }

  public func lstat(
    path: String,
    options: [String: Any]
  ) throws -> [String: Any] {
    let url = try resolver.resolve(path, options: options)
    try resolver.assertNoSymlink(url)
    let values = try url.resourceValues(
      forKeys: [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .isWritableKey,
      ]
    )
    return [
      "isFile": values.isRegularFile == true,
      "isDirectory": values.isDirectory == true,
      "isSymlink": values.isSymbolicLink == true,
      "size": values.fileSize ?? 0,
      "mtime": NSNull(),
      "atime": NSNull(),
      "birthtime": NSNull(),
      "readonly": values.isWritable == false,
      "fileAttributes": NSNull(),
      "dev": 0,
      "ino": 0,
      "mode": 0,
      "nlink": 0,
      "uid": 0,
      "gid": 0,
      "rdev": 0,
      "blksize": 0,
      "blocks": 0,
    ]
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

  public func rename(
    oldPath: String,
    newPath: String,
    options: [String: Any]
  ) throws {
    let oldOptions = baseDirectoryOptions(options["oldPathBaseDir"])
    let newOptions = baseDirectoryOptions(options["newPathBaseDir"])
    let source = try resolver.resolve(oldPath, options: oldOptions)
    let destination = try resolver.resolve(newPath, options: newOptions)
    try resolver.assertNoSymlink(source)
    try resolver.assertNoSymlink(destination)
    guard source != gpNextRoot else {
      throw GameError.failed(.gpNextForbidden, "不允许移动 GP-Next 根目录")
    }
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw GameError.failed(.gpNextForbidden, "源路径不存在：\(source.path)")
    }
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw GameError.failed(.gpNextForbidden, "目标路径已存在：\(destination.path)")
    }
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.moveItem(at: source, to: destination)
  }

  public func resolveWritePath(
    rawPath: String?,
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
      headerOptions = options
    }
    let resolvedPath = (headers["path"] as? String)?.removingPercentEncoding
      ?? rawPath
    guard let resolvedPath, !resolvedPath.isEmpty else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 写入路径为空")
    }
    let url = try resolver.resolve(resolvedPath, options: headerOptions)
    guard url != gpNextRoot else {
      throw GameError.failed(.gpNextForbidden, "Cannot write the GP-Next root")
    }
    try resolver.assertNoSymlink(url)
    if FileManager.default.fileExists(atPath: url.path) {
      guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
        throw GameError.failed(.gpNextForbidden, "Write destination is not a regular file")
      }
    }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try resolver.assertNoSymlink(url)
    return url
  }

  private func baseDirectoryOptions(_ value: Any?) -> [String: Any] {
    value.map { ["baseDir": $0] } ?? [:]
  }
}
