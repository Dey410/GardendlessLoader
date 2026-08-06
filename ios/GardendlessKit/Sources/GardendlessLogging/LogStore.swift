import Foundation

/// Local-only structured event store writing schema v1 JSONL files with
/// rotation, redaction, drop protection, and session lifecycle markers.
public final class LogStore {
  private let queue = DispatchQueue(label: "gardendless.app-log", qos: .utility)
  private let stateLock = NSLock()
  private let logsDirectory: URL
  private let recentCapacity: Int
  private let segmentBytes: Int
  private let maxEventBytes: Int
  private let pendingSoftLimit: Int
  private let pendingHardLimit: Int

  private var initialized = false
  private var pending = 0
  private var sequence = 0
  private var segment = 0
  private var recent: [[String: Any]] = []
  private var dropped: [String: Int] = [:]
  private var writeFailureCount = 0
  private var degraded = false
  private var startedAt = ProcessInfo.processInfo.systemUptime
  private var currentFile: URL?
  private var handle: FileHandle?
  private var markerFile: URL!
  public private(set) var appSessionId = "unavailable"

  public init(
    directory: URL,
    recentCapacity: Int = 500,
    segmentBytes: Int = 2 * 1024 * 1024,
    maxEventBytes: Int = 16 * 1024,
    pendingSoftLimit: Int = 1000,
    pendingHardLimit: Int = 1100
  ) {
    logsDirectory = directory
    self.recentCapacity = recentCapacity
    self.segmentBytes = segmentBytes
    self.maxEventBytes = maxEventBytes
    self.pendingSoftLimit = pendingSoftLimit
    self.pendingHardLimit = pendingHardLimit
  }

  public func initialize() {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard !initialized else { return }
    initialized = true
    markerFile = logsDirectory.appendingPathComponent("active-session.json")
    let previous = readPreviousSession()
    appSessionId = Self.newSessionId()
    startedAt = ProcessInfo.processInfo.systemUptime
    do {
      try FileManager.default.createDirectory(
        at: logsDirectory,
        withIntermediateDirectories: true
      )
      try JSONSerialization.data(
        withJSONObject: ["appSessionId": appSessionId]
      )
      .write(to: markerFile, options: .atomic)
      cleanup()
    } catch {
      markDegraded()
    }
    emitImmediate([
      "source": "ios",
      "level": "INFO",
      "category": "app.lifecycle",
      "event": "app_session_started",
      "outcome": "started",
      "context": [
        "platform": "ios",
        "appVersion": Bundle.main.object(
          forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown",
        "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
      ],
    ])
    if let previous, previous != appSessionId {
      let previousLast = readLastEvent(sessionId: previous)
      emitImmediate([
        "source": "ios",
        "level": "WARN",
        "category": "app.lifecycle",
        "event": "previous_run_unclean_shutdown",
        "outcome": "observed",
        "code": "previous_run_unclean_shutdown",
        "context": [
          "previousAppSessionId": previous,
          "previousLastEvent": previousLast?["event"] as? String ?? "unknown",
          "previousLastCode": previousLast?["code"] as? String ?? "none",
          "previousLastTimestamp":
            previousLast?["timestampUtc"] as? String ?? "unknown",
        ],
      ])
    }
  }

  public func emit(_ event: [String: Any]) {
    let level = Self.level(event["level"] as? String)
    stateLock.lock()
    if pending >= pendingHardLimit
        || (pending >= pendingSoftLimit && level != "ERROR" && level != "FATAL") {
      dropped[level, default: 0] += 1
      stateLock.unlock()
      return
    }
    pending += 1
    stateLock.unlock()
    queue.async { [weak self] in
      guard let self else { return }
      self.emitImmediate(event)
      self.stateLock.lock()
      self.pending -= 1
      self.stateLock.unlock()
    }
  }

  @discardableResult
  public func flush(timeout: TimeInterval) -> Bool {
    let group = DispatchGroup()
    group.enter()
    queue.async { [weak self] in
      try? self?.handle?.synchronizeFile()
      group.leave()
    }
    return group.wait(timeout: .now() + timeout) == .success
  }

  public func endSession() {
    emit(
      [
        "source": "ios",
        "level": "INFO",
        "category": "app.lifecycle",
        "event": "app_session_ended",
        "outcome": "succeeded",
      ]
    )
    _ = flush(timeout: 0.5)
    queue.sync {
      try? handle?.close()
      handle = nil
      try? FileManager.default.removeItem(at: markerFile)
    }
  }

  public func snapshot(limit: Int = 500) -> [String: Any] {
    queue.sync {
      let files = (
        try? FileManager.default.contentsOfDirectory(
          at: logsDirectory,
          includingPropertiesForKeys: [.fileSizeKey]
        )
      ) ?? []
      let total = files.reduce(0) { value, url in
        value
          + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
      }
      return [
        "appSessionId": appSessionId,
        "persisting": !degraded,
        "degraded": degraded,
        "logDirectory": logsDirectory.path,
        "totalBytes": total,
        "writeFailureCount": writeFailureCount,
        "droppedByLevel": dropped,
        "events": Array(recent.suffix(max(1, min(recentCapacity, limit)))),
      ]
    }
  }

  public func deleteHistory() {
    _ = flush(timeout: 0.5)
    queue.async { [weak self] in
      guard let self else { return }
      let currentPrefix = "app-\(self.appSessionId)-"
      let files = (
        try? FileManager.default.contentsOfDirectory(
          at: self.logsDirectory,
          includingPropertiesForKeys: nil
        )
      ) ?? []
      for file in files
      where file.pathExtension == "jsonl"
        && !file.lastPathComponent.hasPrefix(currentPrefix) {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }

  private func emitImmediate(_ input: [String: Any]) {
    sequence += 1
    var value: [String: Any] = [
      "schemaVersion": 1,
      "timestampUtc": Self.dateFormatter.string(from: Date()),
      "monotonicMs": Int(
        (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
      ),
      "sequence": sequence,
      "level": Self.level(input["level"] as? String),
      "source": Self.identifier(input["source"] as? String, fallback: "ios"),
      "category": Self.identifier(
        input["category"] as? String,
        fallback: "unknown"
      ),
      "event": Self.identifier(
        input["event"] as? String,
        fallback: "unknown_event"
      ),
      "outcome": Self.identifier(
        input["outcome"] as? String,
        fallback: "observed"
      ),
      "appSessionId": appSessionId,
    ]
    for key in ["code", "message", "gameSessionId", "operationId"] {
      if let text = input[key] as? String {
        value[key] = Self.sanitize(
          text,
          limit: key == "message" ? 2048 : 256
        )
      }
    }
    if let duration = input["durationMs"] as? NSNumber {
      value["durationMs"] = duration
    }
    if let context = input["context"] as? [String: Any] {
      value["context"] = Self.sanitizeMap(context)
    }
    if let error = input["error"] as? [String: Any] {
      value["error"] = Self.sanitizeMap(error)
    }
    guard var data = try? JSONSerialization.data(withJSONObject: value) else {
      return
    }
    if data.count > maxEventBytes {
      value.removeValue(forKey: "context")
      value["message"] = "Log event exceeded \(maxEventBytes) bytes and was truncated"
      data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
    }
    recent.append(value)
    if recent.count > recentCapacity {
      recent.removeFirst(recent.count - recentCapacity)
    }
    guard !degraded else { return }
    do {
      try ensureHandle(nextBytes: data.count + 1)
      handle?.seekToEndOfFile()
      handle?.write(data)
      handle?.write(Data([0x0a]))
      if value["level"] as? String == "ERROR"
          || value["level"] as? String == "FATAL" {
        handle?.synchronizeFile()
      }
    } catch {
      markDegraded()
    }
  }

  private func ensureHandle(nextBytes: Int) throws {
    let size = currentFile.flatMap {
      try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
    } ?? 0
    if handle == nil || size + nextBytes > segmentBytes {
      try? handle?.close()
      let file = logsDirectory.appendingPathComponent(
        "app-\(appSessionId)-\(String(format: "%03d", segment)).jsonl"
      )
      segment += 1
      if !FileManager.default.fileExists(atPath: file.path) {
        FileManager.default.createFile(atPath: file.path, contents: nil)
      }
      currentFile = file
      handle = try FileHandle(forWritingTo: file)
    }
  }

  private func cleanup() {
    let manager = FileManager.default
    var files = (
      try? manager.contentsOfDirectory(
        at: logsDirectory,
        includingPropertiesForKeys: [
          .contentModificationDateKey,
          .fileSizeKey,
        ]
      )
    ) ?? []
      .filter { $0.pathExtension == "jsonl" }
    let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
    for file in files
    where modificationDate(file, fallback: .distantFuture) < cutoff {
      try? manager.removeItem(at: file)
    }
    files = files.filter { manager.fileExists(atPath: $0.path) }

    let grouped = Dictionary(grouping: files) { file in
      file.lastPathComponent.replacingOccurrences(
        of: "-\\d{3}\\.jsonl$",
        with: "",
        options: .regularExpression
      )
    }
    let ordered = grouped.values.sorted {
      latestModificationDate($0) > latestModificationDate($1)
    }
    for group in ordered.dropFirst(5) {
      for file in group {
        try? manager.removeItem(at: file)
      }
    }
    var remaining = files.filter { manager.fileExists(atPath: $0.path) }
      .sorted { modificationDate($0, fallback: .distantPast)
        < modificationDate($1, fallback: .distantPast) }
    var total = remaining.reduce(0) { $0 + fileSize($1) }
    while total > 10 * 1024 * 1024, let file = remaining.first {
      total -= fileSize(file)
      try? manager.removeItem(at: file)
      remaining.removeFirst()
    }
  }

  private func markDegraded() {
    degraded = true
    writeFailureCount += 1
    try? handle?.close()
    handle = nil
  }

  private func readPreviousSession() -> String? {
    guard let data = try? Data(contentsOf: markerFile),
          let value = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
      return nil
    }
    return value["appSessionId"] as? String
  }

  private func readLastEvent(sessionId: String) -> [String: Any]? {
    let files = (
      try? FileManager.default.contentsOfDirectory(
        at: logsDirectory,
        includingPropertiesForKeys: nil
      )
    ) ?? []
    let candidates = files.filter {
      $0.lastPathComponent.hasPrefix("app-\(sessionId)-")
        && $0.pathExtension == "jsonl"
    }
    guard let file = candidates.max(by: {
      $0.lastPathComponent < $1.lastPathComponent
    }),
      let data = try? Data(contentsOf: file),
      let text = String(data: data, encoding: .utf8),
      let line = text.split(whereSeparator: \.isNewline).last,
      let lineData = String(line).data(using: .utf8),
      let value = try? JSONSerialization.jsonObject(with: lineData)
        as? [String: Any] else {
      return nil
    }
    return value
  }

  private static func sanitizeMap(_ value: [String: Any]) -> [String: Any] {
    let forbidden = try! NSRegularExpression(
      pattern: "password|passwd|secret|token|authorization|cookie|api.?key|private.?key",
      options: .caseInsensitive
    )
    var result: [String: Any] = [:]
    for (key, item) in value.prefix(32) {
      if forbidden.firstMatch(
        in: key,
        range: NSRange(key.startIndex..., in: key)
      ) != nil {
        continue
      }
      if let text = item as? String {
        result[key] = sanitize(text, limit: 4096)
      } else if item is NSNumber {
        result[key] = item
      }
    }
    return result
  }

  static func sanitize(_ value: String, limit: Int) -> String {
    var result = value.replacingOccurrences(
      of: "(?i)(token|authorization|cookie|password|passwd|secret|apiKey)\\s*[:=]\\s*[^\\s,;]+",
      with: "$1=<redacted>",
      options: .regularExpression
    )
    result = result.replacingOccurrences(
      of: "/(Users|home)/[^/\\s]+",
      with: "/<user-home>",
      options: .regularExpression
    )
    return result.count > limit
      ? String(result.prefix(limit)) + "...[truncated]"
      : result
  }

  private static func identifier(_ value: String?, fallback: String) -> String {
    guard let value,
          value.range(
            of: "^[A-Za-z0-9._-]{1,128}$",
            options: .regularExpression
          ) != nil else {
      return fallback
    }
    return value
  }

  private static func level(_ value: String?) -> String {
    let result = value?.uppercased() ?? "INFO"
    return ["DEBUG", "INFO", "WARN", "ERROR", "FATAL"].contains(result)
      ? result
      : "INFO"
  }

  private static func newSessionId() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6))"
  }

  private func modificationDate(_ file: URL, fallback: Date) -> Date {
    guard let values = try? file.resourceValues(
      forKeys: [.contentModificationDateKey]
    ),
      let date = values.contentModificationDate else {
      return fallback
    }
    return date
  }

  private func latestModificationDate(_ files: [URL]) -> Date {
    var latest = Date.distantPast
    for file in files {
      latest = max(latest, modificationDate(file, fallback: .distantPast))
    }
    return latest
  }

  private func fileSize(_ file: URL) -> Int {
    guard let values = try? file.resourceValues(forKeys: [.fileSizeKey]) else {
      return 0
    }
    return values.fileSize ?? 0
  }

  private static let dateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}
