import XCTest
@testable import GardendlessCore

final class HealthProbeTests: XCTestCase {
  func testProbeReportsWritableTemporaryDirectory() {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-health-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let report = HealthProbe.run(probeDirectory: directory)
    XCTAssertTrue(report.writable)
  }
}
