import XCTest
@testable import GardendlessLogging

final class LogStoreTests: XCTestCase {
  func testEmitOrdersEventsAndCapsSnapshot() {
    let store = LogStore(capacity: 3)
    store.emit(["event": "first"])
    store.emit(["event": "second"])
    store.emit(["event": "third"])
    store.emit(["event": "fourth"])

    let snapshot = store.snapshot()
    XCTAssertEqual(snapshot.count, 3)
    XCTAssertEqual(snapshot.first?["event"] as? String, "second")
    XCTAssertEqual(snapshot.last?["event"] as? String, "fourth")
    XCTAssertNotNil(snapshot.first?["timestampUtc"])
    XCTAssertEqual(snapshot.first?["sequence"] as? Int, 2)
  }
}
