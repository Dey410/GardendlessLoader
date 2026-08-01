import Foundation
import WebKit

final class GameResourceSchemeHandler: NSObject, WKURLSchemeHandler {
  private let root: URL
  private let onDiagnostic: ((String, String?, Int, [String: String]) -> Void)?
  private let queue = DispatchQueue(
    label: "io.github.dey410.gardendless.resource-stream",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private let taskStateLock = NSLock()
  private var activeTasks = Set<ObjectIdentifier>()
  private var stoppedTasks = Set<ObjectIdentifier>()

  init(
    resourceRoot: URL,
    onDiagnostic: ((String, String?, Int, [String: String]) -> Void)? = nil
  ) throws {
    let values = try resourceRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw GameSessionError.invalid("Resource root is not a safe directory")
    }
    root = resourceRoot.resolvingSymlinksInPath().standardizedFileURL
    self.onDiagnostic = onDiagnostic
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
    taskStateLock.synchronized {
      activeTasks.insert(identifier)
      stoppedTasks.remove(identifier)
    }
    queue.async { [weak self] in
      guard let self else { return }
      self.serve(urlSchemeTask, identifier: identifier)
    }
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
    taskStateLock.synchronized {
      if activeTasks.contains(identifier) {
        stoppedTasks.insert(identifier)
      }
    }
  }

  private func serve(_ task: WKURLSchemeTask, identifier: ObjectIdentifier) {
    defer {
      taskStateLock.synchronized {
        activeTasks.remove(identifier)
        stoppedTasks.remove(identifier)
      }
    }
    guard !isStopped(identifier) else { return }
    guard let url = task.request.url,
          url.scheme == "gardendless-game", url.host == "localhost" else {
      diagnose("resource_path_forbidden", path: task.request.url?.path, status: 403)
      sendError(task, status: 403, reason: "Forbidden")
      return
    }
    let method = task.request.httpMethod ?? "GET"
    guard method == "GET" || method == "HEAD" else {
      diagnose("resource_method_not_allowed", path: url.path, status: 405, details: ["method": method])
      sendError(task, status: 405, reason: "Method Not Allowed", headers: ["Allow": "GET, HEAD"])
      return
    }
    guard let relativePath = decodePath(url), let file = resolveFile(relativePath) else {
      diagnose("resource_file_not_found", path: url.path, status: 404)
      sendError(task, status: 404, reason: "Not Found")
      return
    }
    do {
      let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      let length = Int64(values.fileSize ?? 0)
      let etag = "\"\(Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0))-\(length)\""
      var headers = [
        "Accept-Ranges": "bytes",
        "ETag": etag,
        "Cache-Control": cacheControl(relativePath),
        "X-Content-Type-Options": "nosniff",
      ]
      if task.request.value(forHTTPHeaderField: "If-None-Match") == etag {
        send(task, url: url, status: 304, reason: "Not Modified", headers: headers, body: nil)
        return
      }
      let rangeHeader = task.request.value(forHTTPHeaderField: "Range")
      let range = rangeHeader.flatMap { parseRange($0, length: length) }
      if rangeHeader != nil && range == nil {
        diagnose("resource_read_failed", path: relativePath, status: 416)
        headers["Content-Range"] = "bytes */\(length)"
        sendError(task, status: 416, reason: "Range Not Satisfiable", headers: headers)
        return
      }
      let start = range?.lowerBound ?? 0
      let end = range?.upperBound ?? max(0, length - 1)
      let responseLength = length == 0 ? 0 : end - start + 1
      let contentType = mimeType(relativePath)
      headers["Content-Type"] = contentType
      if contentType == "application/octet-stream" {
        diagnose(
          "resource_mime_mismatch",
          path: relativePath,
          status: 200,
          details: ["expectedMime": "known resource MIME", "actualMime": contentType]
        )
      }
      headers["Content-Length"] = String(responseLength)
      if range != nil {
        headers["Content-Range"] = "bytes \(start)-\(end)/\(length)"
      }
      let status = range == nil ? 200 : 206
      let reason = range == nil ? "OK" : "Partial Content"
      send(task, url: url, status: status, reason: reason, headers: headers, body: nil, finish: false)
      guard method == "GET", responseLength > 0 else {
        if !isStopped(identifier) { task.didFinish() }
        return
      }
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      try handle.seek(toOffset: UInt64(start))
      var remaining = responseLength
      while remaining > 0 && !isStopped(identifier) {
        let count = Int(min(remaining, 128 * 1024))
        guard let data = try handle.read(upToCount: count), !data.isEmpty else { break }
        task.didReceive(data)
        remaining -= Int64(data.count)
      }
      if !isStopped(identifier) {
        guard remaining == 0 else {
          throw GameSessionError.invalid("Unexpected end of resource file")
        }
        task.didFinish()
      }
    } catch {
      diagnose(
        "resource_read_failed",
        path: task.request.url?.path,
        status: 500,
        details: ["errorType": String(describing: type(of: error))]
      )
      if !isStopped(identifier) { task.didFailWithError(error) }
    }
  }

  private func decodePath(_ url: URL) -> String? {
    guard let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
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

  private func resolveFile(_ relativePath: String) -> URL? {
    var cursor = root
    for component in relativePath.split(separator: "/") {
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

  private func parseRange(_ value: String, length: Int64) -> ClosedRange<Int64>? {
    guard length > 0, value.hasPrefix("bytes="), !value.contains(",") else { return nil }
    let parts = value.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    if parts[0].isEmpty {
      guard let suffix = Int64(parts[1]), suffix > 0 else { return nil }
      return max(0, length - suffix)...(length - 1)
    }
    guard let start = Int64(parts[0]), start >= 0, start < length else { return nil }
    let requestedEnd = parts[1].isEmpty ? length - 1 : Int64(parts[1])
    guard let requestedEnd, requestedEnd >= start else { return nil }
    return start...min(requestedEnd, length - 1)
  }

  private func cacheControl(_ path: String) -> String {
    if ["index.html", "src/settings.json", "src/import-map.json"].contains(path) {
      return "no-cache"
    }
    let name = (path as NSString).lastPathComponent
    if name.range(of: "(?:^|[._-])[0-9a-fA-F]{8,}(?:[._-]|$)", options: .regularExpression) != nil {
      return "public, max-age=31536000, immutable"
    }
    let ext = (path as NSString).pathExtension.lowercased()
    if ["png", "jpg", "jpeg", "gif", "webp", "svg", "mp3", "ogg", "wav", "mp4", "webm", "wasm", "bin"].contains(ext) {
      return "public, max-age=86400"
    }
    return "no-cache"
  }

  private func mimeType(_ path: String) -> String {
    switch (path as NSString).pathExtension.lowercased() {
    case "html", "htm": return "text/html; charset=utf-8"
    case "js", "mjs": return "application/javascript; charset=utf-8"
    case "css": return "text/css; charset=utf-8"
    case "json", "json5": return "application/json; charset=utf-8"
    case "wasm": return "application/wasm"
    case "svg": return "image/svg+xml"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "mp3": return "audio/mpeg"
    case "ogg": return "audio/ogg"
    case "wav": return "audio/wav"
    case "mp4": return "video/mp4"
    case "webm": return "video/webm"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf": return "font/ttf"
    default: return "application/octet-stream"
    }
  }

  private func sendError(
    _ task: WKURLSchemeTask,
    status: Int,
    reason: String,
    headers: [String: String] = [:]
  ) {
    guard let url = task.request.url else { return }
    send(task, url: url, status: status, reason: reason, headers: headers.merging(["Content-Length": "0"]) { a, _ in a }, body: Data())
  }

  private func send(
    _ task: WKURLSchemeTask,
    url: URL,
    status: Int,
    reason: String,
    headers: [String: String],
    body: Data?,
    finish: Bool = true
  ) {
    guard let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    ) else { return }
    task.didReceive(response)
    if let body, !body.isEmpty { task.didReceive(body) }
    if finish { task.didFinish() }
  }

  private func isStopped(_ identifier: ObjectIdentifier) -> Bool {
    taskStateLock.synchronized { stoppedTasks.contains(identifier) }
  }

  private func diagnose(
    _ code: String,
    path: String?,
    status: Int,
    details: [String: String] = [:]
  ) {
    onDiagnostic?(code, path, status, details)
  }
}

private extension NSLock {
  func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
