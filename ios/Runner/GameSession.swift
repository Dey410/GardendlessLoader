import Foundation
import WebKit

struct NativeGameSession {
  static let origin = "gardendless-game://localhost"

  let sessionId: String
  let resourceRoot: URL
  let entryURL: URL
  let activationGeneration: Int
  let hasGpNext: Bool
  let gpNextCompatible: Bool
  let gpNextVersion: String?
  let watermarkEnabled: Bool
  let allowedRemoteHosts: Set<String>
  let gpNextRoot: URL
  let exportTemporaryRoot: URL

  var appRoot: URL { resourceRoot.deletingLastPathComponent() }

  init(arguments: Any?) throws {
    guard let json = arguments as? [String: Any] else {
      throw GameSessionError.invalid("Missing game session")
    }
    guard json["schemaVersion"] as? Int == 1,
          json["platform"] as? String == "ios",
          json["origin"] as? String == Self.origin else {
      throw GameSessionError.invalid("Game session schema, platform or origin mismatch")
    }
    sessionId = try json.requiredString("sessionId")
    resourceRoot = URL(fileURLWithPath: try json.requiredString("resourceRoot"), isDirectory: true)
    guard let entry = URL(string: try json.requiredString("entryUrl")),
          entry.scheme == "gardendless-game", entry.host == "localhost" else {
      throw GameSessionError.invalid("Entry URL escaped the game origin")
    }
    entryURL = entry
    guard let generation = json["activationGeneration"] as? Int, generation >= 0 else {
      throw GameSessionError.invalid("Invalid activation generation")
    }
    activationGeneration = generation
    hasGpNext = try json.requiredBool("hasGpNext")
    gpNextCompatible = try json.requiredBool("gpNextCompatible")
    gpNextVersion = json["gpNextVersion"] as? String
    watermarkEnabled = try json.requiredBool("watermarkEnabled")
    let hosts = json["allowedRemoteHosts"] as? [String] ?? []
    guard hosts.allSatisfy(Self.isValidRemoteHost) else {
      throw GameSessionError.invalid("Invalid remote host")
    }
    allowedRemoteHosts = Set(hosts.map { $0.lowercased() })
    gpNextRoot = URL(fileURLWithPath: try json.requiredString("gpNextRoot"), isDirectory: true)
    exportTemporaryRoot = URL(
      fileURLWithPath: try json.requiredString("exportTemporaryRoot"),
      isDirectory: true
    )
  }

  private static func isValidRemoteHost(_ value: String) -> Bool {
    let host = value.lowercased()
    guard !host.isEmpty, host.utf8.count <= 253 else { return false }
    return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
      guard !label.isEmpty, label.utf8.count <= 63,
            label.first?.isLetter == true || label.first?.isNumber == true,
            label.last?.isLetter == true || label.last?.isNumber == true else {
        return false
      }
      return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
  }
}

enum NativeGameNetworkPolicy {
  static func encodedRules(for hosts: [String]) throws -> String {
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
      let escapedHost = NSRegularExpression.escapedPattern(for: host)
      rules.append([
        "trigger": [
          "url-filter": "^https://([a-z0-9-]+\\.)*\(escapedHost)[:/]",
          "url-filter-is-case-sensitive": true,
        ],
        "action": ["type": "ignore-previous-rules"],
      ])
    }
    let data = try JSONSerialization.data(withJSONObject: rules)
    guard let encoded = String(data: data, encoding: .utf8) else {
      throw GameSessionError.invalid("Unable to encode native network policy")
    }
    return encoded
  }

  static func load(
    for session: NativeGameSession,
    completion: @escaping (Result<WKContentRuleList, Error>) -> Void
  ) {
    let hosts = session.allowedRemoteHosts.sorted()
    let identifier = "gardendless-network-v2-" + (hosts.isEmpty ? "offline" : hosts.joined(separator: "-"))
    guard let store = WKContentRuleListStore.default() else {
      completion(.failure(GameSessionError.invalid("Native network policy store is unavailable")))
      return
    }
    store.lookUpContentRuleList(forIdentifier: identifier) { existing, _ in
      if let existing {
        completion(.success(existing))
        return
      }
      do {
        let encoded = try encodedRules(for: hosts)
        store.compileContentRuleList(
          forIdentifier: identifier,
          encodedContentRuleList: encoded
        ) { compiled, error in
          if let compiled {
            completion(.success(compiled))
          } else {
            completion(.failure(error ?? GameSessionError.invalid("Unable to compile native network policy")))
          }
        }
      } catch {
        completion(.failure(error))
      }
    }
  }
}

enum GameSessionError: Error, LocalizedError {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    }
  }
}

private extension Dictionary where Key == String, Value == Any {
  func requiredString(_ key: String) throws -> String {
    guard let value = self[key] as? String, !value.isEmpty else {
      throw GameSessionError.invalid("\(key) is empty")
    }
    return value
  }

  func requiredBool(_ key: String) throws -> Bool {
    guard let value = self[key] as? Bool else {
      throw GameSessionError.invalid("\(key) is not a bool")
    }
    return value
  }
}
