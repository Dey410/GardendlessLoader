import Foundation

/// How the game viewport fits the screen. The game shows 16:10 to 17:9 without
/// distortion and its whole picture at 17:9.
public enum GameScreenFit: String, Codable, Equatable {
  /// Clamps the viewport to 16:10–17:9: trims some of the picture for
  /// smaller black bars.
  case balanced
  /// Keeps the viewport at 17:9 so the whole picture shows, with larger
  /// black bars.
  case showAll
  /// Stretches the balanced viewport over the whole screen.
  case stretch
}

/// How touches drive the game.
public enum GameGestureMode: String, Codable, Equatable {
  /// Clicks the release point of a drag so it plants.
  case simulated
  /// Experimental: one-to-one mouse mapping with in-game drag and drop.
  case native
}

/// Prepared session contract written by the Flutter launcher and consumed by
/// the native game host. Schema v1 is a frozen public contract.
public struct GameSession: Codable, Equatable {
  public static let schemaVersion = 1

  public let packageId: String?
  public let sessionId: String
  public let resourceRoot: URL
  public let entryURL: URL
  public let activationGeneration: Int
  public let hasGpNext: Bool
  public let gpNextCompatible: Bool
  public let gpNextVersion: String?
  public let watermarkEnabled: Bool
  public let autoCollectSunEnabled: Bool
  public let detailedAudioDiagnosticsEnabled: Bool
  /// Share of the device pixel ratio the game canvas renders at; nil keeps
  /// the device's own ratio.
  public let renderScale: Double?
  public let screenFit: GameScreenFit
  public let gestureMode: GameGestureMode
  /// Records the touch adapter's trace into the logs.
  public let touchDiagnosticsEnabled: Bool
  /// Lines of the one-time gesture hint shown over the game; nil shows none.
  public let gestureHint: [String]?
  public let allowedRemoteHosts: Set<String>
  public let gpNextRoot: URL
  public let exportTemporaryRoot: URL

  public var appRoot: URL {
    resourceRoot.deletingLastPathComponent()
  }

  public init(
    sessionId: String,
    packageId: String? = nil,
    resourceRoot: URL,
    entryURL: URL,
    activationGeneration: Int,
    hasGpNext: Bool,
    gpNextCompatible: Bool,
    gpNextVersion: String?,
    watermarkEnabled: Bool,
    autoCollectSunEnabled: Bool,
    detailedAudioDiagnosticsEnabled: Bool = false,
    renderScale: Double? = nil,
    screenFit: GameScreenFit = .balanced,
    gestureMode: GameGestureMode = .simulated,
    touchDiagnosticsEnabled: Bool = false,
    gestureHint: [String]? = nil,
    allowedRemoteHosts: Set<String>,
    gpNextRoot: URL,
    exportTemporaryRoot: URL
  ) {
    self.packageId = packageId
    self.sessionId = sessionId
    self.resourceRoot = resourceRoot
    self.entryURL = entryURL
    self.activationGeneration = activationGeneration
    self.hasGpNext = hasGpNext
    self.gpNextCompatible = gpNextCompatible
    self.gpNextVersion = gpNextVersion
    self.watermarkEnabled = watermarkEnabled
    self.autoCollectSunEnabled = autoCollectSunEnabled
    self.detailedAudioDiagnosticsEnabled = detailedAudioDiagnosticsEnabled
    self.renderScale = renderScale
    self.screenFit = screenFit
    self.gestureMode = gestureMode
    self.touchDiagnosticsEnabled = touchDiagnosticsEnabled
    self.gestureHint = gestureHint
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
    let renderScale = json["renderScale"] as? Double
    if let renderScale, renderScale <= 0 {
      throw GameError.failed(.invalidSession, "Invalid render scale")
    }
    guard let screenFit = GameScreenFit(
      rawValue: json["screenFit"] as? String ?? GameScreenFit.balanced.rawValue
    ) else {
      throw GameError.failed(.invalidSession, "Invalid screen fit")
    }
    guard let gestureMode = GameGestureMode(
      rawValue: json["touchGestureMode"] as? String
        ?? GameGestureMode.simulated.rawValue
    ) else {
      throw GameError.failed(.invalidSession, "Invalid gesture mode")
    }
    let hosts = json["allowedRemoteHosts"] as? [String] ?? []
    guard hosts.allSatisfy(isValidRemoteHost) else {
      throw GameError.failed(.invalidSession, "Invalid remote host")
    }
    return GameSession(
      sessionId: sessionId,
      packageId: json["packageId"] as? String,
      resourceRoot: resourceRoot,
      entryURL: entry,
      activationGeneration: generation,
      hasGpNext: try requiredBool(json, "hasGpNext"),
      gpNextCompatible: try requiredBool(json, "gpNextCompatible"),
      gpNextVersion: json["gpNextVersion"] as? String,
      watermarkEnabled: try requiredBool(json, "watermarkEnabled"),
      autoCollectSunEnabled: try requiredBool(json, "autoCollectSunEnabled"),
      detailedAudioDiagnosticsEnabled:
        json["detailedAudioDiagnosticsEnabled"] as? Bool ?? false,
      renderScale: renderScale,
      screenFit: screenFit,
      gestureMode: gestureMode,
      touchDiagnosticsEnabled: json["touchDiagnosticsEnabled"] as? Bool ?? false,
      gestureHint: json["gestureHint"] as? [String],
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
