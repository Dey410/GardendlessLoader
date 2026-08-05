import Foundation

/// In-memory structured event log. JSONL persistence lands with the Logging
/// capability milestone; the public shape already matches schema v1.
public final class LogStore {
  private let queue = DispatchQueue(label: "gardendless.logging")
  private let capacity: Int
  private var events: [[String: Any]] = []
  private var nextSequence = 1

  public init(capacity: Int = 500) {
    self.capacity = max(1, capacity)
  }

  public func emit(_ event: [String: Any]) {
    queue.sync {
      var value = event
      value["timestampUtc"] = ISO8601DateFormatter().string(from: Date())
      value["sequence"] = nextSequence
      nextSequence += 1
      events.append(value)
      if events.count > capacity {
        events.removeFirst(events.count - capacity)
      }
    }
  }

  public func snapshot(limit: Int = 500) -> [[String: Any]] {
    queue.sync {
      let safeLimit = min(max(1, limit), capacity)
      return Array(events.suffix(safeLimit))
    }
  }

  public func clear() {
    queue.sync {
      events.removeAll()
    }
  }
}
