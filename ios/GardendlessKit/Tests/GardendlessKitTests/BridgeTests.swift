import Foundation
import GardendlessCore
import GardendlessBridge
import GardendlessGPNext
import XCTest

final class BridgeRequestTests: XCTestCase {
  func testDecodesHostRequestWithArgsAndOptions() throws {
    let raw = """
    {"id":"42","namespace":"host","command":"host:log","args":{"message":"hello"},"options":{}}
    """
    let request = try BridgeRequest.decode(raw)
    XCTAssertEqual(request.id, "42")
    XCTAssertEqual(request.command, "host:log")
    XCTAssertEqual(request.namespace, "host")
    XCTAssertEqual(request.args["message"] as? String, "hello")
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

  func testOnlyCloseAndCancelHaveBoundedAdmissionReserve() {
    XCTAssertEqual(BridgeConstants.pendingRequestLimit(command: "file:finish", args: ["action": "close"]), 72)
    XCTAssertEqual(BridgeConstants.pendingRequestLimit(command: "file:finish", args: ["action": "cancel"]), 72)
    XCTAssertEqual(BridgeConstants.pendingRequestLimit(command: "file:finish", args: ["action": "commit"]), 64)
    XCTAssertEqual(BridgeConstants.pendingRequestLimit(command: "file:finish", args: [:]), 64)
    XCTAssertEqual(BridgeConstants.pendingRequestLimit(command: "host:log", args: ["action": "cancel"]), 64)
  }

  func testCommandClassification() {
    XCTAssertFalse(BridgeCommand.isExport("host:exportBegin"))
    XCTAssertTrue(BridgeCommand.isFile("file:finish"))
    XCTAssertFalse(BridgeCommand.isExport("host:log"))
    XCTAssertNil(BridgeCommand(rawValue: "host:setWatermark"))
    XCTAssertNil(BridgeCommand(rawValue: "host:set_watermark"))
    XCTAssertTrue(BridgeCommand.isReturnHome("host:return_home"))
  }
}

final class FileTaskCoordinatorTests: XCTestCase {
  private func makeCoordinator(gp: Bool = true,
                               clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) throws -> (FileTaskCoordinator, URL) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-file-retained-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let gpRoot = root.appendingPathComponent("gp-next")
    // Fixture files live in packs/; the host itself never creates gp-next.
    try FileManager.default.createDirectory(
      at: gpRoot.appendingPathComponent("packs"), withIntermediateDirectories: true)
    let session = GameSession(
      sessionId: "test", resourceRoot: root, entryURL: URL(string: "gardendless-game://localhost/index.html")!,
      activationGeneration: 1, hasGpNext: gp, gpNextCompatible: gp,
      gpNextVersion: nil, watermarkEnabled: true, autoCollectSunEnabled: false,
      allowedRemoteHosts: [], gpNextRoot: gpRoot,
      exportTemporaryRoot: gpRoot.appendingPathComponent(".exports")
    )
    let router = gp ? try GpNextCommandRouter(session: session) : nil
    return (try FileTaskCoordinator(session: session, gpNextRouter: router, clock: clock), gpRoot)
  }

  private func invoke(_ coordinator: FileTaskCoordinator, _ command: String,
                      _ args: [String: Any]) throws -> GpNextAction {
    let done = expectation(description: command)
    var outcome: Result<GpNextAction, Error>?
    coordinator.submit(command: command, arguments: args) { result in
      outcome = result
      done.fulfill()
    }
    wait(for: [done], timeout: 3)
    return try XCTUnwrap(outcome).get()
  }

  private func invokeGp(_ coordinator: FileTaskCoordinator, _ command: String,
                        _ args: [String: Any] = [:]) throws -> GpNextAction {
    let done = expectation(description: command)
    var outcome: Result<GpNextAction, Error>?
    coordinator.submitGpNext(["command": command, "args": args]) { result in
      outcome = result
      done.fulfill()
    }
    wait(for: [done], timeout: 3)
    return try XCTUnwrap(outcome).get()
  }

  private func value(_ action: GpNextAction) throws -> [String: Any] {
    guard case .value(let value) = action, let map = value as? [String: Any] else {
      XCTFail("Expected file response")
      return [:]
    }
    return map
  }

  func testChunkReadWriteAndExactSequence() throws {
    let (coordinator, root) = try makeCoordinator()
    let path = root.appendingPathComponent("installed/a.bin").path
    let payload = Data(repeating: 247, count: 65536)
    let begin = try value(invoke(coordinator, "file:begin", [
      "mode": "write", "destination": "gp-next", "path": path,
      "totalBytes": payload.count,
    ]))
    let handle = try XCTUnwrap(begin["handle"] as? String)
    XCTAssertThrowsError(try invoke(coordinator, "file:chunk", [
      "handle": handle, "index": 1, "offset": 0, "data": payload.base64EncodedString(),
    ]))
    _ = try invoke(coordinator, "file:chunk", [
      "handle": handle, "index": 0, "offset": 0, "data": payload.base64EncodedString(),
    ])
    _ = try invoke(coordinator, "file:finish", ["handle": handle, "action": "commit"])
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), payload)
    _ = try invoke(coordinator, "file:finish", ["handle": handle, "action": "commit"])
    _ = try invoke(coordinator, "file:finish", ["handle": handle, "action": "cancel"])
    let read = try value(invoke(coordinator, "file:begin", [
      "mode": "read", "destination": "gp-next", "path": path,
    ]))
    XCTAssertEqual(read["sizeBytes"] as? Int, payload.count)
    let readHandle = try XCTUnwrap(read["handle"] as? String)
    let chunk = try value(invoke(coordinator, "file:chunk", [
      "handle": readHandle, "index": 0, "offset": 0, "length": 65536,
    ]))
    XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(chunk["data"] as? String)), payload)
    _ = try invoke(coordinator, "file:finish", ["handle": readHandle, "action": "close"])
    _ = try invoke(coordinator, "file:finish", ["handle": readHandle, "action": "close"])
    _ = try invoke(coordinator, "file:finish", ["handle": readHandle, "action": "cancel"])
    XCTAssertThrowsError(try invoke(coordinator, "file:finish", ["handle": readHandle, "action": "commit"]))
  }

  func testEmptyExportWorksWithoutGpAndWaitsForPickerAction() throws {
    let (coordinator, _) = try makeCoordinator(gp: false)
    let begin = try value(invoke(coordinator, "file:begin", [
      "mode": "write", "destination": "export", "totalBytes": 0,
      "suggestedFilename": "../存档.json",
    ]))
    let handle = try XCTUnwrap(begin["handle"] as? String)
    let action = try invoke(coordinator, "file:finish", ["handle": handle, "action": "commit"])
    guard case .exportFile(let url) = action else { return XCTFail("Expected save picker") }
    XCTAssertTrue(try Data(contentsOf: url).isEmpty)
    XCTAssertEqual(url.lastPathComponent, "存档.json")
    XCTAssertEqual(coordinator.exportHandle(for: url), handle)
    XCTAssertThrowsError(try invoke(coordinator, "file:finish", ["handle": handle, "action": "commit"]))
    XCTAssertEqual(coordinator.exportHandle(for: url), handle)
    XCTAssertThrowsError(try invoke(coordinator, "file:begin", [
      "mode": "read", "destination": "gp-next", "path": "gp-next/a",
    ]))
  }

  func testBoundsAndIncompleteWriteStayAtomic() throws {
    let (coordinator, root) = try makeCoordinator()
    let path = root.appendingPathComponent("packs/b.bin").path
    let begin = try value(invoke(coordinator, "file:begin", [
      "mode": "write", "destination": "gp-next", "path": path, "totalBytes": 2,
    ]))
    let handle = try XCTUnwrap(begin["handle"] as? String)
    XCTAssertThrowsError(try invoke(coordinator, "file:chunk", [
      "handle": handle, "index": 0, "offset": 0,
      "data": Data(repeating: 0, count: 65537).base64EncodedString(),
    ]))
    _ = try invoke(coordinator, "file:chunk", [
      "handle": handle, "index": 0, "offset": 0, "data": "AQ==",
    ])
    XCTAssertThrowsError(try invoke(coordinator, "file:finish", ["handle": handle, "action": "commit"]))
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    _ = try invoke(coordinator, "file:chunk", [
      "handle": handle, "index": 1, "offset": 1, "data": "Ag==",
    ])
    _ = try invoke(coordinator, "file:finish", ["handle": handle, "action": "commit"])
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data([1, 2]))
  }
  func testGpSaveDialogCommitsThroughTheSameFileTasks() throws {
    let (coordinator, _) = try makeCoordinator()
    let saved = expectation(description: "save dialog")
    var path: String?
    coordinator.submitGpNext([
      "command": "plugin:dialog|save", "args": ["options": ["defaultPath": "gp-save.json"]],
    ]) { result in
      if case .success(.value(let value)) = result { path = value as? String }
      saved.fulfill()
    }
    wait(for: [saved], timeout: 3)
    let begin = try value(invoke(coordinator, "file:begin", [
      "mode": "write", "destination": "gp-next", "path": try XCTUnwrap(path), "totalBytes": 0,
    ]))
    let action = try invoke(coordinator, "file:finish", [
      "handle": try XCTUnwrap(begin["handle"] as? String), "action": "commit",
    ])
    guard case .exportFile(let file) = action else { return XCTFail("Save did not request native picker") }
    XCTAssertEqual(file.path, path)
    XCTAssertTrue(try Data(contentsOf: file).isEmpty)
  }

  func testReadHandleLimitAndCancellation() throws {
    let (coordinator, root) = try makeCoordinator()
    let file = root.appendingPathComponent("packs/read-limit.bin")
    try Data([1, 2, 3]).write(to: file)
    var handles: [String] = []
    for _ in 0..<8 {
      let begin = try value(invoke(coordinator, "file:begin", [
        "mode": "read", "destination": "gp-next", "path": file.path,
      ]))
      handles.append(try XCTUnwrap(begin["handle"] as? String))
    }
    XCTAssertThrowsError(try invoke(coordinator, "file:begin", [
      "mode": "read", "destination": "gp-next", "path": file.path,
    ]))
    _ = try invoke(coordinator, "file:finish", ["handle": handles[0], "action": "cancel"])
    XCTAssertThrowsError(try invoke(coordinator, "file:chunk", [
      "handle": handles[0], "index": 0, "offset": 0, "length": 1,
    ]))
    for handle in handles.dropFirst() {
      _ = try invoke(coordinator, "file:finish", ["handle": handle, "action": "close"])
    }
  }

  func testRejectsRootWritesBooleanSizesAndForeignHandles() throws {
    let (coordinator, root) = try makeCoordinator()
    for size: Any in [true, 0.5, 512 * 1024 * 1024 + 1] {
      XCTAssertThrowsError(try invoke(coordinator, "file:begin", [
        "mode": "write", "destination": "gp-next", "path": root.appendingPathComponent("invalid.bin").path,
        "totalBytes": size,
      ]))
    }
    XCTAssertThrowsError(try invoke(coordinator, "file:begin", [
      "mode": "write", "destination": "gp-next", "path": root.path, "totalBytes": 0,
    ]))
    XCTAssertThrowsError(try invoke(coordinator, "file:finish", ["handle": "other-session", "action": "cancel"]))
  }

  func testDestroySuppressesAlreadyQueuedRepliesForReadTasks() throws {
    let (coordinator, root) = try makeCoordinator()
    let file = root.appendingPathComponent("packs/destroy-read.bin")
    try Data([1]).write(to: file)
    let begin = try value(invoke(coordinator, "file:begin", [
      "mode": "read", "destination": "gp-next", "path": file.path,
    ]))
    let reply = expectation(description: "destroyed read has no late reply")
    reply.isInverted = true
    coordinator.submit(command: "file:chunk", arguments: [
      "handle": try XCTUnwrap(begin["handle"] as? String), "index": 0, "offset": 0, "length": 1,
    ]) { _ in reply.fulfill() }
    coordinator.destroy()
    wait(for: [reply], timeout: 0.1)
  }

  func testGpControlCommandsKeepLegacyImportAndModernModSelectionSeparate() throws {
    let (coordinator, _) = try makeCoordinator()
    guard case .importPackages = try invokeGp(coordinator, "plugin:opener|open_path") else {
      return XCTFail("Legacy pack import was changed")
    }
    guard case .openSelection(let directory) = try invokeGp(coordinator, "plugin:dialog|open", [
      "options": ["directory": true, "multiple": false],
    ]) else { return XCTFail("Expected modern Mod selection") }
    XCTAssertTrue(directory)
    XCTAssertThrowsError(try invokeGp(coordinator, "plugin:dialog|open", ["options": ["multiple": true]]))
    for command in ["plugin:fs|read_file", "plugin:fs|write_file", "plugin:fs|write_text_file"] {
      XCTAssertThrowsError(try invokeGp(coordinator, command))
    }
  }

  func testCancelledSelectionAndImportDoNoFileWork() throws {
    let root = URL(fileURLWithPath: "/private/tmp/gardendless-cancelled-\(UUID().uuidString)/gp-next")
    let missing = root.appendingPathComponent("missing.zip")
    let stager = GpNextSelectionStager(gpNextRoot: root)
    XCTAssertThrowsError(try stager.stage(missing, directory: false, isCancelled: { true }))
    let importer = GpNextPackageImporter(gpNextRoot: root)
    XCTAssertThrowsError(try importer.importPackage(missing, isCancelled: { true }) { _ in true })
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }

  func testWriteRejectsDanglingParentSymlinkBeforeCreatingOutsideDirectory() throws {
    let (coordinator, root) = try makeCoordinator()
    let outside = root.deletingLastPathComponent().appendingPathComponent("outside-not-created")
    let link = root.appendingPathComponent("packs/dangling")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    XCTAssertThrowsError(try invoke(coordinator, "file:begin", [
      "mode": "write", "destination": "gp-next", "path": link.appendingPathComponent("escape.bin").path,
      "totalBytes": 0,
    ]))
    XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
  }

  func testExpiredReadClosesItsHandleAndKeepsCancellationIdempotent() throws {
    let clock = FileTestClock()
    let (coordinator, root) = try makeCoordinator(clock: { clock.read() })
    let file = root.appendingPathComponent("packs/expiry.bin")
    try Data([7]).write(to: file)
    let begin = try value(invoke(coordinator, "file:begin", [
      "mode": "read", "destination": "gp-next", "path": file.path,
    ]))
    let handle = try XCTUnwrap(begin["handle"] as? String)
    clock.advance(601)
    XCTAssertThrowsError(try invoke(coordinator, "file:chunk", [
      "handle": handle, "index": 0, "offset": 0, "length": 1,
    ]))
    XCTAssertThrowsError(try invoke(coordinator, "file:finish", ["handle": handle, "action": "close"]))
    _ = try invoke(coordinator, "file:finish", ["handle": handle, "action": "cancel"])
    _ = try invoke(coordinator, "file:finish", ["handle": handle, "action": "cancel"])
    let reopened = try value(invoke(coordinator, "file:begin", [
      "mode": "read", "destination": "gp-next", "path": file.path,
    ]))
    _ = try invoke(coordinator, "file:finish", [
      "handle": try XCTUnwrap(reopened["handle"] as? String), "action": "close",
    ])
    XCTAssertEqual(try Data(contentsOf: file), Data([7]))
  }

}

private final class FileTestClock {
  private let lock = NSLock()
  private var time: TimeInterval = 1
  func read() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return time }
  func advance(_ amount: TimeInterval) { lock.lock(); defer { lock.unlock() }; time += amount }
}
