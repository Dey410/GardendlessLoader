import Foundation
import GardendlessCore
import GardendlessBridge
import XCTest

final class BridgeRequestTests: XCTestCase {
  func testDecodesHostRequestWithArgsAndOptions() throws {
    let raw = """
    {"id":"42","namespace":"host","command":"host:setWatermark","args":{"enabled":false},"options":{}}
    """
    let request = try BridgeRequest.decode(raw)
    XCTAssertEqual(request.id, "42")
    XCTAssertEqual(request.command, "host:setWatermark")
    XCTAssertEqual(request.namespace, "host")
    XCTAssertEqual(request.args["enabled"] as? Bool, false)
  }

  func testDecodesGpNextNamespaceRequest() throws {
    let raw = """
    {"id":"7","namespace":"gp-next","command":"plugin:fs|exists","args":{"path":"packs/a.zip"}}
    """
    let request = try BridgeRequest.decode(raw)
    XCTAssertEqual(request.namespace, "gp-next")
    XCTAssertEqual(request.command, "plugin:fs|exists")
    XCTAssertEqual(request.args["path"] as? String, "packs/a.zip")
  }

  func testRejectsMissingIdOrCommand() {
    XCTAssertThrowsError(try BridgeRequest.decode(#"{"id":"","command":"x"}"#))
    XCTAssertThrowsError(try BridgeRequest.decode(#"{"id":"1","command":""}"#))
    XCTAssertThrowsError(try BridgeRequest.decode("not json"))
  }

  func testCommandClassification() {
    XCTAssertTrue(BridgeCommand.isExport("host:exportBegin"))
    XCTAssertTrue(BridgeCommand.isExport("host:exportAbort"))
    XCTAssertFalse(BridgeCommand.isExport("host:log"))
    XCTAssertTrue(BridgeCommand.isWatermark("host:set_watermark"))
    XCTAssertTrue(BridgeCommand.isReturnHome("host:return_home"))
  }
}

final class ExportCoordinatorTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-export-\(UUID().uuidString)")
  }

  override func tearDownWithError() throws {
    if root != nil {
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testBeginAppendCommitRoundTrip() throws {
    let coordinator = try ExportCoordinator(temporaryRoot: root)
    let token = try coordinator.begin(
      sessionId: "session-1",
      suggestedFilename: "../存档.json",
      mimeType: "application/json",
      totalBytes: 5
    )
    XCTAssertFalse(token.isEmpty)
    try coordinator.append(token: token, index: 0, data: Data("hello".utf8))
    let file = try coordinator.commit(token: token)
    XCTAssertEqual(try Data(contentsOf: file), Data("hello".utf8))
    XCTAssertEqual(file.lastPathComponent, "存档.json")
    coordinator.finishAfterPicker(for: file)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
  }

  func testRejectsWrongOrderAndOversizeChunks() throws {
    let coordinator = try ExportCoordinator(temporaryRoot: root)
    let token = try coordinator.begin(
      sessionId: "s",
      suggestedFilename: "a.json",
      mimeType: "application/json",
      totalBytes: 10
    )
    XCTAssertThrowsError(
      try coordinator.append(token: token, index: 1, data: Data([1]))
    )
    XCTAssertThrowsError(
      try coordinator.append(
        token: token,
        index: 0,
        data: Data(repeating: 1, count: 300 * 1024)
      )
    )
    coordinator.abort(token: token)
  }

  func testCommitRequiresEveryByteAndAbortCleansUp() throws {
    let coordinator = try ExportCoordinator(temporaryRoot: root)
    let token = try coordinator.begin(
      sessionId: "s",
      suggestedFilename: "b.json",
      mimeType: "application/json",
      totalBytes: 4
    )
    try coordinator.append(token: token, index: 0, data: Data([1]))
    XCTAssertThrowsError(try coordinator.commit(token: token))
    coordinator.abort(token: token)
    let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
    XCTAssertTrue(files.isEmpty)
  }

  func testRejectsConcurrentExport() throws {
    let coordinator = try ExportCoordinator(temporaryRoot: root)
    _ = try coordinator.begin(
      sessionId: "s",
      suggestedFilename: "c.json",
      mimeType: "application/json",
      totalBytes: 1
    )
    XCTAssertThrowsError(
      try coordinator.begin(
        sessionId: "s",
        suggestedFilename: "d.json",
        mimeType: "application/json",
        totalBytes: 1
      )
    )
    coordinator.cancelActive()
  }
}
