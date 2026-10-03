import Foundation
import GardendlessCore

/// Resolves Tauri-style paths from the GP-Next bridge while confining every
/// access to the `gp-next` sandbox root.
public final class GpNextPathResolver {
  private let gpNextRoot: URL

  public init(gpNextRoot: URL) throws {
    let values = try gpNextRoot.resourceValues(
      forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
    )
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw GameError.failed(
        .gpNextForbidden,
        "GP-Next 根目录不能是符号链接"
      )
    }
    self.gpNextRoot = gpNextRoot.standardizedFileURL
  }

  public func resolve(_ value: Any?, options: [String: Any]) throws -> URL {
    guard let value = value as? String else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 文件路径为空")
    }
    var raw = value.trimmingCharacters(in: .whitespaces)
    guard !raw.isEmpty else {
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
    let components = raw.split(separator: "/").map(String.init)
    guard !components.contains("."), !components.contains("..") else {
      throw GameError.failed(
        .gpNextForbidden,
        "GP-Next 路径超出 Loader 沙箱"
      )
    }
    guard let namespaceIndex = components.firstIndex(of: "gp-next"),
          raw.hasPrefix("/") || namespaceIndex == components.startIndex else {
      throw GameError.failed(
        .gpNextForbidden,
        "GP-Next 路径超出 Loader 沙箱"
      )
    }
    let candidate = components[components.index(after: namespaceIndex)...]
      .reduce(gpNextRoot) { result, component in
        result.appendingPathComponent(component)
      }
      .standardizedFileURL
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
