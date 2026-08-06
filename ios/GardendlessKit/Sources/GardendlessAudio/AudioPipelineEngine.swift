import AVFoundation
import Foundation
import GardendlessCore

public protocol AudioPipelineEngineDelegate: AnyObject {
  func audioPipelineEngineDidProduce(_ outcome: AudioOutcome)
}

/// Routes requests between the short-SFX engine and the long-audio channel and
/// forwards their outcomes to a single delegate.
public final class AudioPipelineEngine: NSObject,
  ShortSfxEngineDelegate,
  LongAudioChannelDelegate {
  public weak var delegate: AudioPipelineEngineDelegate?
  private let short: ShortSfxEngine
  private let long: LongAudioChannel
  private let sandbox: PathSandbox
  private let configuration: GameConfiguration
  private let fileOpener = AudioFileOpener()
  private var routeCache: [String: AudioRole] = [:]

  public init(
    sandbox: PathSandbox,
    configuration: GameConfiguration = .default,
    onMetric: @escaping (String, [String: Any]) -> Void = { _, _ in }
  ) {
    self.sandbox = sandbox
    self.configuration = configuration
    short = ShortSfxEngine(
      sandbox: sandbox,
      configuration: configuration,
      onMetric: onMetric
    )
    long = LongAudioChannel(
      sandbox: sandbox,
      configuration: configuration,
      onMetric: onMetric
    )
    super.init()
    short.delegate = self
    long.delegate = self
  }

  public func play(_ request: AudioPlayRequest) {
    switch effectiveRole(for: request) {
    case .oneShot:
      short.play(
        requestId: request.requestId,
        url: request.url,
        volume: request.volume,
        rate: request.rate,
        startTime: request.startTime
      )
    case .continuous:
      long.play(request)
    }
  }

  func effectiveRole(for request: AudioPlayRequest) -> AudioRole {
    guard request.role == .continuous, !request.loop else {
      return request.role
    }
    guard let relativePath = sandbox.relativePath(for: request.url) else {
      return .continuous
    }
    if let cached = routeCache[relativePath] {
      return cached
    }
    let ext = (relativePath as NSString).pathExtension.lowercased()
    guard AudioPlaybackLimits.supportedExtensions.contains(ext) else {
      return .continuous
    }
    let tokens = relativePath.lowercased().split(whereSeparator: {
      !$0.isLetter && !$0.isNumber
    })
    guard !tokens.contains(where: {
      AudioPlaybackLimits.excludedTokens.contains(String($0))
    }) else {
      return .continuous
    }
    guard let file = sandbox.resolve(relativePath),
          let properties = try? sandbox.fileProperties(file),
          properties.length > 0,
          properties.length <= configuration.compressedSfxByteLimit else {
      return .continuous
    }
    let container = (try? AudioContainerDetector.detect(file)) ?? .unsupported
    guard container != .unsupported,
          let audioFile = try? fileOpener.open(
            file,
            relativePath: relativePath,
            container: container
          ) else {
      return .continuous
    }
    let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
    let role: AudioRole =
      duration <= configuration.maximumSfxDuration ? .oneShot : .continuous
    if routeCache.count >= 512 {
      routeCache.removeAll()
    }
    routeCache[relativePath] = role
    return role
  }

  public func pause(requestId: String) {
    if long.isActive(requestId: requestId) {
      long.pause(requestId: requestId)
    } else {
      short.pause(requestId: requestId)
    }
  }

  public func stop(requestId: String) {
    if long.isActive(requestId: requestId) {
      long.stop(requestId: requestId)
    } else {
      short.stop(requestId: requestId)
    }
  }

  public func seek(requestId: String, time: TimeInterval) {
    if long.isActive(requestId: requestId) {
      long.seek(requestId: requestId, time: time)
    } else {
      short.seek(requestId: requestId, time: time)
    }
  }

  public func setVolume(requestId: String, volume: Float) {
    if long.isActive(requestId: requestId) {
      long.setVolume(requestId: requestId, volume: volume)
    } else {
      short.setVolume(requestId: requestId, volume: volume)
    }
  }

  public func setLoop(requestId: String, loop: Bool) {
    if long.isActive(requestId: requestId) {
      long.setLoop(requestId: requestId, loop: loop)
    } else {
      short.setLoop(requestId: requestId, loop: loop)
    }
  }

  public func setRate(requestId: String, rate: Double) {
    if long.isActive(requestId: requestId) {
      long.setRate(requestId: requestId, rate: rate)
    } else {
      short.setRate(requestId: requestId, rate: rate)
    }
  }

  public func release(requestId: String) {
    if long.isActive(requestId: requestId) {
      long.release(requestId: requestId)
    } else {
      short.release(requestId: requestId)
    }
  }

  public func stopAll() {
    short.stopAll()
    long.stopAll()
  }

  public func setMasterVolume(_ volume: Float) {
    short.setMasterVolume(volume)
    long.setMasterVolume(volume)
  }

  public func shutdown() {
    short.shutdown()
    long.shutdown()
    fileOpener.cleanup()
  }

  public func shortSfxEngineDidProduce(_ outcome: AudioOutcome) {
    delegate?.audioPipelineEngineDidProduce(outcome)
  }

  public func longAudioChannelDidProduce(_ outcome: AudioOutcome) {
    delegate?.audioPipelineEngineDidProduce(outcome)
  }
}
