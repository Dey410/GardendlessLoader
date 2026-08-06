import XCTest
@testable import GardendlessCore

final class GameConfigurationTests: XCTestCase {
  func testDefaultsMatchProductLimits() {
    let config = GameConfiguration.default
    XCTAssertEqual(config.audioCacheByteLimit, 24 * 1024 * 1024)
    XCTAssertEqual(config.pcmCacheByteLimit, 96 * 1024 * 1024)
    XCTAssertEqual(config.maxExportBytes, 512 * 1024 * 1024)
    XCTAssertEqual(config.maxExportChunkBytes, 256 * 1024)
    XCTAssertEqual(config.bridgeMaxMessageBytes, 1024 * 1024)
    XCTAssertEqual(config.compressedSfxByteLimit, 512 * 1024)
    XCTAssertEqual(config.maximumSfxDuration, 10)
    XCTAssertEqual(config.longMaxBytes, 64 * 1024 * 1024)
    XCTAssertEqual(config.longMaxDuration, 600)
  }
}
