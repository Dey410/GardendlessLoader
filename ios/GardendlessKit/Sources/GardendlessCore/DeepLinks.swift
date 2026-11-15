import Foundation

/// pvzge: links that GP-Next's websites open: a Nest one-click install, a
/// Daily Level and a GitHub level. Only these three exact forms pass; GP-Next
/// validates them again before it acts on one.
public enum DeepLinks {
  private static let maximumLength = 4096

  /// The link itself when it is one of the three supported forms, else nil.
  public static func validate(_ raw: String) -> String? {
    guard !raw.isEmpty, raw.utf8.count <= maximumLength,
          raw.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }),
          let components = URLComponents(string: raw),
          components.scheme == "pvzge",
          components.user == nil, components.password == nil,
          components.port == nil, components.fragment == nil,
          let host = components.percentEncodedHost,
          raw.hasPrefix("pvzge://\(host)/"),
          let query = parseQuery(components.percentEncodedQuery) else {
      return nil
    }
    let path = components.percentEncodedPath
    let valid: Bool
    switch host {
    case "nest":
      valid = path == "/import" && Set(query.keys) == ["version"]
        && matches(query["version"], "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$")
    case "daily-level":
      valid = path == "/open" && Set(query.keys) == ["date", "slot", "slug"]
        && isDate(query["date"] ?? "")
        && matches(query["slot"], "^[0-9]{1,9}$")
        && (query["slug"]?.count ?? 0) <= 200
        && matches(query["slug"], "^[a-z0-9]+(?:-[a-z0-9]+)*$")
    case "github-level":
      valid = path == "/open" && Set(query.keys) == ["path", "sha"]
        && matches(query["sha"], "^[a-f0-9]{40}$")
        && isLevelPath(query["path"] ?? "")
    default:
      valid = false
    }
    return valid ? raw : nil
  }

  /// Each key once, decoded like URLSearchParams; nil for a malformed or repeated parameter.
  private static func parseQuery(_ raw: String?) -> [String: String]? {
    guard let raw, !raw.isEmpty else { return nil }
    var result: [String: String] = [:]
    for pair in raw.split(separator: "&", omittingEmptySubsequences: false) {
      guard let separator = pair.firstIndex(of: "="), separator != pair.startIndex,
            let key = decode(pair[..<separator]),
            let value = decode(pair[pair.index(after: separator)...]),
            result[key] == nil else { return nil }
      result[key] = value
    }
    return result
  }

  private static func decode(_ value: Substring) -> String? {
    value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
  }

  private static func matches(_ value: String?, _ pattern: String) -> Bool {
    guard let value else { return false }
    return value.range(of: pattern, options: .regularExpression) != nil
  }

  private static func isDate(_ value: String) -> Bool {
    guard matches(value, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") else { return false }
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]), parts[2] >= 1 else { return false }
    let year = parts[0]
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return parts[2] <= days[parts[1] - 1]
  }

  private static func isLevelPath(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 2048, value.lowercased().hasSuffix(".json"),
          !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f || $0 == "\\" }) else {
      return false
    }
    return !value.split(separator: "/", omittingEmptySubsequences: false)
      .contains { $0.isEmpty || $0 == "." || $0 == ".." }
  }
}

/// Validated links wait here, in the app process, until a game page takes
/// them with host:takeDeepLinks. A link nobody takes within ten minutes is
/// dropped so it cannot surprise a later game.
public final class DeepLinkInbox {
  public static let shared = DeepLinkInbox()
  private static let maximumLinks = 8
  private static let lifetime: TimeInterval = 10 * 60

  private let lock = NSLock()
  private var entries: [(url: String, receivedAt: TimeInterval)] = []
  private weak var listener: AnyObject?
  private var onAvailable: (() -> Void)?

  public init() {}

  /// The running game listens; it is told on the main queue that a link arrived.
  public func listen(_ owner: AnyObject, onAvailable: @escaping () -> Void) {
    lock.lock()
    listener = owner
    self.onAvailable = onAvailable
    lock.unlock()
  }

  public func stopListening(_ owner: AnyObject) {
    lock.lock()
    if listener === owner {
      listener = nil
      onAvailable = nil
    }
    lock.unlock()
  }

  public func offer(_ url: String) {
    lock.lock()
    prune()
    entries.removeAll { $0.url == url }
    entries.append((url, ProcessInfo.processInfo.systemUptime))
    if entries.count > Self.maximumLinks { entries.removeFirst(entries.count - Self.maximumLinks) }
    let notify = listener == nil ? nil : onAvailable
    lock.unlock()
    if let notify { DispatchQueue.main.async(execute: notify) }
  }

  public func drain() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    prune()
    let urls = entries.map(\.url)
    entries.removeAll()
    return urls
  }

  private func prune() {
    let now = ProcessInfo.processInfo.systemUptime
    entries.removeAll { now - $0.receivedAt > Self.lifetime }
  }
}
