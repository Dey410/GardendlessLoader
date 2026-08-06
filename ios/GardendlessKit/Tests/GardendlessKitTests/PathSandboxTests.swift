import Foundation
import XCTest
@testable import GardendlessCore

final class PathSandboxTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-sandbox-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    if root != nil {
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testRelativePathAndResolveSupportUnicode() throws {
    let sandbox = try PathSandbox(root: root)
    try Data("你好".utf8).write(to: root.appendingPathComponent("你好.json"))
    let url = try XCTUnwrap(
      URL(string: "gardendless-game://localhost/%E4%BD%A0%E5%A5%BD.json")
    )
    let relative = try XCTUnwrap(sandbox.relativePath(for: url))
    XCTAssertEqual(relative, "你好.json")
    XCTAssertEqual(
      sandbox.resolve(relative)?.standardizedFileURL,
      root.appendingPathComponent("你好.json").standardizedFileURL
    )
  }

  func testEmptyPathDefaultsToIndex() throws {
    let sandbox = try PathSandbox(root: root)
    XCTAssertEqual(
      sandbox.relativePath(
        for: URL(string: "gardendless-game://localhost/")!
      ),
      "index.html"
    )
  }

  func testRejectsForeignOriginAndUnsafePaths() throws {
    let sandbox = try PathSandbox(root: root)
    XCTAssertNil(
      sandbox.relativePath(for: URL(string: "gardendless-game://evil/x")!)
    )
    XCTAssertNil(
      sandbox.relativePath(
        for: URL(string: "gardendless-game://localhost/%2e%2e/secret")!
      )
    )
    XCTAssertNil(
      sandbox.relativePath(
        for: URL(string: "gardendless-game://localhost/%252e%252e/secret")!
      )
    )
    XCTAssertNil(sandbox.resolve("../secret"))
    XCTAssertNil(sandbox.resolve("a\\b"))
    XCTAssertNil(sandbox.resolve("a\0b"))
  }

  func testRejectsSymbolicLinkEscape() throws {
    let outside = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-outside-\(UUID().uuidString)")
    try Data("outside".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("linked.bin"),
      withDestinationURL: outside
    )
    let sandbox = try PathSandbox(root: root)
    XCTAssertNil(sandbox.resolve("linked.bin"))
  }

  func testFilePropertiesProduceStableEtag() throws {
    let file = root.appendingPathComponent("asset.bin")
    try Data([0, 1, 2, 3]).write(to: file)
    let sandbox = try PathSandbox(root: root)
    let first = try sandbox.fileProperties(file)
    let second = try sandbox.fileProperties(file)
    XCTAssertEqual(first.length, 4)
    XCTAssertEqual(first.etag, second.etag)
    XCTAssertTrue(first.etag.hasPrefix("\""))
    XCTAssertTrue(first.etag.hasSuffix("\""))
  }
}
