import Foundation

/// Prepared session contract written by the Flutter launcher and consumed by
/// the native game host. Schema v1 is a frozen public contract.
public struct GameSession: Codable, Equatable {
  public static let schemaVersion = 1

  public let sessionId: String
  public let resourceRoot: URL
  public let entryURL: URL
  public let activationGeneration: Int
  public let hasGpNext: Bool
  public let gpNextCompatible: Bool
  public let gpNextVersion: String?
  public let watermarkEnabled: Bool
  public let autoCollectSunEnabled: Bool
  public let allowedRemoteHosts: Set<String>
  public let gpNextRoot: URL
  public let exportTemporaryRoot: URL

  public var appRoot: URL {
    resourceRoot.deletingLastPathComponent()
  }

  public init(
    sessionId: String,
    resourceRoot: URL,
    entryURL: URL,
    activationGeneration: Int,
    hasGpNext: Bool,
    gpNextCompatible: Bool,
    gpNextVersion: String?,
    watermarkEnabled: Bool,
    autoCollectSunEnabled: Bool,
    allowedRemoteHosts: Set<String>,
    gpNextRoot: URL,
    exportTemporaryRoot: URL
  ) {
    self.sessionId = sessionId
    self.resourceRoot = resourceRoot
    self.entryURL = entryURL
    self.activationGeneration = activationGeneration
    self.hasGpNext = hasGpNext
    self.gpNextCompatible = gpNextCompatible
    self.gpNextVersion = gpNextVersion
    self.watermarkEnabled = watermarkEnabled
    self.autoCollectSunEnabled = autoCollectSunEnabled
    self.allowedRemoteHosts = allowedRemoteHosts
    self.gpNextRoot = gpNextRoot
    self.exportTemporaryRoot = exportTemporaryRoot
  }
}

public enum GameSessionDecoder {
  public static func decode(_ value: Any?) throws -> GameSession {
    guard let json = value as? [String: Any] else {
      throw GameError.failed(.invalidSession, "Missing game session")
    }
    guard json["schemaVersion"] as? Int == GameSession.schemaVersion,
          json["platform"] as? String == "ios",
          json["origin"] as? String == GameOrigin.value else {
      throw GameError.failed(
        .invalidSession,
        "Game session schema, platform or origin mismatch"
      )
    }
    let sessionId = try requiredString(json, "sessionId")
    let resourceRoot = try requiredDirectoryURL(json, "resourceRoot")
    let entry = try requiredEntryURL(json)
    guard let generation = json["activationGeneration"] as? Int,
          generation >= 0 else {
      throw GameError.failed(.invalidSession, "Invalid activation generation")
    }
    let hosts = json["allowedRemoteHosts"] as? [String] ?? []
    guard hosts.allSatisfy(isValidRemoteHost) else {
      throw GameError.failed(.invalidSession, "Invalid remote host")
    }
    return GameSession(
      sessionId: sessionId,
      resourceRoot: resourceRoot,
      entryURL: entry,
      activationGeneration: generation,
      hasGpNext: try requiredBool(json, "hasGpNext"),
      gpNextCompatible: try requiredBool(json, "gpNextCompatible"),
      gpNextVersion: json["gpNextVersion"] as? String,
      watermarkEnabled: try requiredBool(json, "watermarkEnabled"),
      autoCollectSunEnabled: try requiredBool(json, "autoCollectSunEnabled"),
      allowedRemoteHosts: Set(hosts.map { $0.lowercased() }),
      gpNextRoot: try requiredDirectoryURL(json, "gpNextRoot"),
      exportTemporaryRoot: try requiredDirectoryURL(json, "exportTemporaryRoot")
    )
  }

  public static func isValidRemoteHost(_ value: String) -> Bool {
    let host = value.lowercased()
    guard !host.isEmpty, host.utf8.count <= 253 else { return false }
    return host.split(
      separator: ".",
      omittingEmptySubsequences: false
    ).allSatisfy { label in
      guard !label.isEmpty, label.utf8.count <= 63,
            label.first?.isLetter == true || label.first?.isNumber == true,
            label.last?.isLetter == true || label.last?.isNumber == true else {
        return false
      }
      return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
  }

  private static func requiredEntryURL(_ json: [String: Any]) throws -> URL {
    let raw = try requiredString(json, "entryUrl")
    guard let url = URL(string: raw),
          url.scheme == GameOrigin.scheme,
          url.host == GameOrigin.host else {
      throw GameError.failed(.invalidSession, "Entry URL escaped the game origin")
    }
    let path = url.path
    guard !path.hasPrefix("//"),
          !path.contains(".."),
          !path.contains("\\"),
          !path.contains("\0") else {
      throw GameError.failed(.invalidSession, "Entry URL path is unsafe")
    }
    return url
  }

  private static func requiredDirectoryURL(
    _ json: [String: Any],
    _ key: String
  ) throws -> URL {
    let raw = try requiredString(json, key)
    return URL(fileURLWithPath: raw, isDirectory: true)
  }

  private static func requiredString(_ json: [String: Any], _ key: String) throws -> String {
    guard let value = json[key] as? String, !value.isEmpty else {
      throw GameError.failed(.invalidSession, "\(key) is empty")
    }
    return value
  }

  private static func requiredBool(_ json: [String: Any], _ key: String) throws -> Bool {
    guard let value = json[key] as? Bool else {
      throw GameError.failed(.invalidSession, "\(key) is not a bool")
    }
    return value
  }
}
