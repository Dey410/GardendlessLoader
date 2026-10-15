import Foundation

/// Holds cancellation and delivery under the same recursive lock. A stop on a
/// different thread waits for an in-flight callback; a callback may stop itself.
final class TaskCallbackGate {
  private enum State { case active, cancelled, finished }
  private let lock = NSRecursiveLock()
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
    lock.lock()
    defer { lock.unlock() }
    guard states[id] == .active else { return false }
    if finishing { states[id] = .finished }
    action()
    return true
  }
}
