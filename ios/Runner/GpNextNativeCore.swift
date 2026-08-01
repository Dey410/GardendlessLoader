import Foundation

enum GpNextNativeAction {
  case value(Any)
  case exportFile(URL)
  case openURL(URL)
  case importPackages
}

final class GpNextNativeCore {
  private let session: NativeGameSession
  private let queue = DispatchQueue(label: "io.github.dey410.gardendless.gp-next", qos: .userInitiated)
  private var pendingExports = Set<URL>()

  init(session: NativeGameSession) throws {
    self.session = session
    try ensureDirectory(session.gpNextRoot)
    try ensureDirectory(session.gpNextRoot.appendingPathComponent("packs", isDirectory: true))
    try ensureDirectory(session.gpNextRoot.appendingPathComponent("patches", isDirectory: true))
  }

  func dispatch(request: [String: Any], completion: @escaping (Result<GpNextNativeAction, Error>) -> Void) {
    queue.async {
      completion(Result { try self.invoke(request) })
    }
  }

  private func invoke(_ request: [String: Any]) throws -> GpNextNativeAction {
    let command = request["command"] as? String ?? ""
    let args = request["args"] as? [String: Any] ?? [:]
    let options = request["options"] as? [String: Any] ?? [:]
    switch command {
    case "plugin:fs|mkdir":
      try ensureDirectory(resolve(args["path"], nestedOptions(args, options)))
      return .value(NSNull())
    case "plugin:fs|read_dir":
      return .value(try readDirectory(resolve(args["path"], nestedOptions(args, options))))
    case "plugin:fs|read_file", "plugin:fs|read_text_file":
      return .value(Array(try Data(contentsOf: resolve(args["path"], nestedOptions(args, options)))))
    case "plugin:fs|exists":
      let path = try resolve(args["path"], nestedOptions(args, options))
      return .value(FileManager.default.fileExists(atPath: path.path))
    case "plugin:fs|remove":
      try remove(resolve(args["path"], nestedOptions(args, options)), recursive: recursive(nestedOptions(args, options)))
      return .value(NSNull())
    case "plugin:fs|write_text_file":
      return try writeFile(request: request, args: args, options: options)
    case "plugin:dialog|save":
      return .value(try prepareExport(args))
    case "plugin:opener|open_url":
      guard let raw = args["url"] as? String, let url = URL(string: raw),
            url.scheme == "https" || url.scheme == "http",
            let host = url.host?.lowercased(),
            session.allowedRemoteHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else {
        throw GameSessionError.invalid("GP-Next 请求打开了未授权网址")
      }
      return .openURL(url)
    case "plugin:opener|open_path":
      return .importPackages
    default:
      throw GameSessionError.invalid("未兼容的 GP-Next 命令：\(command)")
    }
  }

  private func readDirectory(_ url: URL) throws -> [[String: Any]] {
    try assertNoSymlink(url)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw GameSessionError.invalid("目录不存在：\(url.path)")
    }
    return try FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
    ).sorted { $0.lastPathComponent < $1.lastPathComponent }.map { child in
      let values = try child.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
      return [
        "name": child.lastPathComponent,
        "isFile": values.isRegularFile == true,
        "isDirectory": values.isDirectory == true,
        "isSymlink": values.isSymbolicLink == true,
      ]
    }
  }

  private func writeFile(
    request: [String: Any],
    args: [String: Any],
    options: [String: Any]
  ) throws -> GpNextNativeAction {
    let headers = options["headers"] as? [String: Any] ?? [:]
    let headerOptions: [String: Any]
    if let raw = headers["options"] as? String, raw != "undefined",
       let data = raw.data(using: .utf8),
       let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      headerOptions = decoded
    } else {
      headerOptions = [:]
    }
    let rawPath = (headers["path"] as? String)?.removingPercentEncoding ?? args["path"] as? String
    let path = try resolve(rawPath, headerOptions)
    guard let numbers = args["__gardendlessBytes"] as? [NSNumber] else {
      throw GameSessionError.invalid("GP-Next 写入内容不是字节数组")
    }
    try ensureDirectory(path.deletingLastPathComponent())
    try assertNoSymlink(path)
    try Data(numbers.map { UInt8(truncating: $0) }).write(to: path, options: .atomic)
    if pendingExports.remove(path) != nil {
      return .exportFile(path)
    }
    return .value(NSNull())
  }

  private func prepareExport(_ args: [String: Any]) throws -> String {
    let options = args["options"] as? [String: Any]
    let requested = options?["defaultPath"] as? String ?? "gardendless-export.json"
    try ensureDirectory(session.exportTemporaryRoot)
    let path = session.exportTemporaryRoot.appendingPathComponent(safeFileName(requested))
    pendingExports.insert(path)
    return path.path
  }

  private func remove(_ url: URL, recursive: Bool) throws {
    try assertNoSymlink(url)
    guard url != session.gpNextRoot else { throw GameSessionError.invalid("不允许删除 GP-Next 根目录") }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
    if isDirectory.boolValue && !recursive {
      throw GameSessionError.invalid("目录删除需要 recursive=true")
    }
    if isDirectory.boolValue {
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )
      while let child = enumerator?.nextObject() as? URL {
        if try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
          throw GameSessionError.invalid("不允许操作符号链接")
        }
      }
    }
    try FileManager.default.removeItem(at: url)
  }

  private func resolve(_ value: Any?, _ options: [String: Any]) throws -> URL {
    guard var raw = value as? String, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw GameSessionError.invalid("GP-Next 文件路径为空")
    }
    if let base = options["baseDir"] as? Int, base != 14 {
      throw GameSessionError.invalid("不允许访问 Tauri baseDir \(base)")
    }
    if raw.hasPrefix("file:") { raw = URL(string: raw)?.path ?? raw }
    raw = raw.replacingOccurrences(of: "\\", with: "/")
    let candidate = (raw.hasPrefix("/")
      ? URL(fileURLWithPath: raw)
      : session.appRoot.appendingPathComponent(raw)).standardizedFileURL
    let root = session.gpNextRoot.standardizedFileURL.path
    guard candidate.path == root || candidate.path.hasPrefix(root + "/") else {
      throw GameSessionError.invalid("GP-Next 路径超出 Loader 沙箱")
    }
    try assertNoSymlink(candidate)
    return candidate
  }

  private func assertNoSymlink(_ target: URL) throws {
    let root = session.gpNextRoot.standardizedFileURL
    if try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
      throw GameSessionError.invalid("GP-Next 根目录不能是符号链接")
    }
    let relative = target.standardizedFileURL.path.dropFirst(root.path.count)
    var current = root
    for component in relative.split(separator: "/") {
      current.appendPathComponent(String(component))
      guard FileManager.default.fileExists(atPath: current.path) else { return }
      if try current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
        throw GameSessionError.invalid("不允许通过符号链接访问文件")
      }
    }
  }

  private func ensureDirectory(_ url: URL) throws {
    try assertNoSymlink(url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try assertNoSymlink(url)
  }

  private func nestedOptions(_ args: [String: Any], _ options: [String: Any]) -> [String: Any] {
    args["options"] as? [String: Any] ?? options
  }

  private func recursive(_ options: [String: Any]) -> Bool { options["recursive"] as? Bool ?? true }

  private func safeFileName(_ value: String) -> String {
    let base = value.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
    let invalid = CharacterSet(charactersIn: ":*?\"<>|").union(.controlCharacters)
    let cleaned = base.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined()
    return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "gardendless-export.json" : cleaned
  }
}
