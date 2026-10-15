import Foundation
import XCTest
@testable import GardendlessResource

final class TaskCallbackGateTests: XCTestCase {
  func testReentrantStopPreventsAllLaterCallbacks() {
    let gate = TaskCallbackGate()
    let owner = NSObject()
    let id = ObjectIdentifier(owner)
    gate.start(id)
    XCTAssertTrue(gate.perform(id) { gate.cancel(id) })
    XCTAssertFalse(gate.perform(id) { XCTFail("callback ran after stop") })
    XCTAssertFalse(gate.perform(id, finishing: true) { XCTFail("finished after stop") })
  }

  func testOffMainCallbackIsDeliveredOnMainThread() {
    let gate = TaskCallbackGate()
    let owner = NSObject()
    let id = ObjectIdentifier(owner)
    gate.start(id)
    let delivered = expectation(description: "callback delivered")
    DispatchQueue.global().async {
      XCTAssertTrue(gate.perform(id) {
        XCTAssertTrue(Thread.isMainThread)
      })
      delivered.fulfill()
    }
    wait(for: [delivered], timeout: 2)
  }

  /// WebKit calls start/stop on the main thread and blocks off-main
  /// WKURLSchemeTask callers on the main run loop. A main-thread stop must
  /// not wait for an off-main delivery, and the delivery must not run after it.
  func testMainThreadStopIsNotBlockedAndForbidsLateDelivery() {
    let gate = TaskCallbackGate()
    let owner = NSObject()
    let other = NSObject()
    let id = ObjectIdentifier(owner)
    gate.start(id)
    let deliveryRequested = DispatchSemaphore(value: 0)
    let finished = expectation(description: "off-main delivery returned")
    DispatchQueue.global().async {
      deliveryRequested.signal()
      XCTAssertFalse(gate.perform(id) { XCTFail("callback ran after stop") })
      finished.fulfill()
    }
    XCTAssertEqual(deliveryRequested.wait(timeout: .now() + 2), .success)
    gate.start(ObjectIdentifier(other))
    gate.cancel(id)
    wait(for: [finished], timeout: 2)
    XCTAssertFalse(gate.isActive(id))
    XCTAssertTrue(gate.isActive(ObjectIdentifier(other)))
  }
}
