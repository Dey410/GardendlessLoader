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

  func testStopWaitsForReservedActionAndForbidsLateDelivery() {
    let gate = TaskCallbackGate()
    let owner = NSObject()
    let id = ObjectIdentifier(owner)
    gate.start(id)
    let actionEntered = DispatchSemaphore(value: 0)
    let actionMayReturn = DispatchSemaphore(value: 0)
    let cancelReturned = DispatchSemaphore(value: 0)
    let done = expectation(description: "callback and stop complete")
    DispatchQueue.global().async {
      _ = gate.perform(id) {
        actionEntered.signal()
        _ = actionMayReturn.wait(timeout: .now() + 2)
      }
    }
    XCTAssertEqual(actionEntered.wait(timeout: .now() + 2), .success)
    DispatchQueue.global().async {
      gate.cancel(id)
      cancelReturned.signal()
      done.fulfill()
    }
    XCTAssertEqual(cancelReturned.wait(timeout: .now() + 0.05), .timedOut)
    actionMayReturn.signal()
    wait(for: [done], timeout: 2)
    XCTAssertFalse(gate.perform(id) { XCTFail("late callback") })
  }
}
