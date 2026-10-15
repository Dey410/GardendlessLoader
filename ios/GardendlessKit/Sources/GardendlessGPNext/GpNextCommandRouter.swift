import Foundation
import GardendlessCore

public enum GpNextAction {
  case value(Any)
  case exportFile(URL)
  case openURL(URL)
  case importPackages
  case openSelection(directory: Bool)
}

public final class GpNextCommandRouter {
  private let fileSystem: GpNextFileSystem
  private let allowedRemoteHosts: Set<String>
  private let exportTemporaryRoot: URL
  private var pendingExports = Set<URL>()

  public init(
    session: GameSession,
    fileSystem: GpNextFileSystem? = nil
  ) throws {
    self.fileSystem = try fileSystem ?? GpNextFileSystem(session: session)
    self.allowedRemoteHosts = session.allowedRemoteHosts
    self.exportTemporaryRoot = session.exportTemporaryRoot
    try FileManager.default.createDirectory(
      at: exportTemporaryRoot,
      withIntermediateDirectories: true
    )
  }

  public func dispatch(_ request: [String: Any]) throws -> GpNextAction {
    let command = request["command"] as? String ?? ""
    let args = request["args"] as? [String: Any] ?? [:]
    let options = request["options"] as? [String: Any] ?? [:]
    let nested = args["options"] as? [String: Any] ?? options

    switch command {
    case "plugin:fs|mkdir":
      try fileSystem.mkdir(
        path: try string(args, "path"),
        options: nested
      )
      return .value(NSNull())
    case "plugin:fs|read_dir":
      return .value(
        try fileSystem.readDirectory(
          path: try string(args, "path"),
          options: nested
        )
      )
    case "plugin:fs|lstat":
      return .value(
        try fileSystem.lstat(
          path: try string(args, "path"),
          options: nested
        )
      )
    case "plugin:fs|exists":
      return .value(
        try fileSystem.exists(
          path: try string(args, "path"),
          options: nested
        )
      )
    case "plugin:fs|remove":
      try fileSystem.remove(
        path: try string(args, "path"),
        options: nested
      )
      return .value(NSNull())
    case "plugin:fs|rename":
      try fileSystem.rename(
        oldPath: try string(args, "oldPath"),
        newPath: try string(args, "newPath"),
        options: nested
      )
      return .value(NSNull())
    case "plugin:dialog|open":
      let dialogOptions = args["options"] as? [String: Any] ?? [:]
      if dialogOptions["multiple"] as? Bool == true {
        throw GameError.failed(
          .gpNextForbidden,
          "GP-Next 仅支持选择一个 Mod 包"
        )
      }
      return .openSelection(
        directory: dialogOptions["directory"] as? Bool == true
      )
    case "plugin:dialog|save":
      let options = args["options"] as? [String: Any]
      let requested = options?["defaultPath"] as? String
        ?? "gardendless-export.json"
      let name = safeFileName(requested)
      let requestedPath = exportTemporaryRoot.appendingPathComponent(name)
      // An earlier session may still be closing its picker. Keep its cleanup
      // destination separate from the next saved file.
      let path = FileManager.default.fileExists(atPath: requestedPath.path)
        || pendingExports.contains(requestedPath)
        ? exportTemporaryRoot.appendingPathComponent("\(UUID().uuidString.prefix(8))-\(name)")
        : requestedPath
      guard pendingExports.count < 8 else {
        throw GameError.failed(.exportInProgress, "Too many pending save destinations")
      }
      pendingExports.insert(path)
      return .value(path.path)
    case "plugin:opener|open_url":
      guard let raw = args["url"] as? String,
            let url = URL(string: raw),
            url.scheme == "https" || url.scheme == "http",
            let host = url.host?.lowercased(),
            allowedRemoteHosts.contains(where: {
              host == $0 || host.hasSuffix(".\($0)")
            }) else {
        throw GameError.failed(
          .gpNextForbidden,
          "GP-Next 请求打开了未授权网址"
        )
      }
      return .openURL(url)
    case "plugin:opener|open_path":
      return .importPackages
    default:
      throw GameError.failed(.gpNextUnavailable, "未兼容的 GP-Next 命令：\(command)")
    }
  }

  private func string(_ args: [String: Any], _ key: String) throws -> String {
    guard let value = args[key] as? String else {
      throw GameError.failed(.gpNextForbidden, "\(key) 缺失")
    }
    return value
  }

  private func safeFileName(_ value: String) -> String {
    let base = value
      .replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/")
      .last
      .map(String.init) ?? ""
    let invalid = CharacterSet(charactersIn: ":*?\"<>|").union(.controlCharacters)
    let cleaned = base.unicodeScalars.map {
      invalid.contains($0) ? "_" : String($0)
    }
    .joined()
    return cleaned.isEmpty || cleaned == "." || cleaned == ".."
      ? "gardendless-export.json"
      : cleaned
  }

  public func resolveReadPath(path: String, options: [String: Any]) throws -> URL {
    try fileSystem.resolveReadPath(path: path, options: options)
  }

  public func resolveWritePath(path: String?, options: [String: Any]) throws -> URL {
    try fileSystem.resolveWritePath(rawPath: path, options: options)
  }

  public func consumePendingExport(_ path: URL) -> Bool {
    pendingExports.remove(path) != nil
  }
}
