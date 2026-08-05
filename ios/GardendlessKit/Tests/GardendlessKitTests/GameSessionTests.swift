import Foundation
import XCTest
@testable import GardendlessCore

final class GameSessionTests: XCTestCase {
  private func makeJSON(
    platform: String = "ios",
    origin: String = GameOrigin.value,
    schema: Int = GameSession.schemaVersion,
    entryURL: String = "gardendless-game://localhost/index.html?generation=7",
    hosts: [String] = ["pvzge.com", "github.com"],
    resourceRoot: String = "/tmp/gardendless/slot-a"
  ) -> [String: Any] {
    [
      "schemaVersion": schema,
      "sessionId": "session-1",
      "resourceRoot": resourceRoot,
      "platform": platform,
      "origin": origin,
      "entryPath": "index.html",
      "entryUrl": entryURL,
      "activationGeneration": 7,
      "hasGpNext": true,
      "gpNextCompatible": true,
      "gpNextVersion": "1.4.2",
      "watermarkEnabled": true,
      "autoCollectSunEnabled": false,
      "allowedRemoteHosts": hosts,
      "gpNextRoot": "/tmp/gardendless/gp-next",
      "exportTemporaryRoot": "/tmp/gardendless/gp-next/.exports",
    ]
  }

  func testDecodesValidSession() throws {
    let session = try GameSessionDecoder.decode(makeJSON())
    XCTAssertEqual(session.sessionId, "session-1")
    XCTAssertEqual(session.activationGeneration, 7)
    XCTAssertEqual(session.entryURL.scheme, "gardendless-game")
    XCTAssertEqual(session.allowedRemoteHosts, ["pvzge.com", "github.com"])
    XCTAssertEqual(session.appRoot.path, "/tmp/gardendless")
  }

  func testRejectsWrongSchemaPlatformOrOrigin() {
    XCTAssertThrowsError(
      try GameSessionDecoder.decode(makeJSON(schema: 2))
    )
    XCTAssertThrowsError(
      try GameSessionDecoder.decode(makeJSON(platform: "android"))
    )
    XCTAssertThrowsError(
      try GameSessionDecoder.decode(makeJSON(origin: "https://example.com"))
    )
  }

  func testRejectsEscapedEntryURL() {
    XCTAssertThrowsError(
      try GameSessionDecoder.decode(
        makeJSON(entryURL: "https://evil.example/index.html")
      )
    )
    XCTAssertThrowsError(
      try GameSessionDecoder.decode(
        makeJSON(entryURL: "gardendless-game://localhost/../secret")
      )
    )
  }

  func testRejectsInvalidRemoteHosts() {
    XCTAssertThrowsError(
      try GameSessionDecoder.decode(makeJSON(hosts: ["-bad.example"]))
    )
    XCTAssertThrowsError(
      try GameSessionDecoder.decode(makeJSON(hosts: ["bad..example"]))
    )
  }

  func testNormalizesHostsToLowercase() throws {
    let session = try GameSessionDecoder.decode(
      makeJSON(hosts: ["GitHub.COM", "PVZGE.com"])
    )
    XCTAssertEqual(session.allowedRemoteHosts, ["github.com", "pvzge.com"])
  }
}
