import Foundation
import WebKit

/// Default-deny network rules: every HTTP(S) request is blocked unless its
/// host (or a subdomain) is explicitly allowlisted.
public enum NetworkPolicy {
  public static func encodedRules(for hosts: Set<String>) throws -> String {
    var rules: [[String: Any]] = [
      [
        "trigger": ["url-filter": "^http://"],
        "action": ["type": "block"],
      ],
      [
        "trigger": ["url-filter": "^https://"],
        "action": ["type": "block"],
      ],
    ]
    for host in hosts.sorted() {
      let escaped = NSRegularExpression.escapedPattern(for: host)
      rules.append([
        "trigger": [
          "url-filter": "^https://([a-z0-9-]+\\.)*\(escaped)[:/]",
          "url-filter-is-case-sensitive": true,
        ],
        "action": ["type": "ignore-previous-rules"],
      ])
    }
    let data = try JSONSerialization.data(withJSONObject: rules)
    guard let encoded = String(data: data, encoding: .utf8) else {
      throw GameError.failed(.invalidSession, "Unable to encode native network policy")
    }
    return encoded
  }

  public static func load(
    for session: GameSession,
    store: WKContentRuleListStore = WKContentRuleListStore.default(),
    completion: @escaping (Result<WKContentRuleList, Error>) -> Void
  ) {
    let hosts = session.allowedRemoteHosts.sorted()
    let identifier = "gardendless-network-v2-"
      + (hosts.isEmpty ? "offline" : hosts.joined(separator: "-"))
    store.lookUpContentRuleList(forIdentifier: identifier) { existing, _ in
      if let existing {
        completion(.success(existing))
        return
      }
      do {
        let encoded = try encodedRules(for: session.allowedRemoteHosts)
        store.compileContentRuleList(
          forIdentifier: identifier,
          encodedContentRuleList: encoded
        ) { compiled, error in
          if let compiled {
            completion(.success(compiled))
          } else {
            completion(
              .failure(
                error ?? GameError.failed(
                  .invalidSession,
                  "Unable to compile native network policy"
                )
              )
            )
          }
        }
      } catch {
        completion(.failure(error))
      }
    }
  }
}
