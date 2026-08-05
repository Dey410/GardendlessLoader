import Foundation
import GardendlessCore
import GardendlessGPNext
import XCTest

final class GpNextTests: XCTestCase {
  private var root: URL!
  private var session: GameSession!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-gpnext-\(UUID().uuidString)")
    let appRoot = root!
    let gpNextRoot = appRoot.appendingPathComponent("gp-next")
    try FileManager.default.createDirectory(
      at: appRoot,
      withIntermediateDirectories: true
    )
    session = GameSession(
      sessionId: "session-1",
      resourceRoot: appRoot.appendingPathComponent("slot-a"),
      entryURL: URL(
        string: "gardendless-game://localhost/index.html?generation=1"
      )!,
      activationGeneration: 1,
      hasGpNext: true,
      gpNextCompatible: true,
      gpNextVersion: "1.4.2",
      watermarkEnabled: true,
      autoCollectSunEnabled: false,
      allowedRemoteHosts: ["pvzge.com", "github.com"],
      gpNextRoot: gpNextRoot,
      exportTemporaryRoot: gpNextRoot.appendingPathComponent(".exports")
    )
  }

  override func tearDownWithError() throws {
    if root != nil {
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testFileSystemConfinesEveryPathToGpNextRoot() throws {
    let fs = try GpNextFileSystem(session: session)
    let packs = session.gpNextRoot.appendingPathComponent("packs").path
    let patches = session.gpNextRoot.appendingPathComponent("patches").path
    XCTAssertTrue(try fs.exists(path: packs, options: [:]))
    XCTAssertTrue(try fs.exists(path: patches, options: [:]))

    // Relative paths resolve against the app root and therefore stay outside
    // the gp-next sandbox unless they are absolute paths inside it.
    XCTAssertThrowsError(try fs.exists(path: "packs", options: [:]))
    let outside = root.appendingPathComponent("slot-a").path
    XCTAssertThrowsError(try fs.exists(path: outside, options: [:]))
    XCTAssertThrowsError(
      try fs.exists(
        path: packs,
        options: ["baseDir": 13]
      )
    )
  }

  func testFileSystemRoundTrip() throws {
    let fs = try GpNextFileSystem(session: session)
    let sub = session.gpNextRoot
      .appendingPathComponent("patches/sub")
      .path
    let file = session.gpNextRoot
      .appendingPathComponent("patches/sub/a.json")
      .path
    try fs.mkdir(path: sub, options: [:])
    try fs.writeFile(
      path: file,
      bytes: Array("hello".utf8),
      options: [:]
    )
    XCTAssertEqual(
      try fs.readFile(path: file, options: [:]),
      Array("hello".utf8)
    )
    let entries = try fs.readDirectory(path: sub, options: [:])
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries.first?["name"] as? String, "a.json")
    XCTAssertEqual(entries.first?["isFile"] as? Bool, true)

    try fs.remove(path: file, options: [:])
    XCTAssertFalse(try fs.exists(path: file, options: [:]))
    XCTAssertThrowsError(
      try fs.remove(path: sub, options: ["recursive": false])
    )
    try fs.remove(path: sub, options: ["recursive": true])
    XCTAssertFalse(try fs.exists(path: sub, options: [:]))
  }

  func testRemoveRejectsRootAndSymbolicLinks() throws {
    let fs = try GpNextFileSystem(session: session)
    XCTAssertThrowsError(
      try fs.remove(path: "", options: ["recursive": true])
    )
    XCTAssertThrowsError(
      try fs.remove(
        path: session.gpNextRoot.path,
        options: ["recursive": true]
      )
    )
    let outside = root.appendingPathComponent("outside.txt")
    try Data("x".utf8).write(to: outside)
    let link = session.gpNextRoot
      .appendingPathComponent("patches/link")
      .path
    try FileManager.default.createSymbolicLink(
      at: session.gpNextRoot.appendingPathComponent("patches/link"),
      withDestinationURL: outside
    )
    XCTAssertThrowsError(
      try fs.readFile(path: link, options: [:])
    )
    XCTAssertThrowsError(
      try fs.remove(path: link, options: [:])
    )
  }

  func testPackageImporterImportsAndReplacesZipPacks() throws {
    let packURL = root.appendingPathComponent("pack.zip")
    try TestZipWriter.write(
      [
        .file("pack.json", data: Data(#"{"name":"test"}"#.utf8)),
        .file("mod.js", data: Data("export{}".utf8)),
      ],
      to: packURL
    )
    let importer = GpNextPackageImporter(
      gpNextRoot: session.gpNextRoot
    )
    let name = try importer.importPackage(packURL) { _ in true }
    XCTAssertEqual(name, "pack.zip")
    let destination = session.gpNextRoot
      .appendingPathComponent("packs/pack.zip")
    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

    // Replacement is declined: original stays untouched.
    let replacementDirectory = root.appendingPathComponent("replacement")
    try FileManager.default.createDirectory(
      at: replacementDirectory,
      withIntermediateDirectories: true
    )
    let other = replacementDirectory.appendingPathComponent("pack.zip")
    try TestZipWriter.write(
      [
        .file("pack.json", data: Data(#"{"name":"other"}"#.utf8)),
      ],
      to: other
    )
    _ = try importer.importPackage(other) { _ in false }
    XCTAssertEqual(
      try Data(contentsOf: destination),
      try Data(contentsOf: packURL)
    )
    // Replacement is confirmed.
    _ = try importer.importPackage(other) { _ in true }
    XCTAssertEqual(
      try Data(contentsOf: destination),
      try Data(contentsOf: other)
    )
  }

  func testPackageImporterRejectsBadPayloads() throws {
    let importer = GpNextPackageImporter(
      gpNextRoot: session.gpNextRoot
    )
    let noPack = root.appendingPathComponent("nopack.zip")
    try TestZipWriter.write(
      [.file("mod.js", data: Data("x".utf8))],
      to: noPack
    )
    XCTAssertThrowsError(
      try importer.importPackage(noPack) { _ in true }
    )
    let badJSON = root.appendingPathComponent("bad.json")
    try Data("{".utf8).write(to: badJSON)
    XCTAssertThrowsError(
      try importer.importPackage(badJSON) { _ in true }
    )
  }

  func testRouterAllowsOnlyWhitelistedOpenURLs() throws {
    let router = try GpNextCommandRouter(session: session)
    let allowed = try router.dispatch([
      "command": "plugin:opener|open_url",
      "args": ["url": "https://github.com/Dey410/GardendlessLoader"],
      "options": [:] as [String: Any],
    ])
    guard case .openURL = allowed else {
      return XCTFail("expected openURL action")
    }
    XCTAssertThrowsError(
      try router.dispatch([
        "command": "plugin:opener|open_url",
        "args": ["url": "https://evil.example/x"],
        "options": [:] as [String: Any],
      ])
    )
  }

  func testRouterExportFlowProducesExportFile() throws {
    let router = try GpNextCommandRouter(session: session)
    let save = try router.dispatch([
      "command": "plugin:dialog|save",
      "args": ["options": ["defaultPath": "save.json"]],
      "options": [:] as [String: Any],
    ])
    guard case .value(let rawPath) = save, let path = rawPath as? String else {
      return XCTFail("expected save path")
    }
    let action = try router.dispatch([
      "command": "plugin:fs|write_text_file",
      "args": [
        "path": path,
        "__gardendlessBytes": Array("{}".utf8).map { NSNumber(value: $0) },
      ],
      "options": [
        "headers": [
          "path": path,
          "options": "{\"baseDir\":14}",
        ],
      ] as [String: Any],
    ])
    guard case .exportFile(let file) = action else {
      return XCTFail("expected exportFile action")
    }
    XCTAssertEqual(
      try Data(contentsOf: file),
      Data("{}".utf8)
    )
  }

  func testRouterRejectsUnknownCommands() throws {
    let router = try GpNextCommandRouter(session: session)
    XCTAssertThrowsError(
      try router.dispatch([
        "command": "plugin:window|close",
        "args": [:] as [String: Any],
        "options": [:] as [String: Any],
      ])
    )
  }
}
