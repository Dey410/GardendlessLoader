import Foundation

/// Central limits and tuning values for the native game host.
public struct GameConfiguration: Equatable, Sendable {
  public static let `default` = GameConfiguration()

  public var resourceQueueConcurrency: Int
  public var audioQueueConcurrency: Int
  public var audioCacheByteLimit: Int
  public var maxExportBytes: Int
  public var maxExportChunkBytes: Int
  public var bridgeMaxMessageBytes: Int
  public var logSegmentBytes: Int
  public var logRecentEventCapacity: Int
  public var logMaxEventBytes: Int

  public init(
    resourceQueueConcurrency: Int = 6,
    audioQueueConcurrency: Int = 3,
    audioCacheByteLimit: Int = 24 * 1024 * 1024,
    maxExportBytes: Int = 512 * 1024 * 1024,
    maxExportChunkBytes: Int = 256 * 1024,
    bridgeMaxMessageBytes: Int = 1024 * 1024,
    logSegmentBytes: Int = 2 * 1024 * 1024,
    logRecentEventCapacity: Int = 500,
    logMaxEventBytes: Int = 16 * 1024
  ) {
    self.resourceQueueConcurrency = resourceQueueConcurrency
    self.audioQueueConcurrency = audioQueueConcurrency
    self.audioCacheByteLimit = audioCacheByteLimit
    self.maxExportBytes = maxExportBytes
    self.maxExportChunkBytes = maxExportChunkBytes
    self.bridgeMaxMessageBytes = bridgeMaxMessageBytes
    self.logSegmentBytes = logSegmentBytes
    self.logRecentEventCapacity = logRecentEventCapacity
    self.logMaxEventBytes = logMaxEventBytes
  }
}
