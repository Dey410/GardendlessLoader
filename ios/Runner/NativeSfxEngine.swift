import AVFoundation
import Foundation
import UIKit

protocol NativeSfxEngineDelegate: AnyObject {
  func nativeSfxEngineDidProduce(_ result: NativeSfxEngine.PlayResult)
}

final class NativeSfxEngine: NSObject {
  struct PlayRequest {
    let elementId: String
    let url: URL
    let volume: Float
    let requestedAt: TimeInterval
  }

  enum PlayResult {
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

  private var engine: AVAudioEngine?
  private let locator: GameResourceLocator
  private let decodeQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "io.github.dey410.gardendless.native-sfx-decode"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  private let stateQueue = DispatchQueue(label: "io.github.dey410.gardendless.native-sfx-state")
  weak var delegate: NativeSfxEngineDelegate?
  private let onMetric: (String, [String: Any]) -> Void
  private var buffers = [String: CachedBuffer]()
  private var inFlight = [String: [PlayRequest]]()
  private var activeVoices = [String: Voice]()
  private var availableNodes = [AVAudioPlayerNode]()
  private var aliasFiles = [String: URL]()
  private var cacheBytes = 0
  private var cacheClock: UInt64 = 0
  private var masterVolume: Float = 1
  private var stopped = false

  private let compressedByteLimit: Int64 = 256 * 1024
  private let pcmCacheByteLimit = 64 * 1024 * 1024
  private let singleBufferByteLimit = 4 * 1024 * 1024
  private let maximumDuration: TimeInterval = 10
  private let stalePlayInterval: TimeInterval = 0.15
  private let nodeCount = 16

  init(
    locator: GameResourceLocator,
    onMetric: @escaping (String, [String: Any]) -> Void
  ) {
    self.locator = locator
    self.onMetric = onMetric
    super.init()
  }

  func register(_ url: URL) {
    guard let relativePath = locator.relativePath(for: url) else { return }
    metric("native_sfx_registered", path: relativePath)
  }

  func play(elementId: String, url: URL, volume: Float) {
    let request = PlayRequest(
      elementId: elementId,
      url: url,
      volume: max(0, min(1, volume)),
      requestedAt: ProcessInfo.processInfo.systemUptime
    )
    stateQueue.async { [weak self] in self?.enqueue(request) }
  }

  func stop(elementId: String) {
    stateQueue.async { [weak self] in self?.stopVoice(elementId: elementId, notifyEnded: false) }
  }

  func release(elementId: String) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      stopVoice(elementId: elementId, notifyEnded: false)
      for path in Array(inFlight.keys) {
        inFlight[path]?.removeAll { $0.elementId == elementId }
      }
    }
  }

  func stopAll() {
    stateQueue.async { [weak self] in self?.stopAllLocked(notifyEnded: false) }
  }

  func setMasterVolume(_ volume: Float) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      masterVolume = max(0, min(1, volume))
      for voice in activeVoices.values { voice.node.volume = voice.volume * masterVolume }
    }
  }

  func shutdown() {
    NotificationCenter.default.removeObserver(self)
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
        for node in availableNodes { engine.detach(node) }
      }
      availableNodes.removeAll()
      engine = nil
      for file in aliasFiles.values { try? FileManager.default.removeItem(at: file) }
      aliasFiles.removeAll()
    }
  }

  private func configureNodes(_ engine: AVAudioEngine) {
    for _ in 0..<nodeCount {
      let node = AVAudioPlayerNode()
      engine.attach(node)
      engine.connect(node, to: engine.mainMixerNode, format: nil)
      availableNodes.append(node)
    }
  }

  private func observeLifecycle() {
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    center.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    center.addObserver(self, selector: #selector(audioRouteChanged), name: AVAudioSession.routeChangeNotification, object: nil)
  }

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
      guard engine != nil else { return }
      stopAllLocked(notifyEnded: false)
      engine?.stop()
      _ = ensureEngineRunning()
    }
  }

  private func ensureEngineRunning() -> AVAudioEngine? {
    guard !stopped else { return nil }
    if let engine, engine.isRunning { return engine }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      if engine == nil {
        let preparedEngine = AVAudioEngine()
        configureNodes(preparedEngine)
        engine = preparedEngine
        observeLifecycle()
      }
      guard let engine else { return nil }
      try engine.start()
      return engine
    } catch {
      metric("native_sfx_fallback", details: ["reason": "engine_start_failed"])
      return nil
    }
  }

  private func enqueue(_ request: PlayRequest) {
    guard !stopped, let relativePath = locator.relativePath(for: request.url) else {
      fallback(request, reason: "invalid_url")
      return
    }
    let ext = (relativePath as NSString).pathExtension.lowercased()
    let tokens = relativePath.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    guard ["mp3", "m4a"].contains(ext),
          !tokens.contains("bgm"), !tokens.contains("music") else {
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
        let decoded = try decode(relativePath: relativePath)
        stateQueue.async { [weak self] in
          self?.finishDecode(relativePath, decoded: decoded, startedAt: startedAt)
        }
      } catch {
        stateQueue.async { [weak self] in
          self?.failDecode(relativePath, reason: String(describing: type(of: error)))
        }
      }
    }
  }

  private func decode(relativePath: String) throws -> (AVAudioPCMBuffer, Int, TimeInterval, Int64) {
    guard let file = locator.resolve(relativePath) else {
      throw GameSessionError.invalid("Audio resource is unavailable")
    }
    let properties = try locator.fileProperties(file)
    guard properties.length > 0, properties.length <= compressedByteLimit else {
      throw GameSessionError.invalid("Audio resource is not a short sound effect")
    }
    let container = try locator.audioContainer(file)
    guard container != .unsupported else {
      throw GameSessionError.invalid("Audio container is unsupported")
    }
    let audioFile = try openAudioFile(file, relativePath: relativePath, container: container)
    let format = audioFile.processingFormat
    let duration = Double(audioFile.length) / format.sampleRate
    guard duration.isFinite, duration > 0, duration <= maximumDuration,
          audioFile.length <= Int64(AVAudioFrameCount.max),
          let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(audioFile.length)
          ) else {
      throw GameSessionError.invalid("Decoded audio is too long")
    }
    try audioFile.read(into: buffer)
    let decodedBytes = Int(buffer.frameLength) * Int(buffer.format.channelCount) * MemoryLayout<Float>.size
    guard decodedBytes > 0, decodedBytes <= singleBufferByteLimit else {
      throw GameSessionError.invalid("Decoded audio exceeds the per-sound limit")
    }
    return (buffer, decodedBytes, duration, properties.length)
  }

  private func openAudioFile(
    _ file: URL,
    relativePath: String,
    container: GameAudioContainer
  ) throws -> AVAudioFile {
    do {
      return try AVAudioFile(forReading: file)
    } catch {
      guard container == .m4a, file.pathExtension.lowercased() != "m4a" else { throw error }
      let alias = try m4aAlias(file, relativePath: relativePath)
      return try AVAudioFile(forReading: alias)
    }
  }

  private func m4aAlias(_ file: URL, relativePath: String) throws -> URL {
    if let existing = stateQueue.sync(execute: { aliasFiles[relativePath] }) { return existing }
    let properties = try locator.fileProperties(file)
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("gardendless-native-sfx", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let identity = "\(locator.root.path):\(relativePath):\(properties.etag)"
    let alias = directory.appendingPathComponent("\(urlHash(identity)).m4a")
    if !FileManager.default.fileExists(atPath: alias.path) {
      do {
        try FileManager.default.linkItem(at: file, to: alias)
      } catch {
        try FileManager.default.copyItem(at: file, to: alias)
      }
    }
    stateQueue.async { [weak self] in self?.aliasFiles[relativePath] = alias }
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
    guard cacheBytes + decoded.1 <= pcmCacheByteLimit else {
      for request in pending { fallback(request, reason: "pcm_cache_full") }
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
      "decodeMs": Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000),
      "pcmCacheBytes": cacheBytes,
    ])
    for request in pending {
      if ProcessInfo.processInfo.systemUptime - request.requestedAt > stalePlayInterval {
        delegate?.nativeSfxEngineDidProduce(.ended(request.elementId))
      } else {
        schedule(request, relativePath: relativePath)
      }
    }
  }

  private func failDecode(_ relativePath: String, reason: String) {
    let pending = inFlight.removeValue(forKey: relativePath) ?? []
    metric("native_sfx_decode_failed", path: relativePath, details: ["reason": reason])
    for request in pending { fallback(request, reason: "decode_failed") }
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
      delegate?.nativeSfxEngineDidProduce(.ended(request.elementId))
      return
    }
    cached.retainCount += 1
    buffers[relativePath] = cached
    activeVoices[request.elementId] = Voice(
      node: node,
      relativePath: relativePath,
      volume: request.volume
    )
    node.volume = request.volume * masterVolume
    node.scheduleBuffer(cached.buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      self?.stateQueue.async { [weak self] in self?.completeVoice(elementId: request.elementId) }
    }
    node.play()
    metric("native_sfx_play_scheduled", path: relativePath, details: [
      "scheduleMs": Int((ProcessInfo.processInfo.systemUptime - request.requestedAt) * 1_000),
      "activeNodes": activeVoices.count,
      "pcmCacheBytes": cacheBytes,
    ])
  }

  private func completeVoice(elementId: String) {
    guard activeVoices[elementId] != nil else { return }
    stopVoice(elementId: elementId, notifyEnded: true)
  }

  private func stopVoice(elementId: String, notifyEnded: Bool) {
    guard let voice = activeVoices.removeValue(forKey: elementId) else { return }
    voice.node.stop()
    availableNodes.append(voice.node)
    if var cached = buffers[voice.relativePath] {
      cached.retainCount = max(0, cached.retainCount - 1)
      buffers[voice.relativePath] = cached
    }
    evictBuffers()
    if notifyEnded { delegate?.nativeSfxEngineDidProduce(.ended(elementId)) }
  }

  private func stopAllLocked(notifyEnded: Bool) {
    let identifiers = Array(activeVoices.keys)
    for identifier in identifiers { stopVoice(elementId: identifier, notifyEnded: notifyEnded) }
  }

  private func evictBuffers() {
    makeCacheSpace(for: 0)
  }

  private func makeCacheSpace(for incomingBytes: Int) {
    while cacheBytes + incomingBytes > pcmCacheByteLimit,
          let oldest = buffers.filter({ $0.value.retainCount == 0 })
            .min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
      buffers.removeValue(forKey: oldest.key)
      cacheBytes -= oldest.value.byteCount
    }
  }

  private func fallback(_ request: PlayRequest, reason: String) {
    metric("native_sfx_fallback", path: locator.relativePath(for: request.url), details: ["reason": reason])
    delegate?.nativeSfxEngineDidProduce(.fallback(request.elementId, reason))
  }

  private func metric(_ event: String, path: String? = nil, details: [String: Any] = [:]) {
    var context = details
    if let path { context["urlHash"] = urlHash(path) }
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
