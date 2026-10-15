import Foundation

/// Central limits and tuning values for the native game host.
public struct GameConfiguration: Equatable, Sendable {
  public static let `default` = GameConfiguration()

  public var resourceQueueConcurrency: Int
  public var audioQueueConcurrency: Int
  public var audioCacheByteLimit: Int

  public init(
    resourceQueueConcurrency: Int = 6,
    audioQueueConcurrency: Int = 3,
    audioCacheByteLimit: Int = 24 * 1024 * 1024
  ) {
    self.resourceQueueConcurrency = resourceQueueConcurrency
    self.audioQueueConcurrency = audioQueueConcurrency
    self.audioCacheByteLimit = audioCacheByteLimit
  }
}
