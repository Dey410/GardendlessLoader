import Foundation
import GardendlessAudio
import GardendlessCore
import WebKit

final class AudioScriptBridge: NSObject,
  WKScriptMessageHandler,
  AudioPipelineEngineDelegate {
  static let name = "gardendlessAudio"

  private let engine: AudioPipelineEngine
  private let webViewProvider: () -> WKWebView?
  private let diagnosticsWriteQueue = DispatchQueue(
    label: "io.github.dey410.gardendless.audio-diagnostics-write"
  )
  private var destroyed = false

  private var pendingEnded: [String] = []
  private var pendingEndedReasons: [String] = []
  private var pendingSilent: [String] = []
  private var pendingSilentReasons: [String] = []
  private var pendingStopped: [String] = []
  private var pendingStoppedReasons: [String] = []
  private var flushScheduled = false

  init(
    engine: AudioPipelineEngine,
    webViewProvider: @escaping () -> WKWebView?
  ) {
    self.engine = engine
    self.webViewProvider = webViewProvider
    super.init()
    engine.delegate = self
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard !destroyed,
          message.frameInfo.isMainFrame,
          message.frameInfo.securityOrigin.protocol == GameOrigin.scheme,
          message.frameInfo.securityOrigin.host == GameOrigin.host,
          let body = message.body as? [String: Any],
          let command = body["command"] as? String else {
      return
    }
    switch command {
    case "play":
      guard let id = body["requestId"] as? String, !id.isEmpty,
            let url = validatedURL(body),
            let roleRaw = body["role"] as? String else {
        return
      }
      let role: AudioRole
      switch roleRaw {
      case "oneShot":
        role = .oneShot
      case "continuous":
        role = .continuous
      default:
        return
      }
      let request = AudioPlayRequest(
        requestId: id,
        url: url,
        role: role,
        kind: body["kind"] as? String,
        volume: (body["volume"] as? NSNumber)?.floatValue ?? 1,
        loop: (body["loop"] as? Bool) ?? false,
        rate: (body["rate"] as? NSNumber)?.doubleValue ?? 1,
        startTime: (body["startTime"] as? NSNumber)?.doubleValue ?? 0
      )
      engine.play(request)
    case "pause":
      if let id = body["requestId"] as? String, !id.isEmpty {
        engine.pause(requestId: id)
      }
    case "stop":
      if let id = body["requestId"] as? String, !id.isEmpty {
        engine.stop(requestId: id)
      }
    case "seek":
      if let id = body["requestId"] as? String, !id.isEmpty,
         let time = body["time"] as? NSNumber {
        engine.seek(requestId: id, time: time.doubleValue)
      }
    case "setVolume":
      if let id = body["requestId"] as? String, !id.isEmpty,
         let volume = body["volume"] as? NSNumber {
        engine.setVolume(requestId: id, volume: volume.floatValue)
      }
    case "setLoop":
      if let id = body["requestId"] as? String, !id.isEmpty,
         let loop = body["loop"] as? Bool {
        engine.setLoop(requestId: id, loop: loop)
      }
    case "setRate":
      if let id = body["requestId"] as? String, !id.isEmpty,
         let rate = body["rate"] as? NSNumber {
        engine.setRate(requestId: id, rate: rate.doubleValue)
      }
    case "release":
      if let id = body["requestId"] as? String, !id.isEmpty {
        engine.release(requestId: id)
      }
    case "releaseMany":
      if let ids = body["requestIds"] as? [String] {
        for id in ids where !id.isEmpty {
          engine.release(requestId: id)
        }
      }
    case "stopAll":
      engine.stopAll()
    case "setMasterVolume":
      if let volume = body["volume"] as? NSNumber {
        engine.setMasterVolume(volume.floatValue)
      }
    case "writeDiagnostics":
      if let json = body["json"] as? String,
         !json.isEmpty,
         json.utf8.count <= 16 * 1024 * 1024 {
        persistDiagnostics(json)
      }
    default:
      break
    }
  }

  private func persistDiagnostics(_ json: String) {
    diagnosticsWriteQueue.async {
      let directory = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
        .appendingPathComponent("Diagnostics", isDirectory: true)
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let url = directory.appendingPathComponent("audio-diagnostics.json")
      try? json.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  func audioPipelineEngineDidProduce(_ outcome: AudioOutcome) {
    guard !destroyed else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      switch outcome.kind {
      case .ended:
        self.pendingEnded.append(outcome.requestId)
        self.pendingEndedReasons.append(outcome.reason ?? "")
      case .silent:
        self.pendingSilent.append(outcome.requestId)
        self.pendingSilentReasons.append(outcome.reason ?? "")
      case .stopped:
        self.pendingStopped.append(outcome.requestId)
        self.pendingStoppedReasons.append(outcome.reason ?? "")
      }
      self.scheduleEventFlush()
    }
  }

  private func scheduleEventFlush() {
    guard !flushScheduled else { return }
    flushScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
      self?.flushEvents()
    }
  }

  private func flushEvents() {
    flushScheduled = false
    guard !destroyed else {
      clearPending()
      return
    }
    var events: [[String: Any]] = []
    if !pendingEnded.isEmpty {
      events.append([
        "type": "ended",
        "requestIds": pendingEnded,
        "reasons": pendingEndedReasons,
      ])
    }
    if !pendingSilent.isEmpty {
      events.append([
        "type": "silent",
        "requestIds": pendingSilent,
        "reasons": pendingSilentReasons,
      ])
    }
    if !pendingStopped.isEmpty {
      events.append([
        "type": "stopped",
        "requestIds": pendingStopped,
        "reasons": pendingStoppedReasons,
      ])
    }
    clearPending()
    guard !events.isEmpty,
          let payload = try? JSONSerialization.data(withJSONObject: events),
          let json = String(data: payload, encoding: .utf8),
          let webView = webViewProvider() else {
      return
    }
    webView.evaluateJavaScript(
      "if (window.__gardendlessAudioEvents) "
        + "window.__gardendlessAudioEvents(\(json));"
    )
  }

  private func clearPending() {
    pendingEnded.removeAll()
    pendingEndedReasons.removeAll()
    pendingSilent.removeAll()
    pendingSilentReasons.removeAll()
    pendingStopped.removeAll()
    pendingStoppedReasons.removeAll()
  }

  func destroy() {
    destroyed = true
    engine.delegate = nil
    engine.stopAll()
  }

  private func validatedURL(_ body: [String: Any]) -> URL? {
    guard let raw = body["url"] as? String,
          let url = URL(string: raw),
          url.scheme == GameOrigin.scheme,
          url.host == GameOrigin.host else {
      return nil
    }
    return url
  }
}
