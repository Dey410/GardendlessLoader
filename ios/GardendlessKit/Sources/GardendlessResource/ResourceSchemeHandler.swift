import Foundation
import GardendlessCore
import WebKit

/// Serves files from one resource slot over `gardendless-game://localhost`
/// with Range/ETag/MIME/streaming semantics and strict cancellation safety.
public final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
  private enum TaskState {
    case active
    case cancelled
    case finished
  }

  private struct CachedAudio {
    let entry: CachedAudioEntry
    var lastAccess: UInt64
  }

  private enum AudioLoadResult {
    case cached(CachedAudioEntry)
    case streamed(ResourceMetadata)
    case cancelled
    case notFound
  }

  private let sandbox: PathSandbox
  private let configuration: GameConfiguration
  private let onDiagnostic: ((String, String?, Int, [String: String]) -> Void)?
  private let resourceQueue: OperationQueue
  private let audioQueue: OperationQueue

  private let stateLock = NSLock()
  private var taskStates: [ObjectIdentifier: TaskState] = [:]
  private var callbackReservations: [ObjectIdentifier: Int] = [:]

  private let audioCacheCondition = NSCondition()
  private var audioCache: [String: CachedAudio] = [:]
  private var audioCacheBytes = 0
  private var audioCacheClock: UInt64 = 0
  private var loadingAudioPaths = Set<String>()

  public init(
    sandbox: PathSandbox,
    configuration: GameConfiguration = .default,
    onDiagnostic: ((String, String?, Int, [String: String]) -> Void)? = nil
  ) {
    self.sandbox = sandbox
    self.configuration = configuration
    self.onDiagnostic = onDiagnostic
    let resources = OperationQueue()
    resources.name = "io.github.dey410.gardendless.resource"
    resources.qualityOfService = .userInitiated
    resources.maxConcurrentOperationCount = configuration.resourceQueueConcurrency
    resourceQueue = resources
    let audio = OperationQueue()
    audio.name = "io.github.dey410.gardendless.audio-resource"
    audio.qualityOfService = .userInitiated
    audio.maxConcurrentOperationCount = 2
    audioQueue = audio
  }

  public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
    stateLock.synchronized {
      taskStates[identifier] = .active
    }
    let queue = isAudioPath(urlSchemeTask.request.url?.path) ? audioQueue : resourceQueue
    queue.addOperation { [weak self] in
      self?.serve(urlSchemeTask, identifier: identifier)
    }
  }

  public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
    stateLock.synchronized {
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
      stateLock.synchronized {
        taskStates.removeValue(forKey: identifier)
        callbackReservations.removeValue(forKey: identifier)
      }
    }
    guard isActive(identifier) else { return }
    guard let url = task.request.url,
          url.scheme == ResourceConstants.scheme,
          url.host == ResourceConstants.host else {
      diagnose("resource_path_forbidden", path: task.request.url?.path, status: 403)
      sendError(
        task,
        identifier: identifier,
        status: 403,
        reason: "Forbidden"
      )
      return
    }
    let method = task.request.httpMethod ?? "GET"
    guard ResourceConstants.allowedMethods.contains(method) else {
      diagnose(
        "resource_method_not_allowed",
        path: url.path,
        status: 405,
        details: ["method": method]
      )
      sendError(
        task,
        identifier: identifier,
        status: 405,
        reason: "Method Not Allowed",
        headers: ["Allow": "GET, HEAD"]
      )
      return
    }
    guard let relativePath = sandbox.relativePath(for: url) else {
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
              file: sandbox.root.appendingPathComponent(relativePath),
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

      guard let file = sandbox.resolve(relativePath) else {
        diagnose("resource_file_not_found", path: url.path, status: 404)
        sendError(task, identifier: identifier, status: 404, reason: "Not Found")
        return
      }
      let metadata = try ResourceMetadata.make(
        file: file,
        relativePath: relativePath,
        sandbox: sandbox
      )
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
        let count = Int(min(remaining, Int64(ResourceConstants.streamChunkSize)))
        guard let data = try handle.read(upToCount: count), !data.isEmpty else {
          break
        }
        guard sendData(task, identifier: identifier, data: data) else { return }
        remaining -= Int64(data.count)
      }
      guard isActive(identifier) else { return }
      guard remaining == 0 else {
        throw GameError.failed(.resourceReadFailed, "Unexpected end of resource file")
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
      guard let file = sandbox.resolve(relativePath) else {
        finishAudioLoad(relativePath, entry: nil)
        return .notFound
      }
      let properties = try sandbox.fileProperties(file)
      guard properties.length <= Int64(ResourceConstants.smallAudioByteLimit) else {
        let metadata = try ResourceMetadata.make(
          file: file,
          relativePath: relativePath,
          sandbox: sandbox
        )
        finishAudioLoad(relativePath, entry: nil)
        return .streamed(metadata)
      }
      guard isActive(identifier) else {
        finishAudioLoad(relativePath, entry: nil)
        return .cancelled
      }
      let data = try Data(contentsOf: file, options: [.mappedIfSafe])
      let entry = CachedAudioEntry(
        data: data,
        totalLength: properties.length,
        mimeType: ResourceMIME.detectAudioType(
          path: relativePath,
          header: data.prefix(16)
        ),
        etag: properties.etag
      )
      finishAudioLoad(relativePath, entry: entry)
      return .cached(entry)
    } catch {
      finishAudioLoad(relativePath, entry: nil)
      throw error
    }
  }

  private func finishAudioLoad(_ relativePath: String, entry: CachedAudioEntry?) {
    audioCacheCondition.lock()
    if let entry {
      audioCacheClock &+= 1
      audioCache[relativePath] = CachedAudio(
        entry: entry,
        lastAccess: audioCacheClock
      )
      audioCacheBytes += entry.data.count
      evictAudioCacheLocked()
    }
    loadingAudioPaths.remove(relativePath)
    audioCacheCondition.broadcast()
    audioCacheCondition.unlock()
  }

  private func cachedAudioEntryLocked(_ relativePath: String) -> CachedAudioEntry? {
    guard var cached = audioCache[relativePath] else { return nil }
    audioCacheClock &+= 1
    cached.lastAccess = audioCacheClock
    audioCache[relativePath] = cached
    return cached.entry
  }

  private func evictAudioCacheLocked() {
    while audioCacheBytes > configuration.audioCacheByteLimit,
          let oldest = audioCache.min(by: {
            $0.value.lastAccess < $1.value.lastAccess
          }) {
      audioCache.removeValue(forKey: oldest.key)
      audioCacheBytes -= oldest.value.entry.data.count
    }
  }

  private func parseRange(_ value: String, length: Int64) -> ClosedRange<Int64>? {
    guard length > 0, value.hasPrefix("bytes="), !value.contains(",") else {
      return nil
    }
    let parts = value
      .dropFirst(6)
      .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    if parts[0].isEmpty {
      guard let suffix = Int64(parts[1]), suffix > 0 else { return nil }
      return max(0, length - suffix)...(length - 1)
    }
    guard let start = Int64(parts[0]), start >= 0, start < length else {
      return nil
    }
    let requestedEnd = parts[1].isEmpty ? length - 1 : Int64(parts[1])
    guard let requestedEnd, requestedEnd >= start else { return nil }
    return start...min(requestedEnd, length - 1)
  }

  private func cacheControl(_ path: String) -> String {
    if ["index.html", "src/settings.json", "src/import-map.json"].contains(path) {
      return "no-cache"
    }
    let name = (path as NSString).lastPathComponent
    if name.range(
      of: "(?:^|[._-])[0-9a-fA-F]{8,}(?:[._-]|$)",
      options: .regularExpression
    ) != nil {
      return "public, max-age=31536000, immutable"
    }
    let ext = (path as NSString).pathExtension.lowercased()
    if [
      "png", "jpg", "jpeg", "gif", "webp", "svg", "mp3", "m4a", "ogg",
      "wav", "mp4", "webm", "wasm", "bin",
    ].contains(ext) {
      return "public, max-age=86400"
    }
    return "no-cache"
  }

  private func isAudioPath(_ path: String?) -> Bool {
    guard let path else { return false }
    return ["mp3", "m4a", "ogg"].contains(
      (path as NSString).pathExtension.lowercased()
    )
  }

  private func isCacheableAudioPath(_ path: String) -> Bool {
    guard isAudioPath(path) else { return false }
    let tokens = path.lowercased().split(whereSeparator: {
      !$0.isLetter && !$0.isNumber
    })
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
      headers: headers.merging(["Content-Length": "0"]) { first, _ in first },
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
    body: Data?
  ) {
    guard sendResponse(
      task,
      identifier: identifier,
      url: url,
      status: status,
      reason: reason,
      headers: headers
    ) else { return }
    if let body, !body.isEmpty, !sendData(task, identifier: identifier, data: body) {
      return
    }
    finishTask(task, identifier: identifier)
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
    return performCallback(identifier) {
      task.didReceive(response)
    }
  }

  private func sendData(
    _ task: WKURLSchemeTask,
    identifier: ObjectIdentifier,
    data: Data
  ) -> Bool {
    performCallback(identifier) {
      task.didReceive(data)
    }
  }

  private func finishTask(_ task: WKURLSchemeTask, identifier: ObjectIdentifier) {
    guard reserveCallback(identifier, finishing: true) else { return }
    defer { releaseCallback(identifier) }
    task.didFinish()
  }

  private func failTask(
    _ task: WKURLSchemeTask,
    identifier: ObjectIdentifier,
    error: Error
  ) {
    guard reserveCallback(identifier, finishing: true) else { return }
    defer { releaseCallback(identifier) }
    task.didFailWithError(error)
  }

  private func performCallback(
    _ identifier: ObjectIdentifier,
    action: () -> Void
  ) -> Bool {
    guard reserveCallback(identifier) else { return false }
    defer { releaseCallback(identifier) }
    action()
    return true
  }

  private func reserveCallback(
    _ identifier: ObjectIdentifier,
    finishing: Bool = false
  ) -> Bool {
    stateLock.synchronized {
      guard taskStates[identifier] == .active else { return false }
      callbackReservations[identifier, default: 0] += 1
      if finishing { taskStates[identifier] = .finished }
      return true
    }
  }

  private func releaseCallback(_ identifier: ObjectIdentifier) {
    stateLock.synchronized {
      let remaining = (callbackReservations[identifier] ?? 1) - 1
      if remaining > 0 {
        callbackReservations[identifier] = remaining
      } else {
        callbackReservations.removeValue(forKey: identifier)
      }
    }
  }

  private func isActive(_ identifier: ObjectIdentifier) -> Bool {
    stateLock.synchronized {
      taskStates[identifier] == .active
    }
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
