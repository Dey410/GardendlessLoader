import Foundation
import GardendlessCore
import GardendlessGPNext
import GardendlessImport
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

  func testFileSystemSupports015MetadataAndAtomicInstallCommands() throws {
    let fs = try GpNextFileSystem(session: session)
    let pending = session.gpNextRoot
      .appendingPathComponent("installed/pending-test")
      .path
    let installed = session.gpNextRoot
      .appendingPathComponent("installed/final-test")
      .path
    let payload = session.gpNextRoot
      .appendingPathComponent("installed/pending-test/mod.js")
      .path

    try fs.mkdir(path: pending, options: ["baseDir": 14])
    try fs.writeFile(
      path: payload,
      bytes: Array("export {}".utf8),
      options: ["baseDir": 14]
    )

    let metadata = try fs.lstat(path: payload, options: ["baseDir": 14])
    XCTAssertEqual(metadata["isFile"] as? Bool, true)
    XCTAssertEqual(metadata["isDirectory"] as? Bool, false)
    XCTAssertEqual(metadata["isSymlink"] as? Bool, false)
    XCTAssertEqual(metadata["size"] as? NSNumber, 9)

    try fs.rename(
      oldPath: pending,
      newPath: installed,
      options: ["oldPathBaseDir": 14, "newPathBaseDir": 14]
    )
    XCTAssertFalse(try fs.exists(path: pending, options: [:]))
    XCTAssertTrue(try fs.exists(path: installed, options: [:]))
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

  func testSelectionStagerUsesThe015SelectionNamesAndCleansPreviousData() throws {
    let sourceDirectory = root.appendingPathComponent("source-mod")
    try FileManager.default.createDirectory(
      at: sourceDirectory,
      withIntermediateDirectories: true
    )
    try Data("export {}".utf8).write(
      to: sourceDirectory.appendingPathComponent("mod.js")
    )
    let zip = root.appendingPathComponent("mod.zip")
    try Data("zip".utf8).write(to: zip)
    let stager = GpNextSelectionStager(gpNextRoot: session.gpNextRoot)

    let directory = try stager.stage(sourceDirectory, directory: true)
    XCTAssertEqual(directory.lastPathComponent, "selection")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("mod.js").path
      )
    )

    let archive = try stager.stage(zip, directory: false)
    XCTAssertEqual(archive.lastPathComponent, "selection.zip")
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    try stager.clear()
    XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
  }

  func testPackageImporterNormalizesOneWrapperDirectory() throws {
    let wrapped = root.appendingPathComponent("wrapped.zip")
    try TestZipWriter.write(
      [
        .file(
          "Amber 2.0/pack.json",
          data: Data(#"{"name":"Amber"}"#.utf8)
        ),
        .file(
          "Amber 2.0/jsons/config/patching.json",
          data: Data(#"{"defaultMode":"merge"}"#.utf8)
        ),
        .file("Amber 2.0/jsons/.DS_Store", data: Data("junk".utf8)),
        .file("__MACOSX/._Amber 2.0", data: Data("junk".utf8)),
      ],
      to: wrapped
    )

    let importer = GpNextPackageImporter(gpNextRoot: session.gpNextRoot)
    _ = try importer.importPackage(wrapped) { _ in true }

    let destination = session.gpNextRoot
      .appendingPathComponent("packs/wrapped.zip")
    let entries = try ZipArchiveReader.read(from: destination)
      .filter { !$0.isDirectory }
      .map(\.name)
      .sorted()
    XCTAssertEqual(
      entries,
      ["jsons/config/patching.json", "pack.json"]
    )
  }

  func testPackageImporterRejectsAmbiguousWrapperDirectories() throws {
    let ambiguous = root.appendingPathComponent("ambiguous.zip")
    try TestZipWriter.write(
      [
        .file("Amber/pack.json", data: Data("{}".utf8)),
        .file("Other/readme.txt", data: Data("other".utf8)),
      ],
      to: ambiguous
    )

    let importer = GpNextPackageImporter(gpNextRoot: session.gpNextRoot)
    XCTAssertThrowsError(
      try importer.importPackage(ambiguous) { _ in true }
    )
  }

  func testPackageImporterRejectsPathsThatCollideAfterNormalization() throws {
    let duplicate = root.appendingPathComponent("duplicate.zip")
    try TestZipWriter.write(
      [
        .file("Amber/pack.json", data: Data("{}".utf8)),
        .file("Amber/jsons/a.json", data: Data("{}".utf8)),
        .file("Amber/jsons/./a.json", data: Data("{}".utf8)),
      ],
      to: duplicate
    )

    let importer = GpNextPackageImporter(gpNextRoot: session.gpNextRoot)
    XCTAssertThrowsError(
      try importer.importPackage(duplicate) { _ in true }
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

  func testRouterSupports015OpenAndBinaryInstallCommands() throws {
    let router = try GpNextCommandRouter(session: session)

    let directory = try router.dispatch([
      "command": "plugin:dialog|open",
      "args": [
        "options": ["directory": true, "recursive": true, "multiple": false]
      ],
      "options": [:] as [String: Any],
    ])
    guard case .openSelection(let isDirectory) = directory else {
      return XCTFail("expected openSelection action")
    }
    XCTAssertTrue(isDirectory)

    let path = session.gpNextRoot
      .appendingPathComponent("installed/pending-test/mod.js")
      .path
    _ = try router.dispatch([
      "command": "plugin:fs|write_file",
      "args": [
        "__gardendlessBytes": Array("x".utf8).map { NSNumber(value: $0) },
      ],
      "options": [
        "headers": [
          "path": path.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
          )!,
          "options": "{\"baseDir\":14}",
        ],
      ] as [String: Any],
    ])
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("x".utf8))
  }

  func testRouterStreamsLarge015BinaryWritesInBoundedChunks() throws {
    let router = try GpNextCommandRouter(session: session)
    let path = session.gpNextRoot
      .appendingPathComponent("installed/pending-test/large.bin")
      .path
    let payload = [UInt8](repeating: 255, count: 220 * 1024)
    let chunkSize = 96 * 1024
    var index = 0
    for offset in stride(from: 0, to: payload.count, by: chunkSize) {
      let end = min(payload.count, offset + chunkSize)
      _ = try router.dispatch([
        "command": "plugin:fs|write_file",
        "args": [
          "__gardendlessBytes": payload[offset..<end].map {
            NSNumber(value: $0)
          },
          "__gardendlessTransfer": [
            "token": "gp-write-test",
            "index": index,
            "totalBytes": payload.count,
            "final": end == payload.count,
          ],
        ],
        "options": [
          "headers": [
            "path": path.addingPercentEncoding(
              withAllowedCharacters: .alphanumerics
            )!,
            "options": "{\"baseDir\":14}",
          ],
        ] as [String: Any],
      ])
      index += 1
    }
    XCTAssertEqual(
      try Data(contentsOf: URL(fileURLWithPath: path)),
      Data(payload)
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
