import Foundation

public enum AudioRole: String {
  case oneShot
  case continuous
}

public enum AudioOutcomeKind: String {
  case ended
  case silent
  case stopped
}

public struct AudioOutcome {
  public let kind: AudioOutcomeKind
  public let requestId: String
  public let reason: String?

  public init(kind: AudioOutcomeKind, requestId: String, reason: String? = nil) {
    self.kind = kind
    self.requestId = requestId
    self.reason = reason
  }
}

public struct AudioPlayRequest {
  public let requestId: String
  public let url: URL
  public let role: AudioRole
  public let kind: String?
  public let volume: Float
  public let loop: Bool
  public let rate: Double
  public let startTime: TimeInterval

  public init(
    requestId: String,
    url: URL,
    role: AudioRole,
    kind: String? = nil,
    volume: Float = 1,
    loop: Bool = false,
    rate: Double = 1,
    startTime: TimeInterval = 0
  ) {
    self.requestId = requestId
    self.url = url
    self.role = role
    self.kind = kind
    self.volume = max(0, min(1, volume))
    self.loop = loop
    self.rate = max(0.1, min(4, rate))
    self.startTime = max(0, startTime)
  }
}
