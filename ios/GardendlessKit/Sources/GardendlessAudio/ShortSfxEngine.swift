import AVFoundation
import Foundation
import GardendlessCore
import SfxExceptionGuard

public protocol ShortSfxEngineDelegate: AnyObject {
  func shortSfxEngineDidProduce(_ result: ShortSfxEngine.PlayResult)
}

/// Decodes short non-BGM sound effects natively and falls back to WebKit
/// audio whenever decoding or engine scheduling fails.
public final class ShortSfxEngine: NSObject {
  public enum PlayResult {
    case ended(String)
    case fallback(String, String)
  }

  private struct CachedBuffer {
    let buffer: AVAudioPCMBuffer
    let byteCount: Int
    var lastAccess: UInt64
    var retainCount: Int
  }

  private struct Voice {
    let node: AVAudioPlayerNode
    let relativePath: String
    let volume: Float
  }

  private struct PlayRequest {
    let elementId: String
    let url: URL
    let volume: Float
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

  private var engine: AVAudioEngine?
  private var buffers: [String: CachedBuffer] = [:]
  private var inFlight: [String: [PlayRequest]] = [:]
  private var activeVoices: [String: Voice] = [:]
  private var availableNodes: [AVAudioPlayerNode] = []
  private var aliasFiles: [String: URL] = [:]
  private var cacheBytes = 0
  private var cacheClock: UInt64 = 0
  private var masterVolume: Float = 1
  private var stopped = false

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

  public func register(_ url: URL) {
    guard let relativePath = sandbox.relativePath(for: url) else { return }
    metric("native_sfx_registered", path: relativePath)
  }

  public func play(elementId: String, url: URL, volume: Float) {
    let request = PlayRequest(
      elementId: elementId,
      url: url,
      volume: max(0, min(1, volume)),
      requestedAt: ProcessInfo.processInfo.systemUptime
    )
    stateQueue.async { [weak self] in
      self?.enqueue(request)
    }
  }

  public func stop(elementId: String) {
    stateQueue.async { [weak self] in
      self?.stopVoice(elementId: elementId, notifyEnded: false)
    }
  }

  public func release(elementId: String) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      self.stopVoice(elementId: elementId, notifyEnded: false)
      for path in Array(self.inFlight.keys) {
        self.inFlight[path]?.removeAll { $0.elementId == elementId }
      }
    }
  }

  public func stopAll() {
    stateQueue.async { [weak self] in
      self?.stopAllLocked(notifyEnded: false)
    }
  }

  public func setMasterVolume(_ volume: Float) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      self.masterVolume = max(0, min(1, volume))
      for voice in self.activeVoices.values {
        voice.node.volume = voice.volume * self.masterVolume
      }
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
      stopAllLocked(notifyEnded: false)
      buffers.removeAll()
      cacheBytes = 0
      engine?.stop()
      if let engine {
        for node in availableNodes {
          engine.detach(node)
        }
      }
      availableNodes.removeAll()
      engine = nil
      for file in aliasFiles.values {
        try? FileManager.default.removeItem(at: file)
      }
      aliasFiles.removeAll()
    }
  }

  private func enqueue(_ request: PlayRequest) {
    guard !stopped,
          let relativePath = sandbox.relativePath(for: request.url) else {
      fallback(request, reason: "invalid_url")
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
      fallback(request, reason: "not_short_sfx")
      return
    }
    if var cached = buffers[relativePath] {
      cacheClock &+= 1
      cached.lastAccess = cacheClock
      buffers[relativePath] = cached
      metric("native_sfx_cache_hit", path: relativePath)
      schedule(request, relativePath: relativePath)
      return
    }
    if inFlight[relativePath] != nil {
      inFlight[relativePath]?.append(request)
      return
    }
    inFlight[relativePath] = [request]
    metric("native_sfx_decode_started", path: relativePath)
    let startedAt = ProcessInfo.processInfo.systemUptime
    decodeQueue.addOperation { [weak self] in
      guard let self else { return }
      do {
        let decoded = try self.decode(relativePath: relativePath)
        self.stateQueue.async { [weak self] in
          self?.finishDecode(
            relativePath,
            decoded: decoded,
            startedAt: startedAt
          )
        }
      } catch {
        self.stateQueue.async { [weak self] in
          self?.failDecode(
            relativePath,
            reason: String(describing: type(of: error))
          )
        }
      }
    }
  }

  private func decode(
    relativePath: String
  ) throws -> (AVAudioPCMBuffer, Int, TimeInterval, Int64) {
    guard let file = sandbox.resolve(relativePath) else {
      throw GameError.failed(.resourceNotFound, "Audio resource is unavailable")
    }
    let properties = try sandbox.fileProperties(file)
    guard properties.length > 0,
          properties.length <= configuration.compressedSfxByteLimit else {
      throw GameError.failed(
        .nativeAudioFailed,
        "Audio resource is not a short sound effect"
      )
    }
    let container = try AudioContainerDetector.detect(file)
    guard container != .unsupported else {
      throw GameError.failed(.nativeAudioFailed, "Audio container is unsupported")
    }
    let audioFile = try openAudioFile(
      file,
      relativePath: relativePath,
      container: container
    )
    let format = audioFile.processingFormat
    let duration = Double(audioFile.length) / format.sampleRate
    guard duration.isFinite, duration > 0,
          duration <= configuration.maximumSfxDuration,
          audioFile.length <= Int64(AVAudioFrameCount.max),
          let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(audioFile.length)
          ) else {
      throw GameError.failed(.nativeAudioFailed, "Decoded audio is too long")
    }
    try audioFile.read(into: buffer)
    let decodedBytes = Int(buffer.frameLength)
      * Int(buffer.format.channelCount)
      * MemoryLayout<Float>.size
    guard decodedBytes > 0,
          decodedBytes <= configuration.singleBufferByteLimit else {
      throw GameError.failed(
        .nativeAudioFailed,
        "Decoded audio exceeds the per-sound limit"
      )
    }
    return (buffer, decodedBytes, duration, properties.length)
  }

  private func openAudioFile(
    _ file: URL,
    relativePath: String,
    container: AudioContainer
  ) throws -> AVAudioFile {
    do {
      return try AVAudioFile(forReading: file)
    } catch {
      guard container == .m4a,
            file.pathExtension.lowercased() != "m4a" else {
        throw error
      }
      return try AVAudioFile(forReading: m4aAlias(file, relativePath: relativePath))
    }
  }

  private func m4aAlias(_ file: URL, relativePath: String) throws -> URL {
    if let existing = stateQueue.sync(execute: { aliasFiles[relativePath] }) {
      return existing
    }
    let properties = try sandbox.fileProperties(file)
    let directory = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    )[0]
      .appendingPathComponent("gardendless-native-sfx", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let identity = "\(sandbox.root.path):\(relativePath):\(properties.etag)"
    let alias = directory.appendingPathComponent("\(urlHash(identity)).m4a")
    if !FileManager.default.fileExists(atPath: alias.path) {
      do {
        try FileManager.default.linkItem(at: file, to: alias)
      } catch {
        try FileManager.default.copyItem(at: file, to: alias)
      }
    }
    stateQueue.async { [weak self] in
      self?.aliasFiles[relativePath] = alias
    }
    return alias
  }

  private func finishDecode(
    _ relativePath: String,
    decoded: (AVAudioPCMBuffer, Int, TimeInterval, Int64),
    startedAt: TimeInterval
  ) {
    guard !stopped else { return }
    let pending = inFlight.removeValue(forKey: relativePath) ?? []
    makeCacheSpace(for: decoded.1)
    guard cacheBytes + decoded.1 <= configuration.pcmCacheByteLimit else {
      for request in pending {
        fallback(request, reason: "pcm_cache_full")
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
        delegate?.shortSfxEngineDidProduce(.ended(request.elementId))
      } else {
        schedule(request, relativePath: relativePath)
      }
    }
  }

  private func failDecode(_ relativePath: String, reason: String) {
    let pending = inFlight.removeValue(forKey: relativePath) ?? []
    metric("native_sfx_decode_failed", path: relativePath, details: ["reason": reason])
    for request in pending {
      fallback(request, reason: "decode_failed")
    }
  }

  private func schedule(_ request: PlayRequest, relativePath: String) {
    guard var cached = buffers[relativePath] else {
      fallback(request, reason: "buffer_missing")
      return
    }
    guard let engine = ensureEngineRunning(), engine.isRunning else {
      fallback(request, reason: "engine_unavailable")
      return
    }
    stopVoice(elementId: request.elementId, notifyEnded: false)
    guard let node = availableNodes.popLast() else {
      delegate?.shortSfxEngineDidProduce(.ended(request.elementId))
      return
    }
    let exceptionReason = SfxExceptionGuard.runBlock {
      engine.disconnectNodeOutput(node)
      engine.connect(node, to: engine.mainMixerNode, format: cached.buffer.format)
      cached.retainCount += 1
      buffers[relativePath] = cached
      activeVoices[request.elementId] = Voice(
        node: node,
        relativePath: relativePath,
        volume: request.volume
      )
      node.volume = request.volume * masterVolume
      node.scheduleBuffer(
        cached.buffer,
        completionCallbackType: .dataPlayedBack
      ) { [weak self] _ in
        self?.stateQueue.async { [weak self] in
          self?.completeVoice(elementId: request.elementId)
        }
      }
      node.play()
    }
    if let exceptionReason {
      activeVoices.removeValue(forKey: request.elementId)
      availableNodes.append(node)
      if var stored = buffers[relativePath] {
        stored.retainCount = max(0, stored.retainCount - 1)
        buffers[relativePath] = stored
      }
      evictBuffers()
      metric("native_sfx_fallback", path: relativePath, details: [
        "reason": "schedule_exception",
        "exception": String(exceptionReason),
      ])
      fallback(request, reason: "schedule_failed")
      return
    }
    metric("native_sfx_play_scheduled", path: relativePath, details: [
      "scheduleMs": Int(
        (ProcessInfo.processInfo.systemUptime - request.requestedAt) * 1_000
      ),
      "activeNodes": activeVoices.count,
      "pcmCacheBytes": cacheBytes,
    ])
  }

  private func completeVoice(elementId: String) {
    guard activeVoices[elementId] != nil else { return }
    stopVoice(elementId: elementId, notifyEnded: true)
  }

  private func stopVoice(elementId: String, notifyEnded: Bool) {
    guard let voice = activeVoices.removeValue(forKey: elementId) else {
      return
    }
    voice.node.stop()
    availableNodes.append(voice.node)
    if var cached = buffers[voice.relativePath] {
      cached.retainCount = max(0, cached.retainCount - 1)
      buffers[voice.relativePath] = cached
    }
    evictBuffers()
    if notifyEnded {
      delegate?.shortSfxEngineDidProduce(.ended(elementId))
    }
  }

  private func stopAllLocked(notifyEnded: Bool) {
    let identifiers = Array(activeVoices.keys)
    for identifier in identifiers {
      stopVoice(elementId: identifier, notifyEnded: notifyEnded)
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

  private func fallback(_ request: PlayRequest, reason: String) {
    metric(
      "native_sfx_fallback",
      path: sandbox.relativePath(for: request.url),
      details: ["reason": reason]
    )
    delegate?.shortSfxEngineDidProduce(.fallback(request.elementId, reason))
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
      metric("native_sfx_fallback", details: ["reason": "session_start_failed"])
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
      metric("native_sfx_fallback", details: ["reason": "engine_start_failed"])
      return nil
    }
    return preparedEngine
  }

  private func configureNodes(_ engine: AVAudioEngine) {
    for _ in 0..<AudioPlaybackLimits.nodeCount {
      let node = AVAudioPlayerNode()
      engine.attach(node)
      availableNodes.append(node)
    }
  }

  private func startEngineSafely(_ engine: AVAudioEngine) -> Bool {
    let exceptionReason = SfxExceptionGuard.runBlock {
      try? engine.start()
    }
    if let exceptionReason {
      metric("native_sfx_fallback", details: [
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
      self?.stopAllLocked(notifyEnded: false)
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
        self?.stopAllLocked(notifyEnded: false)
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
      self.stopAllLocked(notifyEnded: false)
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
