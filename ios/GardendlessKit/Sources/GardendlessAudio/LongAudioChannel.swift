import AVFoundation
import Foundation
import GardendlessCore
import SfxExceptionGuard
#if os(iOS)
import UIKit
#endif

public protocol LongAudioChannelDelegate: AnyObject {
  func longAudioChannelDidProduce(_ outcome: AudioOutcome)
}

/// Streaming pool for BGM, ambience and other continuous audio. Isolated
/// from the short-SFX engine and never preempted by it.
public final class LongAudioChannel: NSObject {
  private struct Stream {
    let requestId: String
    let nodeIndex: Int
    let player: AVAudioPlayerNode
    let varispeed: AVAudioUnitVarispeed
    let file: AVAudioFile
    let relativePath: String
    var volume: Float
    var rate: Double
    var loop: Bool
    var paused: Bool
    var stopped: Bool
    var generation: Int
    var pendingChunks: Int
    var reachedEOF: Bool
  }

  public weak var delegate: LongAudioChannelDelegate?
  private let sandbox: PathSandbox
  private let configuration: GameConfiguration
  private let onMetric: (String, [String: Any]) -> Void
  private let stateQueue = DispatchQueue(
    label: "io.github.dey410.gardendless.long-audio-state"
  )
  private let fileOpener = AudioFileOpener()

  private var engine: AVAudioEngine?
  private var nodes: [(player: AVAudioPlayerNode, varispeed: AVAudioUnitVarispeed)] = []
  private var availableNodeIndices: [Int] = []
  private var streams: [String: Stream] = [:]
  private var masterVolume: Float = 1
  private var stopped = false
  private var generationCounter = 0
  private let chunkDuration: TimeInterval = 2
  private let chunkReadAhead = 2

  public init(
    sandbox: PathSandbox,
    configuration: GameConfiguration = .default,
    onMetric: @escaping (String, [String: Any]) -> Void = { _, _ in }
  ) {
    self.sandbox = sandbox
    self.configuration = configuration
    self.onMetric = onMetric
    super.init()
  }

  public func play(_ request: AudioPlayRequest) {
    stateQueue.async { [weak self] in
      self?.enqueue(request)
    }
  }

  public func pause(requestId: String) {
    stateQueue.async { [weak self] in
      self?.pauseLocked(requestId: requestId)
    }
  }

  public func stop(requestId: String) {
    stateQueue.async { [weak self] in
      self?.stopStream(requestId: requestId, outcome: nil)
    }
  }

  public func release(requestId: String) {
    stateQueue.async { [weak self] in
      self?.stopStream(requestId: requestId, outcome: nil)
    }
  }

  public func seek(requestId: String, time: TimeInterval) {
    stateQueue.async { [weak self] in
      self?.seekLocked(requestId: requestId, time: time)
    }
  }

  public func setVolume(requestId: String, volume: Float) {
    stateQueue.async { [weak self] in
      guard var stream = self?.streams[requestId] else { return }
      stream.volume = max(0, min(1, volume))
      self?.streams[requestId] = stream
      stream.player.volume = stream.volume * (self?.masterVolume ?? 1)
    }
  }

  public func setLoop(requestId: String, loop: Bool) {
    stateQueue.async { [weak self] in
      guard var stream = self?.streams[requestId] else { return }
      stream.loop = loop
      self?.streams[requestId] = stream
    }
  }

  public func setRate(requestId: String, rate: Double) {
    stateQueue.async { [weak self] in
      guard var stream = self?.streams[requestId] else { return }
      stream.rate = max(0.25, min(4, rate))
      self?.streams[requestId] = stream
      stream.varispeed.rate = Float(stream.rate)
    }
  }

  public func setMasterVolume(_ volume: Float) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      self.masterVolume = max(0, min(1, volume))
      for stream in self.streams.values {
        stream.player.volume = stream.volume * self.masterVolume
      }
    }
  }

  public func stopAll(reason: String? = nil) {
    stateQueue.async { [weak self] in
      self?.stopAllLocked(reason: reason)
    }
  }

  public func isActive(requestId: String) -> Bool {
    stateQueue.sync {
      streams[requestId] != nil
    }
  }

  public func shutdown() {
    #if os(iOS)
    NotificationCenter.default.removeObserver(self)
    #endif
    stateQueue.sync {
      guard !stopped else { return }
      stopped = true
      stopAllLocked(reason: nil)
      engine?.stop()
      if let engine {
        for (player, varispeed) in nodes {
          engine.detach(player)
          engine.detach(varispeed)
        }
      }
      nodes.removeAll()
      availableNodeIndices.removeAll()
      engine = nil
    }
    fileOpener.cleanup()
  }

  private func enqueue(_ request: AudioPlayRequest) {
    guard !stopped else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "engine_stopped"))
      return
    }
    if let existing = streams[request.requestId] {
      if existing.paused, !existing.stopped {
        existing.player.play()
        var resumed = existing
        resumed.paused = false
        streams[request.requestId] = resumed
        if resumed.pendingChunks == 0 {
          ensureChunks(resumed)
        }
        metric("long_channel_resumed", path: existing.relativePath)
        return
      }
      stopStream(requestId: request.requestId, outcome: nil)
    }
    guard let relativePath = sandbox.relativePath(for: request.url) else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "invalid_url"))
      return
    }
    let ext = (relativePath as NSString).pathExtension.lowercased()
    guard AudioPlaybackLimits.supportedExtensions.contains(ext) else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "unsupported_container"))
      return
    }
    guard ensureEngineRunning() else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "engine_unavailable"))
      return
    }
    guard let nodeIndex = availableNodeIndices.first else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "long_channel_full"))
      return
    }
    guard let file = sandbox.resolve(relativePath) else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "file_unavailable"))
      return
    }
    let properties: (length: Int64, etag: String)
    do {
      properties = try sandbox.fileProperties(file)
    } catch {
      route(.init(kind: .silent, requestId: request.requestId, reason: "properties_failed"))
      return
    }
    guard properties.length > 0,
          properties.length <= configuration.longMaxBytes else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "size_limit"))
      return
    }
    let container: AudioContainer
    do {
      container = try AudioContainerDetector.detect(file)
    } catch {
      route(.init(kind: .silent, requestId: request.requestId, reason: "container_detect_failed"))
      return
    }
    guard container != .unsupported else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "unsupported_container"))
      return
    }
    let audioFile: AVAudioFile
    do {
      audioFile = try fileOpener.open(
        file,
        relativePath: relativePath,
        container: container
      )
    } catch {
      route(.init(kind: .silent, requestId: request.requestId, reason: "open_failed"))
      return
    }
    let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
    guard duration.isFinite,
          duration > 0,
          duration <= configuration.longMaxDuration else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "duration_limit"))
      return
    }
    let (player, varispeed) = nodes[nodeIndex]
    guard let engine else {
      route(.init(kind: .silent, requestId: request.requestId, reason: "engine_unavailable"))
      return
    }
    let exceptionReason = SfxExceptionGuard.runBlock {
      engine.disconnectNodeOutput(player)
      engine.disconnectNodeOutput(varispeed)
      engine.connect(
        player,
        to: varispeed,
        format: audioFile.processingFormat
      )
      engine.connect(
        varispeed,
        to: engine.mainMixerNode,
        format: audioFile.processingFormat
      )
    }
    if let exceptionReason {
      metric(
        "long_channel_schedule_failed",
        path: relativePath,
        details: ["reason": exceptionReason]
      )
      route(.init(kind: .silent, requestId: request.requestId, reason: "schedule_failed"))
      return
    }
    availableNodeIndices.removeFirst()
    let stream = Stream(
      requestId: request.requestId,
      nodeIndex: nodeIndex,
      player: player,
      varispeed: varispeed,
      file: audioFile,
      relativePath: relativePath,
      volume: request.volume,
      rate: max(0.25, min(4, request.rate)),
      loop: request.loop,
      paused: false,
      stopped: false,
      generation: 0,
      pendingChunks: 0,
      reachedEOF: false
    )
    player.volume = request.volume * masterVolume
    varispeed.rate = Float(stream.rate)
    streams[request.requestId] = stream
    schedule(stream, at: request.startTime)
    player.play()
    metric("long_channel_started", path: relativePath, details: [
      "durationMs": Int(duration * 1_000),
      "rate": stream.rate,
      "loop": stream.loop,
      "activeStreams": streams.count,
    ])
  }

  private func schedule(_ stream: Stream, at time: TimeInterval) {
    var updated = stream
    generationCounter &+= 1
    updated.generation = generationCounter
    streams[stream.requestId] = updated
    let sampleRate = stream.file.processingFormat.sampleRate
    let frame = min(
      max(AVAudioFramePosition(time * sampleRate), 0),
      stream.file.length
    )
    stream.file.framePosition = frame
    ensureChunks(updated)
  }

  private func ensureChunks(_ stream: Stream) {
    while let current = streams[stream.requestId],
          !current.stopped,
          !current.paused,
          current.generation == stream.generation,
          current.pendingChunks < chunkReadAhead {
      guard scheduleNextChunk(current) else {
        return
      }
    }
  }

  private func scheduleNextChunk(_ stream: Stream) -> Bool {
    while true {
      guard let current = streams[stream.requestId],
            !current.stopped,
            !current.paused,
            current.generation == stream.generation else {
        return false
      }
      let format = stream.file.processingFormat
      let chunkFrames = AVAudioFrameCount(
        max(1, Int(Double(format.sampleRate) * chunkDuration))
      )
      guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: chunkFrames
      ) else {
        stopStream(
          requestId: stream.requestId,
          outcome: .init(
            kind: .silent,
            requestId: stream.requestId,
            reason: "buffer_alloc_failed"
          )
        )
        return false
      }
      do {
        try stream.file.read(into: buffer, frameCount: chunkFrames)
      } catch {
        if stream.file.framePosition >= stream.file.length {
          var eofStream = stream
          eofStream.reachedEOF = true
          streams[stream.requestId] = eofStream
          if eofStream.loop {
            stream.file.framePosition = 0
            continue
          }
          if eofStream.pendingChunks > 0 {
            return false
          }
          stopStream(
            requestId: stream.requestId,
            outcome: .init(
              kind: .ended,
              requestId: stream.requestId,
              reason: nil
            )
          )
          return false
        }
        stopStream(
          requestId: stream.requestId,
          outcome: .init(
            kind: .silent,
            requestId: stream.requestId,
            reason: "read_failed"
          )
        )
        return false
      }
      if buffer.frameLength == 0 {
        var eofStream = stream
        eofStream.reachedEOF = true
        streams[stream.requestId] = eofStream
        if eofStream.loop {
          stream.file.framePosition = 0
          continue
        }
        if eofStream.pendingChunks > 0 {
          return false
        }
        stopStream(
          requestId: stream.requestId,
          outcome: .init(
            kind: .ended,
            requestId: stream.requestId,
            reason: nil
          )
        )
        return false
      }
      let requestId = stream.requestId
      let generation = stream.generation
      var scheduled = stream
      scheduled.pendingChunks += 1
      streams[stream.requestId] = scheduled
      let scheduleException = SfxExceptionGuard.runBlock {
        scheduled.player.scheduleBuffer(
          buffer,
          completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
          self?.stateQueue.async { [weak self] in
            self?.handleChunkCompletion(
              requestId: requestId,
              generation: generation
            )
          }
        }
      }
      if let scheduleException {
        metric(
          "long_channel_schedule_failed",
          path: stream.relativePath,
          details: ["reason": scheduleException]
        )
        stopStream(
          requestId: requestId,
          outcome: .init(
            kind: .silent,
            requestId: requestId,
            reason: "schedule_failed"
          )
        )
        return false
      }
      return true
    }
  }

  private func handleChunkCompletion(requestId: String, generation: Int) {
    guard var stream = streams[requestId],
          !stream.stopped,
          stream.generation == generation else {
      return
    }
    stream.pendingChunks = max(0, stream.pendingChunks - 1)
    streams[requestId] = stream
    if stream.paused {
      return
    }
    if stream.reachedEOF && !stream.loop && stream.pendingChunks == 0 {
      stopStream(
        requestId: requestId,
        outcome: .init(
          kind: .ended,
          requestId: requestId,
          reason: nil
        )
      )
      return
    }
    ensureChunks(stream)
  }

  private func pauseLocked(requestId: String) {
    guard var stream = streams[requestId], !stream.paused, !stream.stopped else {
      return
    }
    stream.paused = true
    streams[requestId] = stream
    stream.player.pause()
    metric("long_channel_paused", path: stream.relativePath)
  }

  private func seekLocked(requestId: String, time: TimeInterval) {
    guard var stream = streams[requestId], !stream.stopped else { return }
    let sampleRate = stream.file.processingFormat.sampleRate
    let fileLength = stream.file.length
    let frame = min(max(AVAudioFramePosition(time * sampleRate), 0), fileLength)
    generationCounter &+= 1
    stream.generation = generationCounter
    streams[requestId] = stream
    stream.player.stop()
    stream.pendingChunks = 0
    stream.reachedEOF = false
    stream.file.framePosition = frame
    schedule(stream, at: time)
    if !stream.paused {
      stream.player.play()
    }
    metric("long_channel_seek", path: stream.relativePath, details: [
      "timeMs": Int(time * 1_000),
    ])
  }

  private func stopStream(requestId: String, outcome: AudioOutcome?) {
    guard var stream = streams.removeValue(forKey: requestId) else { return }
    stream.stopped = true
    stream.player.stop()
    availableNodeIndices.append(stream.nodeIndex)
    if let outcome {
      route(outcome)
    }
  }

  private func stopAllLocked(reason: String?) {
    let identifiers = Array(streams.keys)
    for identifier in identifiers {
      let outcome = reason.map {
        AudioOutcome(kind: .stopped, requestId: identifier, reason: $0)
      }
      stopStream(requestId: identifier, outcome: outcome)
    }
    engine?.pause()
  }

  private func route(_ outcome: AudioOutcome) {
    let reason = outcome.reason ?? ""
    metric(
      "long_channel_\(outcome.kind.rawValue)",
      details: ["reason": reason]
    )
    delegate?.longAudioChannelDidProduce(outcome)
  }

  private func ensureEngineRunning() -> Bool {
    guard !stopped else { return false }
    if let engine, engine.isRunning {
      return true
    }
    #if os(iOS)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .ambient,
        mode: .default,
        options: [.mixWithOthers]
      )
      try session.setActive(true)
    } catch {
      metric("long_channel_engine_unavailable", details: [
        "reason": "session_start_failed",
      ])
      return false
    }
    #endif
    let preparedEngine: AVAudioEngine
    if let engine {
      preparedEngine = engine
    } else {
      let newEngine = AVAudioEngine()
      engine = newEngine
      nodes = (0..<AudioPlaybackLimits.longChannelCount).map { _ in
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        newEngine.attach(player)
        newEngine.attach(varispeed)
        return (player, varispeed)
      }
      availableNodeIndices = Array(0..<AudioPlaybackLimits.longChannelCount)
      observeLifecycle()
      preparedEngine = newEngine
    }
    _ = preparedEngine.mainMixerNode
    let exceptionReason = SfxExceptionGuard.runBlock {
      try? preparedEngine.start()
    }
    if let exceptionReason {
      metric("long_channel_engine_unavailable", details: [
        "reason": "engine_start_exception",
        "exception": exceptionReason,
      ])
      return false
    }
    return preparedEngine.isRunning
  }

  private func observeLifecycle() {
    #if os(iOS)
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(didEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(willEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(audioInterrupted(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(audioRouteChanged),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    #endif
  }

  #if os(iOS)
  @objc private func didEnterBackground() {
    stateQueue.async { [weak self] in
      self?.stopAllLocked(reason: "background")
    }
  }

  @objc private func willEnterForeground() {
    stateQueue.async { [weak self] in
      guard self?.engine != nil else { return }
      _ = self?.ensureEngineRunning()
    }
  }

  @objc private func audioInterrupted(_ notification: Notification) {
    let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
    if raw == AVAudioSession.InterruptionType.began.rawValue {
      stateQueue.async { [weak self] in
        self?.stopAllLocked(reason: "interruption")
      }
    } else {
      stateQueue.async { [weak self] in
        guard self?.engine != nil else { return }
        self?.engine?.stop()
        _ = self?.ensureEngineRunning()
      }
    }
  }

  @objc private func audioRouteChanged() {
    stateQueue.async { [weak self] in
      guard self?.engine != nil else { return }
      self?.stopAllLocked(reason: "route_changed")
      self?.engine?.stop()
      _ = self?.ensureEngineRunning()
    }
  }
  #endif

  private func metric(
    _ event: String,
    path: String? = nil,
    details: [String: Any] = [:]
  ) {
    var context = details
    if let path {
      context["urlHash"] = urlHash(path)
    }
    onMetric(event, context)
  }

  private func urlHash(_ value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }
}
