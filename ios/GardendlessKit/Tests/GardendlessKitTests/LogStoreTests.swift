import Foundation
import GardendlessLogging
import XCTest

final class LogStoreTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-log-\(UUID().uuidString)")
  }

  override func tearDownWithError() throws {
    if directory != nil {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  private func makeStore(
    segmentBytes: Int = 2 * 1024 * 1024,
    pendingSoftLimit: Int = 1000,
    pendingHardLimit: Int = 1100
  ) -> LogStore {
    LogStore(
      directory: directory,
      segmentBytes: segmentBytes,
      pendingSoftLimit: pendingSoftLimit,
      pendingHardLimit: pendingHardLimit
    )
  }

  func testInitializeWritesMarkerAndSessionStartedEvent() {
    let store = makeStore()
    store.initialize()
    _ = store.flush(timeout: 2)

    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("active-session.json").path
      )
    )
    let snapshot = store.snapshot()
    let events = snapshot["events"] as? [[String: Any]] ?? []
    XCTAssertTrue(
      events.contains {
        ($0["event"] as? String) == "app_session_started"
      }
    )
    XCTAssertNotEqual(snapshot["appSessionId"] as? String, "unavailable")
  }

  func testEmitPersistsSchemaV1JsonlAndSnapshot() {
    let store = makeStore()
    store.initialize()
    store.emit([
      "source": "dart",
      "level": "ERROR",
      "category": "game.host",
      "event": "game_host_launch_finished",
      "outcome": "failed",
      "code": "resource_validation_failed",
      "gameSessionId": "session-9",
      "context": ["activeSlot": "slot-a"],
    ])
    _ = store.flush(timeout: 2)

    let files = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    let logFile = try? XCTUnwrap(
      files?.first { $0.pathExtension == "jsonl" }
    )
    let text = try? String(contentsOf: logFile!, encoding: .utf8)
    XCTAssertNotNil(text)
    let lines = text?.split(whereSeparator: \.isNewline) ?? []
    let lastLine = lines.last.map(String.init) ?? ""
    let decoded = try? JSONSerialization.jsonObject(
      with: Data(lastLine.utf8)
    ) as? [String: Any]
    XCTAssertEqual(decoded?["schemaVersion"] as? Int, 1)
    XCTAssertEqual(
      decoded?["event"] as? String,
      "game_host_launch_finished"
    )
    XCTAssertEqual(decoded?["gameSessionId"] as? String, "session-9")

    let snapshot = store.snapshot()
    let events = snapshot["events"] as? [[String: Any]] ?? []
    XCTAssertTrue(
      events.contains {
        ($0["event"] as? String) == "game_host_launch_finished"
      }
    )
  }

  func testSanitizesSecretsAndUserPaths() {
    let store = makeStore()
    store.initialize()
    store.emit([
      "source": "ios",
      "level": "INFO",
      "category": "test",
      "event": "test_event",
      "outcome": "observed",
      "message": "token=abc123 path=/Users/xiaozhu/secret.txt",
      "context": [
        "password": "hunter2",
        "apiKey": "k-123",
        "safe": "kept",
        "path": "/Users/xiaozhu/Documents",
      ],
    ])
    _ = store.flush(timeout: 2)

    let snapshot = store.snapshot()
    let events = snapshot["events"] as? [[String: Any]] ?? []
    let event = try! XCTUnwrap(
      events.first { ($0["event"] as? String) == "test_event" }
    )
    XCTAssertEqual(
      event["message"] as? String,
      "token=<redacted> path=/<user-home>/secret.txt"
    )
    let context = event["context"] as? [String: Any]
    XCTAssertNil(context?["password"])
    XCTAssertNil(context?["apiKey"])
    XCTAssertEqual(context?["safe"] as? String, "kept")
    XCTAssertEqual(context?["path"] as? String, "/<user-home>/Documents")
  }

  func testRotationCreatesMultipleSegments() {
    let store = makeStore(segmentBytes: 128)
    store.initialize()
    for index in 0..<5 {
      store.emit([
        "source": "ios",
        "level": "INFO",
        "category": "test",
        "event": "segment_event",
        "outcome": "observed",
        "message": String(repeating: "x", count: 200) + "\(index)",
      ])
    }
    _ = store.flush(timeout: 2)
    let files = try! FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    let segments = files.filter {
      $0.pathExtension == "jsonl" && $0.lastPathComponent.contains("\(store.appSessionId)-")
    }
    XCTAssertGreaterThan(segments.count, 1)
  }

  func testDeleteHistoryKeepsOnlyCurrentSession() {
    let store = makeStore()
    store.initialize()
    store.emit([
      "source": "ios",
      "level": "INFO",
      "category": "test",
      "event": "current_event",
      "outcome": "observed",
    ])
    _ = store.flush(timeout: 2)

    let old = directory.appendingPathComponent("app-20260101-000000-aaaaaa-000.jsonl")
    try! Data("{}\n".utf8).write(to: old)
    store.deleteHistory()
    _ = store.flush(timeout: 2)

    XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    let currentFiles = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )) ?? []
    XCTAssertTrue(
      currentFiles.contains {
        $0.lastPathComponent.hasPrefix("app-\(store.appSessionId)-")
      }
    )
  }

  func testEndSessionRemovesMarker() {
    let store = makeStore()
    store.initialize()
    store.endSession()
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("active-session.json").path
      )
    )
  }

  func testDropProtectionCountsDroppedEvents() {
    let store = makeStore(pendingSoftLimit: 5, pendingHardLimit: 8)
    store.initialize()
    for index in 0..<30 {
      store.emit([
        "source": "ios",
        "level": "INFO",
        "category": "test",
        "event": "flood_\(index)",
        "outcome": "observed",
      ])
    }
    _ = store.flush(timeout: 5)
    let snapshot = store.snapshot()
    let dropped = snapshot["droppedByLevel"] as? [String: Int] ?? [:]
    XCTAssertGreaterThan(dropped["INFO"] ?? 0, 0)
  }

  func testCleanupRemovesExpiredFiles() {
    let old = directory.appendingPathComponent("app-20200101-000000-aaaaaa-000.jsonl")
    try! FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try! Data("old\n".utf8).write(to: old)
    let past = Date(timeIntervalSinceNow: -8 * 24 * 60 * 60)
    try! FileManager.default.setAttributes(
      [.modificationDate: past],
      ofItemAtPath: old.path
    )

    let store = makeStore()
    store.initialize()
    _ = store.flush(timeout: 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
  }
}
