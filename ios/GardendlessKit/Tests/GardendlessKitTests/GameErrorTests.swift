import XCTest
@testable import GardendlessCore

final class GameErrorTests: XCTestCase {
  func testFailedErrorCarriesStableCodeAndMessage() {
    let error = GameError.failed(.zipEncrypted, "选择的 ZIP 已加密，无法导入")
    XCTAssertEqual(error.code, .zipEncrypted)
    XCTAssertEqual(error.message, "选择的 ZIP 已加密，无法导入")
    XCTAssertEqual(error.errorDescription, "选择的 ZIP 已加密，无法导入")
  }

  func testUnderlyingErrorKeepsCodeAndWrapsCause() {
    let cause = CocoaError(.fileNoSuchFile)
    let error = GameError.underlying(.resourceReadFailed, "read failed", cause)
    XCTAssertEqual(error.code, .resourceReadFailed)
    XCTAssertEqual(error.message, "read failed")
  }
}
