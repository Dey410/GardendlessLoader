import XCTest
@testable import GardendlessBridge
@testable import GardendlessGPNext
@testable import GardendlessImport
@testable import GardendlessResource

final class ConstantsTests: XCTestCase {
  func testResourceMethods() {
    XCTAssertEqual(ResourceConstants.allowedMethods, ["GET", "HEAD"])
  }

  func testBridgeLimits() {
    XCTAssertEqual(BridgeConstants.maxMessageBytes, 1024 * 1024)
  }

  func testZipLimits() {
    XCTAssertEqual(ZipImportLimits.copyBufferSize, 64 * 1024)
    XCTAssertEqual(ZipImportLimits.centralHeaderLength, 46)
  }

  func testGpNextConstants() {
    XCTAssertEqual(GpNextConstants.appDataBaseDirectoryID, 14)
  }

}
