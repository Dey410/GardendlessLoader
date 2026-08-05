import Foundation
import WebKit

final class GameResourceSchemeHandler: NSObject, WKURLSchemeHandler {
  private enum TaskState: Equatable {
    case active
    case cancelled
    case finished
  }

  private struct AudioFileEntry {
    let data: Data
    let totalLength: Int64
    let mimeType: String
    let etag: String
  }

  private struct CachedAudioFile {
    let entry: AudioFileEntry
    var lastAccess: UInt64
  }

  private struct ResourceMetadata {
    let file: URL
    let totalLength: Int64
    let mimeType: String
    let etag: String
  }

  private enum AudioLoadResult {
    case cached(AudioFileEntry)
    case streamed(ResourceMetadata)
    case cancelled
    case notFound
  }

  private let root: URL
  private let onDiagnostic: ((String, String?, Int, [String: String]) -> Void)?
  private let resourceQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "io.github.dey410.gardendless.resource"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 6
    return queue
  }()
  private let audioQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "io.github.dey410.gardendless.audio-resource"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 2
    return queue
  }()

  private let taskStateLock = NSRecursiveLock()
  private var taskStates = [ObjectIdentifier: TaskState]()

  private let smallAudioByteLimit = 256 * 1024
  private let audioCacheByteLimit = 24 * 1024 * 1024
  private let audioCacheCondition = NSCondition()
  private var audioCache = [String: CachedAudioFile]()
  private var audioCacheBytes = 0
  private var audioCacheClock: UInt64 = 0
  private var loadingAudioPaths = Set<String>()

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
      taskStates[identifier] = .active
    }
    let queue = isAudioPath(urlSchemeTask.request.url?.path) ? audioQueue : resourceQueue
    queue.addOperation { [weak self] in
      guard let self else { return }
      self.serve(urlSchemeTask, identifier: identifier)
    }
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
    taskStateLock.synchronized {
      if taskStates[identifier] == .active {
        taskStates[identifier] = .cancelled
      }
    }
    audioCacheCondition.lock()
    audioCacheCondition.broadcast()
    audioCacheCondition.unlock()
  }

  private func serve(_ task: WKURLSchemeTask, identifier: ObjectIdentifier) {
    defer {
      taskStateLock.synchronized {
        taskStates.removeValue(forKey: identifier)
      }
    }
    guard isActive(identifier) else { return }
    guard let url = task.request.url,
          url.scheme == "gardendless-game", url.host == "localhost" else {
      diagnose("resource_path_forbidden", path: task.request.url?.path, status: 403)
      sendError(task, identifier: identifier, status: 403, reason: "Forbidden")
      return
    }
    let method = task.request.httpMethod ?? "GET"
    guard method == "GET" || method == "HEAD" else {
      diagnose("resource_method_not_allowed", path: url.path, status: 405, details: ["method": method])
      sendError(
        task,
        identifier: identifier,
        status: 405,
        reason: "Method Not Allowed",
        headers: ["Allow": "GET, HEAD"]
      )
      return
    }
    guard let relativePath = decodePath(url) else {
      diagnose("resource_file_not_found", path: url.path, status: 404)
      sendError(task, identifier: identifier, status: 404, reason: "Not Found")
      return
    }

    do {
      if isCacheableAudioPath(relativePath) {
        switch try loadAudio(relativePath, identifier: identifier) {
        case let .cached(entry):
          serve(
            task,
            identifier: identifier,
            url: url,
            relativePath: relativePath,
            method: method,
            metadata: ResourceMetadata(
              file: root.appendingPathComponent(relativePath),
              totalLength: entry.totalLength,
              mimeType: entry.mimeType,
              etag: entry.etag
            ),
            cachedData: entry.data
          )
        case let .streamed(metadata):
          serve(
            task,
            identifier: identifier,
            url: url,
            relativePath: relativePath,
            method: method,
            metadata: metadata,
            cachedData: nil
          )
        case .cancelled:
          return
        case .notFound:
          diagnose("resource_file_not_found", path: url.path, status: 404)
          sendError(task, identifier: identifier, status: 404, reason: "Not Found")
        }
        return
      }

      guard let file = resolveFile(relativePath) else {
        diagnose("resource_file_not_found", path: url.path, status: 404)
        sendError(task, identifier: identifier, status: 404, reason: "Not Found")
        return
      }
      let metadata = try resourceMetadata(file: file, relativePath: relativePath)
      serve(
        task,
        identifier: identifier,
        url: url,
        relativePath: relativePath,
        method: method,
        metadata: metadata,
        cachedData: nil
      )
    } catch {
      diagnose(
        "resource_read_failed",
        path: task.request.url?.path,
        status: 500,
        details: ["errorType": String(describing: type(of: error))]
      )
      failTask(task, identifier: identifier, error: error)
    }
  }

  private func serve(
    _ task: WKURLSchemeTask,
    identifier: ObjectIdentifier,
    url: URL,
    relativePath: String,
    method: String,
    metadata: ResourceMetadata,
    cachedData: Data?
  ) {
    do {
      let length = metadata.totalLength
      var headers = [
        "Accept-Ranges": "bytes",
        "ETag": metadata.etag,
        "Cache-Control": cacheControl(relativePath),
        "X-Content-Type-Options": "nosniff",
      ]
      if task.request.value(forHTTPHeaderField: "If-None-Match") == metadata.etag {
        send(
          task,
          identifier: identifier,
          url: url,
          status: 304,
          reason: "Not Modified",
          headers: headers,
          body: nil
        )
        return
      }
      let rangeHeader = task.request.value(forHTTPHeaderField: "Range")
      let range = rangeHeader.flatMap { parseRange($0, length: length) }
      if rangeHeader != nil && range == nil {
        diagnose("resource_read_failed", path: relativePath, status: 416)
        headers["Content-Range"] = "bytes */\(length)"
        sendError(
          task,
          identifier: identifier,
          status: 416,
          reason: "Range Not Satisfiable",
          headers: headers
        )
        return
      }
      let start = range?.lowerBound ?? 0
      let end = range?.upperBound ?? max(0, length - 1)
      let responseLength = length == 0 ? 0 : end - start + 1
      headers["Content-Type"] = metadata.mimeType
      if metadata.mimeType == "application/octet-stream" {
        diagnose(
          "resource_mime_mismatch",
          path: relativePath,
          status: 200,
          details: ["expectedMime": "known resource MIME", "actualMime": metadata.mimeType]
        )
      }
      headers["Content-Length"] = String(responseLength)
      if range != nil {
        headers["Content-Range"] = "bytes \(start)-\(end)/\(length)"
      }
      let status = range == nil ? 200 : 206
      let reason = range == nil ? "OK" : "Partial Content"
      guard sendResponse(
        task,
        identifier: identifier,
        url: url,
        status: status,
        reason: reason,
        headers: headers
      ) else { return }
      guard method == "GET", responseLength > 0 else {
        finishTask(task, identifier: identifier)
        return
      }

      if let cachedData {
        let body = cachedData.subdata(in: Int(start)..<(Int(end) + 1))
        guard sendData(task, identifier: identifier, data: body) else { return }
        finishTask(task, identifier: identifier)
        return
      }

      let handle = try FileHandle(forReadingFrom: metadata.file)
      defer { try? handle.close() }
      try handle.seek(toOffset: UInt64(start))
      var remaining = responseLength
      while remaining > 0 && isActive(identifier) {
        let count = Int(min(remaining, 128 * 1024))
        guard let data = try handle.read(upToCount: count), !data.isEmpty else { break }
        guard sendData(task, identifier: identifier, data: data) else { return }
        remaining -= Int64(data.count)
      }
      guard isActive(identifier) else { return }
      guard remaining == 0 else {
        throw GameSessionError.invalid("Unexpected end of resource file")
      }
      finishTask(task, identifier: identifier)
    } catch {
      diagnose(
        "resource_read_failed",
        path: relativePath,
        status: 500,
        details: ["errorType": String(describing: type(of: error))]
      )
      failTask(task, identifier: identifier, error: error)
    }
  }

  private func loadAudio(
    _ relativePath: String,
    identifier: ObjectIdentifier
  ) throws -> AudioLoadResult {
    audioCacheCondition.lock()
    while loadingAudioPaths.contains(relativePath) {
      if let entry = cachedAudioEntryLocked(relativePath) {
        audioCacheCondition.unlock()
        return .cached(entry)
      }
      audioCacheCondition.wait(until: Date(timeIntervalSinceNow: 0.05))
      audioCacheCondition.unlock()
      guard isActive(identifier) else { return .cancelled }
      audioCacheCondition.lock()
    }
    if let entry = cachedAudioEntryLocked(relativePath) {
      audioCacheCondition.unlock()
      return .cached(entry)
    }
    loadingAudioPaths.insert(relativePath)
    audioCacheCondition.unlock()

    do {
      guard let file = resolveFile(relativePath) else {
        finishAudioLoad(relativePath, entry: nil)
        return .notFound
      }
      let properties = try fileProperties(file)
      guard properties.length <= Int64(smallAudioByteLimit) else {
        let metadata = ResourceMetadata(
          file: file,
          totalLength: properties.length,
          mimeType: try detectedMimeType(relativePath, file: file),
          etag: properties.etag
        )
        finishAudioLoad(relativePath, entry: nil)
        return .streamed(metadata)
      }
      guard isActive(identifier) else {
        finishAudioLoad(relativePath, entry: nil)
        return .cancelled
      }
      let data = try Data(contentsOf: file, options: [.mappedIfSafe])
      let entry = AudioFileEntry(
        data: data,
        totalLength: properties.length,
        mimeType: detectedMimeType(relativePath, header: data.prefix(16)),
        etag: properties.etag
      )
      finishAudioLoad(relativePath, entry: entry)
      return .cached(entry)
    } catch {
      finishAudioLoad(relativePath, entry: nil)
      throw error
    }
  }

  private func finishAudioLoad(_ relativePath: String, entry: AudioFileEntry?) {
    audioCacheCondition.lock()
    if let entry {
      audioCacheClock &+= 1
      audioCache[relativePath] = CachedAudioFile(entry: entry, lastAccess: audioCacheClock)
      audioCacheBytes += entry.data.count
      evictAudioCacheLocked()
    }
    loadingAudioPaths.remove(relativePath)
    audioCacheCondition.broadcast()
    audioCacheCondition.unlock()
  }

  private func cachedAudioEntryLocked(_ relativePath: String) -> AudioFileEntry? {
    guard var cached = audioCache[relativePath] else { return nil }
    audioCacheClock &+= 1
    cached.lastAccess = audioCacheClock
    audioCache[relativePath] = cached
    return cached.entry
  }

  private func evictAudioCacheLocked() {
    while audioCacheBytes > audioCacheByteLimit,
          let oldest = audioCache.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
      audioCache.removeValue(forKey: oldest.key)
      audioCacheBytes -= oldest.value.entry.data.count
    }
  }

  private func resourceMetadata(file: URL, relativePath: String) throws -> ResourceMetadata {
    let properties = try fileProperties(file)
    return ResourceMetadata(
      file: file,
      totalLength: properties.length,
      mimeType: try detectedMimeType(relativePath, file: file),
      etag: properties.etag
    )
  }

  private func fileProperties(_ file: URL) throws -> (length: Int64, etag: String) {
    let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let length = Int64(values.fileSize ?? 0)
    let etag = "\"\(Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0))-\(length)\""
    return (length, etag)
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
    if ["png", "jpg", "jpeg", "gif", "webp", "svg", "mp3", "m4a", "ogg", "wav", "mp4", "webm", "wasm", "bin"].contains(ext) {
      return "public, max-age=86400"
    }
    return "no-cache"
  }

  private func detectedMimeType(_ path: String, file: URL) throws -> String {
    guard (path as NSString).pathExtension.lowercased() == "mp3" else {
      return mimeType(path)
    }
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let header = try handle.read(upToCount: 16) ?? Data()
    return detectedMimeType(path, header: header)
  }

  private func detectedMimeType(_ path: String, header: Data.SubSequence) -> String {
    guard (path as NSString).pathExtension.lowercased() == "mp3" else {
      return mimeType(path)
    }
    let bytes = Data(header)
    let mp4Brands = ["ftypM4A", "ftypisom", "ftypmp42"]
    if mp4Brands.contains(where: { bytes.range(of: Data($0.utf8)) != nil }) {
      return "audio/mp4"
    }
    return "audio/mpeg"
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
    case "m4a": return "audio/mp4"
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

  private func isAudioPath(_ path: String?) -> Bool {
    guard let path else { return false }
    return ["mp3", "m4a", "ogg"].contains((path as NSString).pathExtension.lowercased())
  }

  private func isCacheableAudioPath(_ path: String) -> Bool {
    guard isAudioPath(path) else { return false }
    let tokens = path.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    return !tokens.contains("bgm") && !tokens.contains("music")
  }

  private func sendError(
    _ task: WKURLSchemeTask,
    identifier: ObjectIdentifier,
    status: Int,
    reason: String,
    headers: [String: String] = [:]
  ) {
    guard let url = task.request.url else { return }
    send(
      task,
      identifier: identifier,
      url: url,
      status: status,
      reason: reason,
      headers: headers.merging(["Content-Length": "0"]) { a, _ in a },
      body: Data()
    )
  }

  private func send(
    _ task: WKURLSchemeTask,
    identifier: ObjectIdentifier,
    url: URL,
    status: Int,
    reason: String,
    headers: [String: String],
    body: Data?,
    finish: Bool = true
  ) {
    guard sendResponse(
      task,
      identifier: identifier,
      url: url,
      status: status,
      reason: reason,
      headers: headers
    ) else { return }
    if let body, !body.isEmpty,
       !sendData(task, identifier: identifier, data: body) {
      return
    }
    if finish { finishTask(task, identifier: identifier) }
  }

  private func sendResponse(
    _ task: WKURLSchemeTask,
    identifier: ObjectIdentifier,
    url: URL,
    status: Int,
    reason: String,
    headers: [String: String]
  ) -> Bool {
    guard let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    ) else { return false }
    return withActiveTask(identifier) {
      task.didReceive(response)
    }
  }

  private func sendData(
    _ task: WKURLSchemeTask,
    identifier: ObjectIdentifier,
    data: Data
  ) -> Bool {
    withActiveTask(identifier) {
      task.didReceive(data)
    }
  }

  private func finishTask(_ task: WKURLSchemeTask, identifier: ObjectIdentifier) {
    taskStateLock.synchronized {
      guard taskStates[identifier] == .active else { return }
      taskStates[identifier] = .finished
      task.didFinish()
    }
  }

  private func failTask(
    _ task: WKURLSchemeTask,
    identifier: ObjectIdentifier,
    error: Error
  ) {
    taskStateLock.synchronized {
      guard taskStates[identifier] == .active else { return }
      taskStates[identifier] = .finished
      task.didFailWithError(error)
    }
  }

  private func withActiveTask(
    _ identifier: ObjectIdentifier,
    action: () -> Void
  ) -> Bool {
    taskStateLock.synchronized {
      guard taskStates[identifier] == .active else { return false }
      action()
      return true
    }
  }

  private func isActive(_ identifier: ObjectIdentifier) -> Bool {
    taskStateLock.synchronized { taskStates[identifier] == .active }
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

private extension NSRecursiveLock {
  func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
