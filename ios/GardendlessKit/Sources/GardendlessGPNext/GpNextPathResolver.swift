import Foundation
import GardendlessCore

/// Resolves Tauri-style paths from the GP-Next bridge while confining every
/// access to the `gp-next` sandbox root.
public final class GpNextPathResolver {
  private let appRoot: URL
  private let gpNextRoot: URL

  public init(appRoot: URL, gpNextRoot: URL) throws {
    let values = try gpNextRoot.resourceValues(
      forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
    )
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw GameError.failed(
        .gpNextForbidden,
        "GP-Next 根目录不能是符号链接"
      )
    }
    self.appRoot = appRoot.standardizedFileURL
    self.gpNextRoot = gpNextRoot.standardizedFileURL
  }

  public func resolve(_ value: Any?, options: [String: Any]) throws -> URL {
    guard var raw = value as? String,
          !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 文件路径为空")
    }
    if let base = options["baseDir"] as? Int,
       base != GpNextConstants.appDataBaseDirectoryID {
      throw GameError.failed(.gpNextForbidden, "不允许访问 Tauri baseDir \(base)")
    }
    if raw.hasPrefix("file:") {
      raw = URL(string: raw)?.path ?? raw
    }
    raw = raw.replacingOccurrences(of: "\\", with: "/")
    let candidate = (
      raw.hasPrefix("/")
        ? URL(fileURLWithPath: raw)
        : appRoot.appendingPathComponent(raw)
    ).standardizedFileURL
    let rootPath = gpNextRoot.path
    guard candidate.path == rootPath
            || candidate.path.hasPrefix(rootPath + "/") else {
      throw GameError.failed(
        .gpNextForbidden,
        "GP-Next 路径超出 Loader 沙箱"
      )
    }
    try assertNoSymlink(candidate)
    return candidate
  }

  public func assertNoSymlink(_ target: URL) throws {
    if try gpNextRoot.resourceValues(forKeys: [.isSymbolicLinkKey])
      .isSymbolicLink == true {
      throw GameError.failed(
        .gpNextForbidden,
        "GP-Next 根目录不能是符号链接"
      )
    }
    let relative = target.standardizedFileURL.path.dropFirst(gpNextRoot.path.count)
    var current = gpNextRoot
    for component in relative.split(separator: "/") {
      current.appendPathComponent(String(component))
      guard FileManager.default.fileExists(atPath: current.path) else {
        return
      }
      if try current.resourceValues(forKeys: [.isSymbolicLinkKey])
        .isSymbolicLink == true {
        throw GameError.failed(.gpNextForbidden, "不允许通过符号链接访问文件")
      }
    }
  }
}
