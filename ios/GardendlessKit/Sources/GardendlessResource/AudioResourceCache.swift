import Foundation

public struct CachedAudioEntry {
  public let data: Data
  public let totalLength: Int64
  public let mimeType: String
  public let etag: String

  public init(data: Data, totalLength: Int64, mimeType: String, etag: String) {
    self.data = data
    self.totalLength = totalLength
    self.mimeType = mimeType
    self.etag = etag
  }
}

/// Bounded LRU cache for small, repeatedly requested audio files.
public final class AudioResourceCache {
  private struct Value {
    let entry: CachedAudioEntry
    var lastAccess: UInt64
  }

  private let lock = NSLock()
  private var values: [String: Value] = [:]
  private var totalBytes = 0
  private var clock: UInt64 = 0
  private let byteLimit: Int

  public init(byteLimit: Int) {
    self.byteLimit = byteLimit
  }

  public func entry(for path: String) -> CachedAudioEntry? {
    lock.lock()
    defer { lock.unlock() }
    guard var value = values[path] else { return nil }
    clock &+= 1
    value.lastAccess = clock
    values[path] = value
    return value.entry
  }

  public func insert(_ entry: CachedAudioEntry, for path: String) {
    lock.lock()
    defer { lock.unlock() }
    clock &+= 1
    values[path] = Value(entry: entry, lastAccess: clock)
    totalBytes += entry.data.count
    while totalBytes > byteLimit,
          let oldest = values.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
      values.removeValue(forKey: oldest.key)
      totalBytes -= oldest.value.entry.data.count
    }
  }

  public var byteCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return totalBytes
  }
}
