import XCTest
@testable import GardendlessCore

final class GameConfigurationTests: XCTestCase {
  func testDefaultsMatchProductLimits() {
    let config = GameConfiguration.default
    XCTAssertEqual(config.audioCacheByteLimit, 24 * 1024 * 1024)
    XCTAssertEqual(config.audioQueueConcurrency, 3)
    XCTAssertEqual(config.maxExportBytes, 512 * 1024 * 1024)
    XCTAssertEqual(config.maxExportChunkBytes, 256 * 1024)
    XCTAssertEqual(config.bridgeMaxMessageBytes, 1024 * 1024)
  }
}
