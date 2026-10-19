import Foundation

/// Serializes task delivery with WebKit's start/stop, which always arrive on
/// the main thread. Off-main callbacks hop to the main thread and check state
/// there, so a stop can never interleave with a delivery and no lock is held
/// across a WKURLSchemeTask call (WebKit blocks off-main callers on the main
/// run loop, so holding a lock the main thread also takes would deadlock).
final class TaskCallbackGate {
  private enum State { case active, cancelled, finished }
  private let lock = NSLock()
  private var states: [ObjectIdentifier: State] = [:]

  func start(_ id: ObjectIdentifier) {
    lock.lock()
    defer { lock.unlock() }
    states[id] = .active
  }

  func cancel(_ id: ObjectIdentifier) {
    lock.lock()
    defer { lock.unlock() }
    if states[id] == .active { states[id] = .cancelled }
  }

  func remove(_ id: ObjectIdentifier) {
    lock.lock()
    defer { lock.unlock() }
    states.removeValue(forKey: id)
  }

  func isActive(_ id: ObjectIdentifier) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return states[id] == .active
  }

  func perform(_ id: ObjectIdentifier, finishing: Bool = false, action: () -> Void) -> Bool {
    guard Thread.isMainThread else {
      return DispatchQueue.main.sync {
        perform(id, finishing: finishing, action: action)
      }
    }
    guard claim(id, finishing: finishing) else { return false }
    action()
    return true
  }

  private func claim(_ id: ObjectIdentifier, finishing: Bool) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard states[id] == .active else { return false }
    if finishing { states[id] = .finished }
    return true
  }
}
