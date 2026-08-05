import AVFoundation
import Foundation
import GardendlessCore
import GardendlessAudio
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
}
