import XCTest
@testable import GardendlessAudio
@testable import GardendlessBridge
@testable import GardendlessGPNext
@testable import GardendlessImport
@testable import GardendlessResource

final class ConstantsTests: XCTestCase {
  func testResourceOriginAndMethods() {
    XCTAssertEqual(ResourceConstants.origin, "gardendless-game://localhost")
    XCTAssertEqual(ResourceConstants.allowedMethods, ["GET", "HEAD"])
  }

  func testBridgeLimits() {
    XCTAssertEqual(BridgeConstants.maxMessageBytes, 1024 * 1024)
    XCTAssertEqual(BridgeConstants.userInteractionTimeout, 5 * 60)
  }

  func testZipLimits() {
    XCTAssertEqual(ZipImportLimits.copyBufferSize, 64 * 1024)
    XCTAssertEqual(ZipImportLimits.centralHeaderLength, 46)
  }

  func testGpNextConstants() {
    XCTAssertEqual(GpNextConstants.appDataBaseDirectoryID, 14)
    XCTAssertEqual(
      GpNextConstants.allowedImportExtensions,
      ["zip", "json", "json5"]
    )
  }

  func testAudioLimits() {
    XCTAssertEqual(AudioPlaybackLimits.voicePoolSize, 48)
    XCTAssertEqual(AudioPlaybackLimits.rateVoiceCount, 6)
    XCTAssertEqual(AudioPlaybackLimits.longChannelCount, 8)
    XCTAssertTrue(AudioPlaybackLimits.excludedTokens.contains("bgm"))
  }
}
