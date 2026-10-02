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
  private var pendingWrites: [String: PendingWrite] = [:]

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
    case "plugin:fs|read_file", "plugin:fs|read_text_file":
      return .value(
        try fileSystem.readFile(
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
    case "plugin:fs|write_file", "plugin:fs|write_text_file":
      let rawPath = (nested["headers"] as? [String: Any])?["path"] as? String
        ?? args["path"] as? String
      if let transfer = args["__gardendlessTransfer"] as? [String: Any] {
        let path = try writeChunk(
          rawPath: rawPath,
          args: args,
          options: nested,
          transfer: transfer
        )
        guard let path else { return .value(NSNull()) }
        if pendingExports.remove(path) != nil {
          return .exportFile(path)
        }
        return .value(NSNull())
      }
      guard let bytes = args["__gardendlessBytes"] as? [NSNumber] else {
        throw GameError.failed(
          .gpNextForbidden,
          "GP-Next 写入内容不是字节数组"
        )
      }
      let path = try fileSystem.writeFileAndReturnPath(
        rawPath: rawPath,
        bytes: bytes,
        options: nested
      )
      if pendingExports.remove(path) != nil {
        return .exportFile(path)
      }
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
      let path = exportTemporaryRoot.appendingPathComponent(
        safeFileName(requested)
      )
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

  private func writeChunk(
    rawPath: String?,
    args: [String: Any],
    options: [String: Any],
    transfer: [String: Any]
  ) throws -> URL? {
    guard let token = transfer["token"] as? String,
          token.range(
            of: #"^[A-Za-z0-9-]{1,96}$"#,
            options: .regularExpression
          ) != nil else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 分块写入 token 无效")
    }
    if transfer["abort"] as? Bool == true {
      clearPendingWrite(token)
      return nil
    }
    guard let bytes = args["__gardendlessBytes"] as? [NSNumber],
          bytes.count <= 96 * 1024,
          let index = transfer["index"] as? Int,
          let total = transfer["totalBytes"] as? Int,
          total >= 0,
          total <= 512 * 1024 * 1024 else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 写入分块无效")
    }
    let path = try fileSystem.resolveWritePath(
      rawPath: rawPath,
      options: options
    )
    let state: PendingWrite
    if index == 0 {
      guard pendingWrites[token] == nil else {
        throw GameError.failed(.gpNextForbidden, "GP-Next 分块写入已存在")
      }
      let temporary = path.deletingLastPathComponent().appendingPathComponent(
        ".gardendless-write-\(token)"
      )
      guard !FileManager.default.fileExists(atPath: temporary.path) else {
        throw GameError.failed(.gpNextForbidden, "GP-Next 分块临时文件已存在")
      }
      state = PendingWrite(path: path, temporary: temporary, expectedBytes: total)
      pendingWrites[token] = state
    } else if let existing = pendingWrites[token] {
      state = existing
    } else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 分块写入不存在")
    }
    guard state.path == path,
          state.nextIndex == index,
          state.expectedBytes == total else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 分块写入顺序无效")
    }
    let data = Data(bytes.map { UInt8(truncating: $0) })
    if index == 0 {
      try data.write(to: state.temporary, options: .atomic)
    } else {
      let handle = try FileHandle(forWritingTo: state.temporary)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
    }
    state.written += data.count
    state.nextIndex += 1
    guard state.written <= state.expectedBytes else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 分块写入超出声明大小")
    }
    guard transfer["final"] as? Bool == true else { return nil }
    guard state.written == state.expectedBytes else {
      throw GameError.failed(.gpNextForbidden, "GP-Next 分块写入不完整")
    }
    pendingWrites.removeValue(forKey: token)
    if FileManager.default.fileExists(atPath: path.path) {
      _ = try FileManager.default.replaceItemAt(path, withItemAt: state.temporary)
    } else {
      try FileManager.default.moveItem(at: state.temporary, to: path)
    }
    return path
  }

  private func clearPendingWrite(_ token: String) {
    guard let state = pendingWrites.removeValue(forKey: token) else { return }
    try? FileManager.default.removeItem(at: state.temporary)
  }

  deinit {
    for token in Array(pendingWrites.keys) {
      clearPendingWrite(token)
    }
  }
}

private final class PendingWrite {
  let path: URL
  let temporary: URL
  let expectedBytes: Int
  var written = 0
  var nextIndex = 0

  init(path: URL, temporary: URL, expectedBytes: Int) {
    self.path = path
    self.temporary = temporary
    self.expectedBytes = expectedBytes
  }
}
