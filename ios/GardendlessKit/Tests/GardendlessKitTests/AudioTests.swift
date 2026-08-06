import AVFoundation
import Foundation
import GardendlessCore
@testable import GardendlessAudio
import SfxExceptionGuard
import XCTest

final class AudioTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-audio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if root != nil {
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testNativeCandidateRules() {
    XCTAssertTrue(
      ShortSfxEngine.isNativeCandidate(
        relativePath: "assets/sfx/click.mp3",
        loop: false,
        playbackRate: 1
      )
    )
    XCTAssertFalse(
      ShortSfxEngine.isNativeCandidate(
        relativePath: "assets/sfx/click.mp3",
        loop: true,
        playbackRate: 1
      )
    )
    XCTAssertFalse(
      ShortSfxEngine.isNativeCandidate(
        relativePath: "assets/sfx/click.mp3",
        loop: false,
        playbackRate: 1.5
      )
    )
    XCTAssertFalse(
      ShortSfxEngine.isNativeCandidate(
        relativePath: "assets/bgm/main.mp3",
        loop: false,
        playbackRate: 1
      )
    )
    XCTAssertFalse(
      ShortSfxEngine.isNativeCandidate(
        relativePath: "assets/sfx/music.mp3",
        loop: false,
        playbackRate: 1
      )
    )
    XCTAssertFalse(
      ShortSfxEngine.isNativeCandidate(
        relativePath: "assets/sfx/click.ogg",
        loop: false,
        playbackRate: 1
      )
    )
  }

  func testRouteClassifierSilencesEverythingOutsideShortBounds() {
    let configuration = GameConfiguration.default
    XCTAssertEqual(
      ShortSfxEngine.classify(
        compressedBytes: 100_000,
        duration: 2,
        configuration: configuration
      ),
      .native
    )
    XCTAssertEqual(
      ShortSfxEngine.classify(
        compressedBytes: 600_000,
        duration: 2,
        configuration: configuration
      ),
      .silent("compressed_size_limit")
    )
    XCTAssertEqual(
      ShortSfxEngine.classify(
        compressedBytes: 100_000,
        duration: 20,
        configuration: configuration
      ),
      .silent("duration_limit")
    )
  }

  func testAudioContainerDetection() throws {
    let m4a = root.appendingPathComponent("mislabeled.mp3")
    try Data([0, 0, 0, 24] + Array("ftypM4A ".utf8) + [0, 0, 0, 0])
      .write(to: m4a)
    XCTAssertEqual(try AudioContainerDetector.detect(m4a), .m4a)

    let mp3 = root.appendingPathComponent("genuine.mp3")
    try Data(Array("ID3genuine-mp3".utf8)).write(to: mp3)
    XCTAssertEqual(try AudioContainerDetector.detect(mp3), .mp3)

    let unknown = root.appendingPathComponent("unknown.bin")
    try Data([0, 1, 2, 3]).write(to: unknown)
    XCTAssertEqual(try AudioContainerDetector.detect(unknown), .unsupported)
  }

  func testExceptionGuardReturnsReasonForObjectiveCExceptions() {
    let normal = SfxExceptionGuard.runBlock {
      _ = 1 + 1
    }
    XCTAssertNil(normal)

    let raised = SfxExceptionGuard.runBlock {
      NSException(
        name: .invalidArgumentException,
        reason: "boom",
        userInfo: nil
      ).raise()
    }
    XCTAssertNotNil(raised)
    XCTAssertTrue(raised?.contains("boom") == true)
  }

  func testEngineShutdownWithoutPlaybackIsIdempotent() throws {
    let sandbox = try PathSandbox(root: root)
    let engine = ShortSfxEngine(sandbox: sandbox)
    engine.shutdown()
    engine.shutdown()
  }

  func testAudioPlayRequestClampsVolumeAndRate() {
    let loud = AudioPlayRequest(
      requestId: "1",
      url: URL(string: "https://example.com/a.mp3")!,
      role: .oneShot,
      volume: 5,
      rate: 0.05
    )
    XCTAssertEqual(loud.volume, 1)
    XCTAssertEqual(loud.rate, 0.1)

    let quiet = AudioPlayRequest(
      requestId: "2",
      url: URL(string: "https://example.com/b.mp3")!,
      role: .continuous,
      volume: -1,
      rate: 99
    )
    XCTAssertEqual(quiet.volume, 0)
    XCTAssertEqual(quiet.rate, 4)
  }

  func testPipelineShutdownIsIdempotent() throws {
    let sandbox = try PathSandbox(root: root)
    let pipeline = AudioPipelineEngine(sandbox: sandbox)
    pipeline.shutdown()
    pipeline.shutdown()
  }

  func testLongChannelReportsSilentForUnresolvableUrl() throws {
    let sandbox = try PathSandbox(root: root)
    let channel = LongAudioChannel(sandbox: sandbox)
    let spy = OutcomeSpy()
    channel.delegate = spy
    let expectation = expectation(description: "long silent outcome")
    spy.onOutcome = { outcome in
      if outcome.kind == .silent {
        expectation.fulfill()
      }
    }
    channel.play(
      AudioPlayRequest(
        requestId: "long-1",
        url: URL(string: "https://example.com/a.mp3")!,
        role: .continuous
      )
    )
    wait(for: [expectation], timeout: 1)
    channel.shutdown()
  }

  func testShortEngineReportsSilentForUnresolvableUrl() throws {
    let sandbox = try PathSandbox(root: root)
    let engine = ShortSfxEngine(sandbox: sandbox)
    let spy = OutcomeSpy()
    engine.delegate = spy
    let expectation = expectation(description: "short silent outcome")
    spy.onOutcome = { outcome in
      if outcome.kind == .silent {
        expectation.fulfill()
      }
    }
    engine.play(
      requestId: "short-1",
      url: URL(string: "https://example.com/a.mp3")!,
      volume: 1
    )
    wait(for: [expectation], timeout: 1)
    engine.shutdown()
  }

  func testLongChannelScheduleFailureSurface() throws {
    let url = root.appendingPathComponent("tiny.m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 24_000,
    ]
    do {
      let audioFile = try AVAudioFile(forWriting: url, settings: settings)
      let format = audioFile.processingFormat
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
      buffer.frameLength = 1_600
      if let channel = buffer.floatChannelData?[0] {
        for index in 0..<Int(buffer.frameLength) {
          channel[index] = sin(Float(index) * 0.1)
        }
      }
      try audioFile.write(from: buffer)
    }

    let sandbox = try PathSandbox(root: root)
    let channel = LongAudioChannel(sandbox: sandbox)
    let spy = OutcomeSpy()
    channel.delegate = spy
    let expectation = expectation(description: "long schedule outcome")
    spy.onOutcome = { outcome in
      if outcome.kind == .ended || outcome.kind == .silent {
        expectation.fulfill()
      }
    }
    channel.play(
      AudioPlayRequest(
        requestId: "long-schedule-1",
        url: URL(string: "gardendless-game://localhost/tiny.m4a")!,
        role: .continuous
      )
    )
    wait(for: [expectation], timeout: 5)
    XCTAssertTrue(
      spy.outcomes.contains { $0.kind == .ended },
      "long channel should schedule and play through to ended"
    )
    XCTAssertFalse(
      spy.outcomes.contains { $0.kind == .silent },
      "long channel should not report silent for a valid m4a"
    )
    channel.shutdown()
  }

  func testShortEngineSchedulesValidM4aAtNormalAndRatedPlayback() throws {
    let url = root.appendingPathComponent("tiny-short.m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 24_000,
    ]
    do {
      let audioFile = try AVAudioFile(forWriting: url, settings: settings)
      let format = audioFile.processingFormat
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
      buffer.frameLength = 1_600
      if let channel = buffer.floatChannelData?[0] {
        for index in 0..<Int(buffer.frameLength) {
          channel[index] = sin(Float(index) * 0.1)
        }
      }
      try audioFile.write(from: buffer)
    }

    let sandbox = try PathSandbox(root: root)
    let engine = ShortSfxEngine(sandbox: sandbox)
    let spy = OutcomeSpy()
    engine.delegate = spy
    let normalExpectation = expectation(description: "short normal outcome")
    spy.onOutcome = { outcome in
      if outcome.kind == .ended || outcome.kind == .silent {
        normalExpectation.fulfill()
      }
    }
    engine.play(
      requestId: "short-normal-1",
      url: URL(string: "gardendless-game://localhost/tiny-short.m4a")!,
      volume: 1
    )
    wait(for: [normalExpectation], timeout: 5)
    XCTAssertTrue(
      spy.outcomes.contains { $0.kind == .ended },
      "short engine should play a valid m4a at rate 1"
    )

    let rateExpectation = expectation(description: "short rate outcome")
    spy.onOutcome = { outcome in
      if outcome.kind == .ended || outcome.kind == .silent {
        rateExpectation.fulfill()
      }
    }
    engine.play(
      requestId: "short-rate-1",
      url: URL(string: "gardendless-game://localhost/tiny-short.m4a")!,
      volume: 1,
      rate: 2
    )
    wait(for: [rateExpectation], timeout: 5)
    XCTAssertTrue(
      spy.outcomes.contains { $0.kind == .ended },
      "short engine rate voice should play a valid m4a"
    )
    XCTAssertFalse(
      spy.outcomes.contains { $0.kind == .silent },
      "short engine should not report silent for valid m4a"
    )
    engine.shutdown()
  }

  private func writeOneSecondM4a(_ name: String) throws -> URL {
    let url = root.appendingPathComponent(name)
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 24_000,
    ]
    do {
      let audioFile = try AVAudioFile(forWriting: url, settings: settings)
      let format = audioFile.processingFormat
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: 16_000
      )!
      buffer.frameLength = 16_000
      if let channel = buffer.floatChannelData?[0] {
        for index in 0..<Int(buffer.frameLength) {
          channel[index] = sin(Float(index) * 0.01)
        }
      }
      try audioFile.write(from: buffer)
    }
    return url
  }

  func testLongChannelIgnoresStaleCompletionAfterStopAndReplay() throws {
    _ = try writeOneSecondM4a("reuse-long.m4a")
    let sandbox = try PathSandbox(root: root)
    let channel = LongAudioChannel(sandbox: sandbox)
    let spy = OutcomeSpy()
    channel.delegate = spy
    let url = URL(string: "gardendless-game://localhost/reuse-long.m4a")!
    channel.play(
      AudioPlayRequest(requestId: "reuse", url: url, role: .continuous)
    )
    channel.stop(requestId: "reuse")
    channel.play(
      AudioPlayRequest(requestId: "reuse", url: url, role: .continuous)
    )
    let startedAt = Date()
    let expectation = expectation(description: "replayed long ended")
    spy.onOutcome = { outcome in
      if outcome.kind == .ended {
        expectation.fulfill()
      }
    }
    wait(for: [expectation], timeout: 4)
    XCTAssertGreaterThan(
      Date().timeIntervalSince(startedAt),
      0.5,
      "a stale completion must not end the replayed continuous audio"
    )
    channel.shutdown()
  }

  func testShortEngineIgnoresStaleCompletionAfterStopAndReplay() throws {
    _ = try writeOneSecondM4a("reuse-short.m4a")
    let sandbox = try PathSandbox(root: root)
    let engine = ShortSfxEngine(sandbox: sandbox)
    let spy = OutcomeSpy()
    engine.delegate = spy
    let url = URL(string: "gardendless-game://localhost/reuse-short.m4a")!
    engine.play(requestId: "reuse-short", url: url, volume: 1)
    engine.stop(requestId: "reuse-short")
    engine.play(requestId: "reuse-short", url: url, volume: 1)
    let startedAt = Date()
    let expectation = expectation(description: "replayed short ended")
    spy.onOutcome = { outcome in
      if outcome.kind == .ended {
        expectation.fulfill()
      }
    }
    wait(for: [expectation], timeout: 4)
    XCTAssertGreaterThan(
      Date().timeIntervalSince(startedAt),
      0.5,
      "a stale completion must not end the replayed short audio"
    )
    engine.shutdown()
  }

  func testLongChannelLoopDoesNotEndUntilStopped() throws {
    _ = try writeOneSecondM4a("loop-long.m4a")
    let sandbox = try PathSandbox(root: root)
    let channel = LongAudioChannel(sandbox: sandbox)
    let spy = OutcomeSpy()
    channel.delegate = spy
    let expectation = expectation(description: "looped audio must not end")
    expectation.isInverted = true
    spy.onOutcome = { outcome in
      if outcome.kind == .ended || outcome.kind == .silent {
        expectation.fulfill()
      }
    }
    channel.play(
      AudioPlayRequest(
        requestId: "loop-long",
        url: URL(string: "gardendless-game://localhost/loop-long.m4a")!,
        role: .continuous,
        loop: true
      )
    )
    wait(for: [expectation], timeout: 1.6)
    channel.stop(requestId: "loop-long")
    channel.shutdown()
  }

  func testLongChannelPauseAndResumePlaysToEnd() throws {
    _ = try writeOneSecondM4a("resume-long.m4a")
    let sandbox = try PathSandbox(root: root)
    let channel = LongAudioChannel(sandbox: sandbox)
    let spy = OutcomeSpy()
    channel.delegate = spy
    let url = URL(string: "gardendless-game://localhost/resume-long.m4a")!
    channel.play(
      AudioPlayRequest(requestId: "resume-long", url: url, role: .continuous)
    )
    channel.pause(requestId: "resume-long")
    channel.play(
      AudioPlayRequest(requestId: "resume-long", url: url, role: .continuous)
    )
    let expectation = expectation(description: "resumed long ended")
    spy.onOutcome = { outcome in
      if outcome.kind == .ended {
        expectation.fulfill()
      }
    }
    wait(for: [expectation], timeout: 4)
    XCTAssertFalse(
      spy.outcomes.contains { $0.kind == .silent },
      "resumed continuous audio must not report silent"
    )
    channel.shutdown()
  }

  func testLongChannelRatedPlaybackPlaysToEnd() throws {
    _ = try writeOneSecondM4a("rate-long.m4a")
    let sandbox = try PathSandbox(root: root)
    let channel = LongAudioChannel(sandbox: sandbox)
    let spy = OutcomeSpy()
    channel.delegate = spy
    let startedAt = Date()
    let expectation = expectation(description: "rated long ended")
    spy.onOutcome = { outcome in
      if outcome.kind == .ended {
        expectation.fulfill()
      }
    }
    channel.play(
      AudioPlayRequest(
        requestId: "rate-long",
        url: URL(string: "gardendless-game://localhost/rate-long.m4a")!,
        role: .continuous,
        rate: 2
      )
    )
    wait(for: [expectation], timeout: 3)
    let elapsed = Date().timeIntervalSince(startedAt)
    XCTAssertGreaterThan(
      elapsed,
      0.2,
      "rated long audio must not be ended by a stale completion"
    )
    XCTAssertLessThan(
      elapsed,
      1.0,
      "2x rated 1s audio should finish before a full second"
    )
    XCTAssertFalse(
      spy.outcomes.contains { $0.kind == .silent },
      "rated continuous audio must not report silent"
    )
    channel.shutdown()
  }

  func testLongChannelMultiChunkStreamingPlaysToEnd() throws {
    let url = root.appendingPathComponent("multi-chunk.m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 24_000,
    ]
    do {
      let audioFile = try AVAudioFile(forWriting: url, settings: settings)
      let format = audioFile.processingFormat
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: 80_000
      )!
      buffer.frameLength = 80_000
      if let channel = buffer.floatChannelData?[0] {
        for index in 0..<Int(buffer.frameLength) {
          channel[index] = sin(Float(index) * 0.01)
        }
      }
      try audioFile.write(from: buffer)
    }
    let sandbox = try PathSandbox(root: root)
    let channel = LongAudioChannel(sandbox: sandbox)
    let spy = OutcomeSpy()
    channel.delegate = spy
    let startedAt = Date()
    let expectation = expectation(description: "multi chunk ended")
    spy.onOutcome = { outcome in
      if outcome.kind == .ended {
        expectation.fulfill()
      }
    }
    channel.play(
      AudioPlayRequest(
        requestId: "multi-chunk",
        url: URL(string: "gardendless-game://localhost/multi-chunk.m4a")!,
        role: .continuous
      )
    )
    wait(for: [expectation], timeout: 8)
    let elapsed = Date().timeIntervalSince(startedAt)
    XCTAssertGreaterThan(
      elapsed,
      4.5,
      "5s audio must play through multiple chunks before ending"
    )
    XCTAssertFalse(
      spy.outcomes.contains { $0.kind == .silent },
      "multi-chunk continuous audio must not report silent"
    )
    channel.shutdown()
  }

  func testPipelineRoutesShortContinuousAudioToShortEngine() throws {
    _ = try writeOneSecondM4a("route-short.m4a")
    let sandbox = try PathSandbox(root: root)
    let pipeline = AudioPipelineEngine(sandbox: sandbox)
    let role = pipeline.effectiveRole(
      for: AudioPlayRequest(
        requestId: "route-short",
        url: URL(string: "gardendless-game://localhost/route-short.m4a")!,
        role: .continuous
      )
    )
    XCTAssertEqual(
      role,
      .oneShot,
      "short non-loop continuous audio must route to the short engine"
    )
    pipeline.shutdown()
  }

  func testPipelineKeepsLongContinuousAudioOnLongChannel() throws {
    let url = root.appendingPathComponent("route-long.m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 24_000,
    ]
    do {
      let audioFile = try AVAudioFile(forWriting: url, settings: settings)
      let format = audioFile.processingFormat
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: 176_000
      )!
      buffer.frameLength = 176_000
      if let channel = buffer.floatChannelData?[0] {
        for index in 0..<Int(buffer.frameLength) {
          channel[index] = sin(Float(index) * 0.01)
        }
      }
      try audioFile.write(from: buffer)
    }
    let sandbox = try PathSandbox(root: root)
    let pipeline = AudioPipelineEngine(sandbox: sandbox)
    let role = pipeline.effectiveRole(
      for: AudioPlayRequest(
        requestId: "route-long",
        url: URL(string: "gardendless-game://localhost/route-long.m4a")!,
        role: .continuous
      )
    )
    XCTAssertEqual(
      role,
      .continuous,
      "audio longer than the short limit must stay on the long channel"
    )
    pipeline.shutdown()
  }
}

private final class OutcomeSpy: ShortSfxEngineDelegate, LongAudioChannelDelegate {
  var outcomes: [AudioOutcome] = []
  var onOutcome: ((AudioOutcome) -> Void)?

  func shortSfxEngineDidProduce(_ outcome: AudioOutcome) {
    record(outcome)
  }

  func longAudioChannelDidProduce(_ outcome: AudioOutcome) {
    record(outcome)
  }

  private func record(_ outcome: AudioOutcome) {
    outcomes.append(outcome)
    onOutcome?(outcome)
  }
}
