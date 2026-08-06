import AVFoundation
import Foundation
import GardendlessCore
import SfxExceptionGuard
#if os(iOS)
import UIKit
#endif

public protocol ShortSfxEngineDelegate: AnyObject {
  func shortSfxEngineDidProduce(_ outcome: AudioOutcome)
}

public enum NativeAudioDecision: Equatable {
  case native
  case silent(String)
}

/// Decodes and plays bounded one-shot sound effects natively on a fixed voice
/// pool. The pool preempts the oldest one-shot when full and never touches the
/// long-audio channel. Audio that cannot be played is reported as `silent` and
/// cached so repeated requests do not re-decode.
public final class ShortSfxEngine: NSObject {
  private enum DecodeOutcome {
    case buffer(AVAudioPCMBuffer, Int, TimeInterval, Int64)
    case silent(String, String)
  }

  private struct CachedBuffer {
    let buffer: AVAudioPCMBuffer
    let byteCount: Int
    var lastAccess: UInt64
    var retainCount: Int
  }

  private struct VoiceNode {
    let player: AVAudioPlayerNode
    let varispeed: AVAudioUnitVarispeed?
  }

  private struct Voice {
    let node: VoiceNode
    let url: URL
    let relativePath: String
    let volume: Float
    let rate: Double
    let startedAt: TimeInterval
    var paused: Bool
    let generation: Int
  }

  private struct PlayRequest {
    let requestId: String
    let url: URL
    let volume: Float
    let rate: Double
    let startTime: TimeInterval
    let requestedAt: TimeInterval
  }

  public weak var delegate: ShortSfxEngineDelegate?
  private let sandbox: PathSandbox
  private let configuration: GameConfiguration
  private let onMetric: (String, [String: Any]) -> Void
  private let decodeQueue: OperationQueue
  private let stateQueue = DispatchQueue(
    label: "io.github.dey410.gardendless.native-sfx-state"
  )
  private let fileOpener = AudioFileOpener()

  private var engine: AVAudioEngine?
  private var buffers: [String: CachedBuffer] = [:]
  private var inFlight: [String: [PlayRequest]] = [:]
  private var inFlightEtags: [String: String] = [:]
  private var etags: [String: String] = [:]
  private var activeVoices: [String: Voice] = [:]
  private var availableNodes: [VoiceNode] = []
  private var rejectionCache: [String: String] = [:]
  private var cacheBytes = 0
  private var cacheClock: UInt64 = 0
  private var masterVolume: Float = 1
  private var stopped = false
  private var voiceGeneration = 0

  public init(
    sandbox: PathSandbox,
    configuration: GameConfiguration = .default,
    onMetric: @escaping (String, [String: Any]) -> Void = { _, _ in }
  ) {
    self.sandbox = sandbox
    self.configuration = configuration
    self.onMetric = onMetric
    let queue = OperationQueue()
    queue.name = "io.github.dey410.gardendless.native-sfx-decode"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = configuration.audioQueueConcurrency
    decodeQueue = queue
    super.init()
  }

  public static func isNativeCandidate(
    relativePath: String,
    loop: Bool,
    playbackRate: Double
  ) -> Bool {
    guard !loop, playbackRate == 1 else { return false }
    let ext = (relativePath as NSString).pathExtension.lowercased()
    guard AudioPlaybackLimits.supportedExtensions.contains(ext) else {
      return false
    }
    let tokens = relativePath.lowercased().split(whereSeparator: {
      !$0.isLetter && !$0.isNumber
    })
    return !tokens.contains {
      AudioPlaybackLimits.excludedTokens.contains(String($0))
    }
  }

  /// Pure classification used before native decoding: only bounded, short
  /// audio is accepted; anything else is rejected.
  public static func classify(
    compressedBytes: Int64,
    duration: TimeInterval,
    configuration: GameConfiguration = .default
  ) -> NativeAudioDecision {
    guard compressedBytes > 0,
          compressedBytes <= configuration.compressedSfxByteLimit else {
      return .silent("compressed_size_limit")
    }
    guard duration.isFinite,
          duration > 0,
          duration <= configuration.maximumSfxDuration else {
      return .silent("duration_limit")
    }
    return .native
  }

  public func play(
    requestId: String,
    url: URL,
    volume: Float,
    rate: Double = 1,
    startTime: TimeInterval = 0
  ) {
    let request = PlayRequest(
      requestId: requestId,
      url: url,
      volume: max(0, min(1, volume)),
      rate: max(0.1, min(4, rate)),
      startTime: max(0, startTime),
      requestedAt: ProcessInfo.processInfo.systemUptime
    )
    stateQueue.async { [weak self] in
      self?.enqueue(request)
    }
  }

  public func pause(requestId: String) {
    stateQueue.async { [weak self] in
      guard var voice = self?.activeVoices[requestId], !voice.paused else {
        return
      }
      voice.paused = true
      self?.activeVoices[requestId] = voice
      voice.node.player.pause()
    }
  }

  public func stop(requestId: String) {
    stateQueue.async { [weak self] in
      self?.stopVoice(requestId: requestId, notifyEnded: false)
    }
  }

  public func release(requestId: String) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      self.stopVoice(requestId: requestId, notifyEnded: false)
      for path in Array(self.inFlight.keys) {
        self.inFlight[path]?.removeAll { $0.requestId == requestId }
      }
    }
  }

  public func seek(requestId: String, time: TimeInterval) {
    stateQueue.async { [weak self] in
      guard let self,
            let voice = self.activeVoices[requestId],
            let cached = self.buffers[voice.relativePath] else {
        return
      }
      self.stopVoice(requestId: requestId, notifyEnded: false)
      let request = PlayRequest(
        requestId: requestId,
        url: voice.url,
        volume: voice.volume,
        rate: voice.rate,
        startTime: time,
        requestedAt: ProcessInfo.processInfo.systemUptime
      )
      self.schedule(
        request,
        relativePath: voice.relativePath,
        cached: cached
      )
    }
  }

  public func setVolume(requestId: String, volume: Float) {
    stateQueue.async { [weak self] in
      guard let self,
            let voice = self.activeVoices[requestId] else {
        return
      }
      let normalized = max(0, min(1, volume))
      voice.node.player.volume = normalized * self.masterVolume
    }
  }

  public func setLoop(requestId: String, loop: Bool) {
    // One-shot voices never loop; the game routes looped audio to the long
    // channel. Kept as a no-op so the bridge protocol stays uniform.
  }

  public func setRate(requestId: String, rate: Double) {
    stateQueue.async { [weak self] in
      guard let self,
            let voice = self.activeVoices[requestId],
            let varispeed = voice.node.varispeed else {
        return
      }
      varispeed.rate = Float(max(0.25, min(4, rate)))
    }
  }

  public func stopAll() {
    stateQueue.async { [weak self] in
      self?.stopAllLocked(notifyEnded: false, stoppedReason: nil)
    }
  }

  public func setMasterVolume(_ volume: Float) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      self.masterVolume = max(0, min(1, volume))
      for voice in self.activeVoices.values {
        voice.node.player.volume = voice.volume * self.masterVolume
      }
    }
  }

  public func isActive(requestId: String) -> Bool {
    stateQueue.sync {
      activeVoices[requestId] != nil
        || inFlight.values.contains { $0.contains { $0.requestId == requestId } }
    }
  }

  public func shutdown() {
    #if os(iOS)
    NotificationCenter.default.removeObserver(self)
    #endif
    decodeQueue.cancelAllOperations()
    stateQueue.sync {
      guard !stopped else { return }
      stopped = true
      inFlight.removeAll()
      inFlightEtags.removeAll()
      etags.removeAll()
      stopAllLocked(notifyEnded: false, stoppedReason: nil)
      buffers.removeAll()
      cacheBytes = 0
      rejectionCache.removeAll()
      engine?.stop()
      if let engine {
        for node in availableNodes {
          engine.detach(node.player)
          if let varispeed = node.varispeed {
            engine.detach(varispeed)
          }
        }
      }
      availableNodes.removeAll()
      engine = nil
    }
    fileOpener.cleanup()
  }

  private func enqueue(_ request: PlayRequest) {
    guard !stopped,
          let relativePath = sandbox.relativePath(for: request.url) else {
      routeSilent(request, reason: "invalid_url")
      return
    }
    if let voice = activeVoices[request.requestId], voice.paused {
      voice.node.player.play()
      var resumed = voice
      resumed.paused = false
      activeVoices[request.requestId] = resumed
      return
    }
    let ext = (relativePath as NSString).pathExtension.lowercased()
    let tokens = relativePath.lowercased().split(whereSeparator: {
      !$0.isLetter && !$0.isNumber
    })
    guard AudioPlaybackLimits.supportedExtensions.contains(ext),
          !tokens.contains(where: {
            AudioPlaybackLimits.excludedTokens.contains(String($0))
          }) else {
      routeSilent(request, reason: "not_short_sfx")
      return
    }
    if let cached = buffers[relativePath] {
      cacheClock &+= 1
      var refreshed = cached
      refreshed.lastAccess = cacheClock
      buffers[relativePath] = refreshed
      metric("native_sfx_cache_hit", path: relativePath)
      schedule(request, relativePath: relativePath, cached: refreshed)
      return
    }
    let etag: String
    if let cachedEtag = etags[relativePath] {
      etag = cachedEtag
    } else if let file = sandbox.resolve(relativePath),
              let properties = try? sandbox.fileProperties(file) {
      etag = properties.etag
      etags[relativePath] = etag
    } else {
      etag = ""
    }
    if let cachedReason = rejectionCache[rejectionKey(
      role: "oneShot",
      path: relativePath,
      etag: etag
    )] {
      metric("native_sfx_rejected_cached", path: relativePath, details: [
        "reason": cachedReason,
      ])
      routeSilent(request, reason: cachedReason)
      return
    }
    if inFlight[relativePath] != nil {
      inFlight[relativePath]?.append(request)
      return
    }
    inFlight[relativePath] = [request]
    inFlightEtags[relativePath] = etag
    metric("native_sfx_decode_started", path: relativePath)
    let startedAt = ProcessInfo.processInfo.systemUptime
    decodeQueue.addOperation { [weak self] in
      guard let self else { return }
      let outcome = self.decode(relativePath: relativePath)
      self.stateQueue.async { [weak self] in
        self?.finishDecode(
          relativePath,
          outcome: outcome,
          startedAt: startedAt
        )
      }
    }
  }

  private func decode(
    relativePath: String
  ) -> DecodeOutcome {
    guard let file = sandbox.resolve(relativePath) else {
      return .silent("file_unavailable", "Audio resource is unavailable")
    }
    let properties: (length: Int64, etag: String)
    do {
      properties = try sandbox.fileProperties(file)
    } catch {
      return .silent("properties_failed", String(describing: error))
    }
    guard properties.length > 0 else {
      return .silent("invalid_audio", "Audio resource is empty")
    }
    let container: AudioContainer
    do {
      container = try AudioContainerDetector.detect(file)
    } catch {
      return .silent("container_detect_failed", String(describing: error))
    }
    guard container != .unsupported else {
      return .silent(
        "unsupported_container",
        "Audio container is unsupported"
      )
    }
    let audioFile: AVAudioFile
    do {
      audioFile = try fileOpener.open(
        file,
        relativePath: relativePath,
        container: container
      )
    } catch {
      return .silent("open_failed", String(describing: error))
    }
    let format = audioFile.processingFormat
    let duration = Double(audioFile.length) / format.sampleRate
    switch ShortSfxEngine.classify(
      compressedBytes: properties.length,
      duration: duration,
      configuration: configuration
    ) {
    case .silent(let reason):
      return .silent(reason, "Audio is not a native short SFX")
    case .native:
      break
    }
    guard audioFile.length <= Int64(AVAudioFrameCount.max),
          let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(audioFile.length)
          ) else {
      return .silent("buffer_alloc_failed", "Decoded audio is too long")
    }
    do {
      try audioFile.read(into: buffer)
    } catch {
      return .silent("decode_failed", String(describing: error))
    }
    let decodedBytes = Int(buffer.frameLength)
      * Int(buffer.format.channelCount)
      * MemoryLayout<Float>.size
    guard decodedBytes > 0,
          decodedBytes <= configuration.singleBufferByteLimit else {
      return .silent(
        "pcm_limit",
        "Decoded audio exceeds the per-sound limit"
      )
    }
    return .buffer(buffer, decodedBytes, duration, properties.length)
  }

  private func finishDecode(
    _ relativePath: String,
    outcome: DecodeOutcome,
    startedAt: TimeInterval
  ) {
    guard !stopped else { return }
    let pending = inFlight.removeValue(forKey: relativePath) ?? []
    let etag = inFlightEtags.removeValue(forKey: relativePath) ?? ""
    let decoded: (AVAudioPCMBuffer, Int, TimeInterval, Int64)
    switch outcome {
    case .silent(let reason, let message):
      let key = rejectionKey(
        role: "oneShot",
        path: relativePath,
        etag: etag
      )
      if isCacheable(reason: reason) {
        rejectionCache[key] = reason
        if rejectionCache.count > 512,
           let first = rejectionCache.keys.first {
          rejectionCache.removeValue(forKey: first)
        }
      }
      metric(
        "native_sfx_silent",
        path: relativePath,
        details: ["reason": reason, "message": message]
      )
      for request in pending {
        routeSilent(request, reason: reason)
      }
      return
    case let .buffer(buffer, byteCount, duration, compressedBytes):
      decoded = (buffer, byteCount, duration, compressedBytes)
    }
    makeCacheSpace(for: decoded.1)
    guard cacheBytes + decoded.1 <= configuration.pcmCacheByteLimit else {
      for request in pending {
        routeSilent(request, reason: "pcm_cache_full")
      }
      return
    }
    cacheClock &+= 1
    buffers[relativePath] = CachedBuffer(
      buffer: decoded.0,
      byteCount: decoded.1,
      lastAccess: cacheClock,
      retainCount: 0
    )
    cacheBytes += decoded.1
    metric("native_sfx_decode_finished", path: relativePath, details: [
      "compressedBytes": decoded.3,
      "durationMs": Int(decoded.2 * 1_000),
      "decodeMs": Int(
        (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
      ),
      "pcmCacheBytes": cacheBytes,
    ])
    for request in pending {
      if ProcessInfo.processInfo.systemUptime - request.requestedAt
          > AudioPlaybackLimits.stalePlayInterval {
        delegate?.shortSfxEngineDidProduce(
          .init(kind: .ended, requestId: request.requestId)
        )
      } else {
        schedule(request, relativePath: relativePath, cached: buffers[relativePath]!)
      }
    }
  }

  private func schedule(
    _ request: PlayRequest,
    relativePath: String,
    cached: CachedBuffer
  ) {
    guard let engine = ensureEngineRunning(), engine.isRunning else {
      routeSilent(request, reason: "engine_unavailable")
      return
    }
    stopVoice(requestId: request.requestId, notifyEnded: false)
    var node: VoiceNode?
    if request.rate != 1 {
      if let index = availableNodes.firstIndex(where: { $0.varispeed != nil }) {
        node = availableNodes.remove(at: index)
      }
    } else if let popped = availableNodes.popLast() {
      node = popped
    }
    if node == nil {
      // Preempt the oldest one-shot instead of dropping the new request.
      if let oldest = activeVoices.min(by: {
        $0.value.startedAt < $1.value.startedAt
      }) {
        stopVoice(requestId: oldest.key, notifyEnded: true)
        if request.rate != 1 {
          if let index = availableNodes.firstIndex(where: {
            $0.varispeed != nil
          }) {
            node = availableNodes.remove(at: index)
          }
        } else {
          node = availableNodes.popLast()
        }
      }
    }
    guard let selectedNode = node else {
      delegate?.shortSfxEngineDidProduce(
        .init(kind: .ended, requestId: request.requestId)
      )
      return
    }
    var cached = cached
    let exceptionReason = SfxExceptionGuard.runBlock {
      if let varispeed = selectedNode.varispeed {
        engine.disconnectNodeOutput(selectedNode.player)
        engine.disconnectNodeOutput(varispeed)
        engine.connect(
          selectedNode.player,
          to: varispeed,
          format: cached.buffer.format
        )
        engine.connect(
          varispeed,
          to: engine.mainMixerNode,
          format: cached.buffer.format
        )
        varispeed.rate = Float(max(0.25, min(4, request.rate)))
      } else {
        engine.disconnectNodeOutput(selectedNode.player)
        engine.connect(
          selectedNode.player,
          to: engine.mainMixerNode,
          format: cached.buffer.format
        )
      }
      cached.retainCount += 1
      self.buffers[relativePath] = cached
      self.voiceGeneration &+= 1
      let generation = self.voiceGeneration
      self.activeVoices[request.requestId] = Voice(
        node: selectedNode,
        url: request.url,
        relativePath: relativePath,
        volume: request.volume,
        rate: request.rate,
        startedAt: ProcessInfo.processInfo.systemUptime,
        paused: false,
        generation: generation
      )
      selectedNode.player.volume = request.volume * self.masterVolume
      selectedNode.player.scheduleBuffer(
        cached.buffer,
        completionCallbackType: .dataPlayedBack
      ) { [weak self] _ in
        self?.stateQueue.async { [weak self] in
          self?.completeVoice(
            requestId: request.requestId,
            generation: generation
          )
        }
      }
      selectedNode.player.play()
    }
    if let exceptionReason {
      activeVoices.removeValue(forKey: request.requestId)
      availableNodes.append(selectedNode)
      if var stored = buffers[relativePath] {
        stored.retainCount = max(0, stored.retainCount - 1)
        buffers[relativePath] = stored
      }
      evictBuffers()
      metric("native_sfx_schedule_failed", path: relativePath, details: [
        "reason": "schedule_exception",
        "exception": String(exceptionReason),
      ])
      routeSilent(request, reason: "schedule_failed")
      return
    }
    metric("native_sfx_play_scheduled", path: relativePath, details: [
      "scheduleMs": Int(
        (ProcessInfo.processInfo.systemUptime - request.requestedAt) * 1_000
      ),
      "activeNodes": activeVoices.count,
      "pcmCacheBytes": cacheBytes,
      "rate": request.rate,
    ])
  }

  private func completeVoice(requestId: String, generation: Int) {
    guard activeVoices[requestId]?.generation == generation else { return }
    stopVoice(requestId: requestId, notifyEnded: true)
  }

  private func stopVoice(requestId: String, notifyEnded: Bool) {
    guard let voice = activeVoices.removeValue(forKey: requestId) else {
      return
    }
    voice.node.player.stop()
    availableNodes.append(voice.node)
    let relativePath = voice.relativePath
    if var cached = buffers[relativePath] {
      cached.retainCount = max(0, cached.retainCount - 1)
      buffers[relativePath] = cached
    }
    evictBuffers()
    if notifyEnded {
      delegate?.shortSfxEngineDidProduce(
        .init(kind: .ended, requestId: requestId)
      )
    }
  }

  private func stopAllLocked(notifyEnded: Bool, stoppedReason: String?) {
    let identifiers = Array(activeVoices.keys)
    for identifier in identifiers {
      if notifyEnded {
        stopVoice(requestId: identifier, notifyEnded: true)
      } else if let stoppedReason {
        guard let voice = activeVoices.removeValue(forKey: identifier) else {
          continue
        }
        voice.node.player.stop()
        availableNodes.append(voice.node)
        if var cached = buffers[voice.relativePath] {
          cached.retainCount = max(0, cached.retainCount - 1)
          buffers[voice.relativePath] = cached
        }
        evictBuffers()
        delegate?.shortSfxEngineDidProduce(
          .init(
            kind: .stopped,
            requestId: identifier,
            reason: stoppedReason
          )
        )
      } else {
        stopVoice(requestId: identifier, notifyEnded: false)
      }
    }
  }

  private func evictBuffers() {
    makeCacheSpace(for: 0)
  }

  private func makeCacheSpace(for incomingBytes: Int) {
    while cacheBytes + incomingBytes > configuration.pcmCacheByteLimit,
          let oldest = buffers
            .filter({ $0.value.retainCount == 0 })
            .min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
      buffers.removeValue(forKey: oldest.key)
      cacheBytes -= oldest.value.byteCount
    }
  }

  private func routeSilent(_ request: PlayRequest, reason: String) {
    metric(
      "native_sfx_silent",
      path: sandbox.relativePath(for: request.url),
      details: ["reason": reason]
    )
    delegate?.shortSfxEngineDidProduce(
      .init(kind: .silent, requestId: request.requestId, reason: reason)
    )
  }

  private func rejectionKey(role: String, path: String, etag: String) -> String {
    "\(role)|\(path)|\(etag)"
  }

  private func isCacheable(reason: String) -> Bool {
    switch reason {
    case "unsupported_container",
         "compressed_size_limit",
         "duration_limit",
         "pcm_limit",
         "not_short_sfx",
         "invalid_audio":
      return true
    default:
      return false
    }
  }

  private func ensureEngineRunning() -> AVAudioEngine? {
    guard !stopped else { return nil }
    if let engine, engine.isRunning {
      return engine
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
      metric(
        "native_sfx_engine_unavailable",
        details: ["reason": "session_start_failed"]
      )
      return nil
    }
    #endif
    let preparedEngine: AVAudioEngine
    if let engine {
      preparedEngine = engine
    } else {
      let newEngine = AVAudioEngine()
      configureNodes(newEngine)
      engine = newEngine
      observeLifecycle()
      preparedEngine = newEngine
    }
    // Touch the main mixer so the output node is created before start().
    _ = preparedEngine.mainMixerNode
    guard startEngineSafely(preparedEngine) else {
      metric(
        "native_sfx_engine_unavailable",
        details: ["reason": "engine_start_failed"]
      )
      return nil
    }
    return preparedEngine
  }

  private func configureNodes(_ engine: AVAudioEngine) {
    for index in 0..<AudioPlaybackLimits.voicePoolSize {
      let player = AVAudioPlayerNode()
      engine.attach(player)
      if index < AudioPlaybackLimits.rateVoiceCount {
        let varispeed = AVAudioUnitVarispeed()
        engine.attach(varispeed)
        availableNodes.append(VoiceNode(player: player, varispeed: varispeed))
      } else {
        availableNodes.append(VoiceNode(player: player, varispeed: nil))
      }
    }
  }

  private func startEngineSafely(_ engine: AVAudioEngine) -> Bool {
    let exceptionReason = SfxExceptionGuard.runBlock {
      try? engine.start()
    }
    if let exceptionReason {
      metric("native_sfx_engine_unavailable", details: [
        "reason": "engine_start_exception",
        "exception": String(exceptionReason),
      ])
      return false
    }
    return engine.isRunning
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
      self?.stopAllLocked(notifyEnded: false, stoppedReason: "background")
      self?.engine?.pause()
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
        self?.stopAllLocked(notifyEnded: false, stoppedReason: "interruption")
        self?.engine?.pause()
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
      guard let self else { return }
      guard self.engine != nil else { return }
      self.stopAllLocked(notifyEnded: false, stoppedReason: "route_changed")
      self.engine?.stop()
      _ = self.ensureEngineRunning()
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
