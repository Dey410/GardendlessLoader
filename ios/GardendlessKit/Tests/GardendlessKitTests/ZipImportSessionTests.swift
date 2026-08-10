import Compression
import Foundation
import GardendlessCore
import GardendlessImport
import XCTest

struct ZipTestEntry {
  let name: String
  let data: Data?
  let deflate: Bool
  let rawDeflatePayload: Data?
  let rawDeflateUncompressedSize: UInt32?
  let flags: UInt16
  let externalAttributes: UInt32

  static func file(
    _ name: String,
    data: Data,
    deflate: Bool = false,
    flags: UInt16 = 0x0800,
    externalAttributes: UInt32 = 0
  ) -> ZipTestEntry {
    ZipTestEntry(
      name: name,
      data: data,
      deflate: deflate,
      rawDeflatePayload: nil,
      rawDeflateUncompressedSize: nil,
      flags: flags,
      externalAttributes: externalAttributes
    )
  }

  static func rawDeflateFile(
    _ name: String,
    compressed: Data,
    uncompressedSize: UInt32,
    flags: UInt16 = 0x0800,
    externalAttributes: UInt32 = 0
  ) -> ZipTestEntry {
    ZipTestEntry(
      name: name,
      data: Data(),
      deflate: true,
      rawDeflatePayload: compressed,
      rawDeflateUncompressedSize: uncompressedSize,
      flags: flags,
      externalAttributes: externalAttributes
    )
  }

  static func directory(
    _ name: String,
    flags: UInt16 = 0x0800,
    externalAttributes: UInt32 = 0
  ) -> ZipTestEntry {
    ZipTestEntry(
      name: name,
      data: nil,
      deflate: false,
      rawDeflatePayload: nil,
      rawDeflateUncompressedSize: nil,
      flags: flags,
      externalAttributes: externalAttributes
    )
  }
}

enum TestZipWriter {
  static func write(_ entries: [ZipTestEntry], to url: URL) throws {
    var locals = Data()
    var centrals = Data()
    var offset: UInt32 = 0

    for entry in entries {
      let isDirectory = entry.data == nil
      let nameData = Data(
        (isDirectory ? entry.name + "/" : entry.name).utf8
      )
      var payload = entry.data ?? Data()
      var uncompressedSize = (entry.data ?? Data()).count
      var method: UInt16 = 0
      if let rawDeflatePayload = entry.rawDeflatePayload {
        payload = rawDeflatePayload
        uncompressedSize = Int(entry.rawDeflateUncompressedSize ?? 0)
        method = 8
      } else if let source = entry.data, entry.deflate {
        payload = try deflate(source)
        method = 8
      }

      let local = localHeader(
        nameData: nameData,
        method: method,
        compressedSize: UInt32(payload.count),
        uncompressedSize: UInt32(uncompressedSize),
        flags: entry.flags
      )
      locals.append(local)
      locals.append(payload)

      centrals.append(
        centralHeader(
          nameData: nameData,
          method: method,
          compressedSize: UInt32(payload.count),
          uncompressedSize: UInt32(uncompressedSize),
          flags: entry.flags,
          externalAttributes: entry.externalAttributes,
          localOffset: offset
        )
      )
      offset += UInt32(local.count + payload.count)
    }

    var archive = Data()
    archive.append(locals)
    let centralOffset = UInt32(archive.count)
    archive.append(centrals)
    archive.append(
      eocd(
        entryCount: UInt16(entries.count),
        centralSize: UInt32(centrals.count),
        centralOffset: centralOffset
      )
    )
    try archive.write(to: url)
  }

  private static func localHeader(
    nameData: Data,
    method: UInt16,
    compressedSize: UInt32,
    uncompressedSize: UInt32,
    flags: UInt16
  ) -> Data {
    var data = Data()
    data.append(le32(0x04034b50))
    data.append(le16(20))
    data.append(le16(flags))
    data.append(le16(method))
    data.append(le16(0))
    data.append(le16(0))
    data.append(le32(0))
    data.append(le32(compressedSize))
    data.append(le32(uncompressedSize))
    data.append(le16(UInt16(nameData.count)))
    data.append(le16(0))
    data.append(nameData)
    return data
  }

  private static func centralHeader(
    nameData: Data,
    method: UInt16,
    compressedSize: UInt32,
    uncompressedSize: UInt32,
    flags: UInt16,
    externalAttributes: UInt32,
    localOffset: UInt32
  ) -> Data {
    var data = Data()
    data.append(le32(0x02014b50))
    data.append(le16(20))
    data.append(le16(20))
    data.append(le16(flags))
    data.append(le16(method))
    data.append(le16(0))
    data.append(le16(0))
    data.append(le32(0))
    data.append(le32(compressedSize))
    data.append(le32(uncompressedSize))
    data.append(le16(UInt16(nameData.count)))
    data.append(le16(0))
    data.append(le16(0))
    data.append(le16(0))
    data.append(le16(0))
    data.append(le32(externalAttributes))
    data.append(le32(localOffset))
    data.append(nameData)
    return data
  }

  private static func eocd(
    entryCount: UInt16,
    centralSize: UInt32,
    centralOffset: UInt32
  ) -> Data {
    var data = Data()
    data.append(le32(0x06054b50))
    data.append(le16(0))
    data.append(le16(0))
    data.append(le16(entryCount))
    data.append(le16(entryCount))
    data.append(le32(centralSize))
    data.append(le32(centralOffset))
    data.append(le16(0))
    return data
  }

  private static func deflate(_ data: Data) throws -> Data {
    let source = [UInt8](data)
    var destination = [UInt8](repeating: 0, count: source.count + 1024)
    let written = compression_encode_buffer(
      &destination,
      destination.count,
      source,
      source.count,
      nil,
      COMPRESSION_ZLIB
    )
    guard written > 4 else {
      throw GameError.failed(.zipInvalid, "Unable to create test deflate data")
    }
    // Apple's COMPRESSION_ZLIB encoder emits raw DEFLATE compatible with the
    // -MAX_WBITS inflate path used for ZIP entries.
    return Data(destination[0..<written])
  }

  private static func le16(_ value: UInt16) -> Data {
    Data([UInt8(value & 0xff), UInt8(value >> 8)])
  }

  private static func le32(_ value: UInt32) -> Data {
    Data([
      UInt8(value & 0xff),
      UInt8((value >> 8) & 0xff),
      UInt8((value >> 16) & 0xff),
      UInt8((value >> 24) & 0xff),
    ])
  }
}

final class ZipImportSessionTests: XCTestCase {
  private var zipURL: URL!
  private var target: URL!

  override func setUpWithError() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-zip-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    zipURL = directory.appendingPathComponent("resources.zip")
    target = directory.appendingPathComponent("slot-a")
  }

  override func tearDownWithError() throws {
    if let directory = zipURL?.deletingLastPathComponent() {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  private func docsEntries() -> [ZipTestEntry] {
    [
      .directory("release"),
      .directory("release/docs"),
      .file("release/docs/index.html", data: Data("<html>game</html>".utf8)),
      .file(
        "release/docs/src/settings.json",
        data: Data(#"{"CocosEngine":"cc","engine":{},"assets":{},"launch":{}}"#.utf8)
      ),
      .file(
        "release/docs/src/import-map.json",
        data: Data("{}".utf8)
      ),
      .file("release/docs/cocos-js/cc.js", data: Data("cc".utf8)),
      .file("release/docs/assets/tex.png", data: Data("png".utf8)),
      .file("release/other.txt", data: Data("outside".utf8)),
    ]
  }

  func testExtractsNestedDocsDirectory() throws {
    try TestZipWriter.write(docsEntries(), to: zipURL)
    var phases: [String] = []
    let session = ZipImportSession(zipURL: zipURL, targetDirectory: target)
    let result = try session.run { phases.append($0.phase) }

    XCTAssertEqual(result.path, target.path)
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: target.appendingPathComponent("index.html").path
    ))
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: target.appendingPathComponent("cocos-js/cc.js").path
    ))
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: target.appendingPathComponent("other.txt").path
    ))
    XCTAssertTrue(phases.contains("receiving"))
    XCTAssertTrue(phases.contains("extracting"))
  }

  func testPrefersDirectoryNamedDocs() throws {
    var entries = docsEntries()
    entries.append(.directory("docs"))
    entries.append(.file("docs/index.html", data: Data("<html>docs</html>".utf8)))
    entries.append(.file("docs/src/settings.json", data: Data("{}".utf8)))
    entries.append(.file("docs/src/import-map.json", data: Data("{}".utf8)))
    entries.append(.file("docs/cocos-js/cc.js", data: Data("cc".utf8)))
    entries.append(.file("docs/assets/a.png", data: Data("a".utf8)))
    try TestZipWriter.write(entries, to: zipURL)

    let session = ZipImportSession(zipURL: zipURL, targetDirectory: target)
    _ = try session.run { _ in }
    let index = try String(
      data: Data(contentsOf: target.appendingPathComponent("index.html")),
      encoding: .utf8
    )
    XCTAssertEqual(index, "<html>docs</html>")
  }

  func testDeflatedEntryExtractsCorrectly() throws {
    var entries = docsEntries()
    entries.append(
      .file(
        "release/docs/assets/compressed.bin",
        data: Data((0..<4096).map { UInt8($0 & 0xff) }),
        deflate: true
      )
    )
    try TestZipWriter.write(entries, to: zipURL)
    let session = ZipImportSession(zipURL: zipURL, targetDirectory: target)
    _ = try session.run { _ in }
    let extracted = try Data(
      contentsOf: target.appendingPathComponent("assets/compressed.bin")
    )
    XCTAssertEqual(extracted, Data((0..<4096).map { UInt8($0 & 0xff) }))
  }

  func testDeflatedEntryExactlyFillingOutputBufferIsFlushed() throws {
    var entries = docsEntries()
    let fixtureURL = Bundle.module.url(
      forResource: "boundary-64k.astc.deflate",
      withExtension: nil,
      subdirectory: "Fixtures"
    )!
    let compressed = try Data(contentsOf: fixtureURL)
    XCTAssertEqual(compressed.count, 41351)
    entries.append(
      .rawDeflateFile(
        "release/docs/assets/boundary.bin",
        compressed: compressed,
        uncompressedSize: 131088
      )
    )
    try TestZipWriter.write(entries, to: zipURL)

    let session = ZipImportSession(zipURL: zipURL, targetDirectory: target)
    _ = try session.run { _ in }

    let attributes = try FileManager.default.attributesOfItem(
      atPath: target.appendingPathComponent("assets/boundary.bin").path
    )
    XCTAssertEqual((attributes[.size] as? NSNumber)?.uint64Value, 131088)
  }

  func testRejectsTraversalPaths() throws {
    var entries = docsEntries()
    entries.append(.file("../evil.txt", data: Data("x".utf8)))
    try TestZipWriter.write(entries, to: zipURL)
    let session = ZipImportSession(zipURL: zipURL, targetDirectory: target)
    XCTAssertThrowsError(try session.run { _ in })
  }

  func testRejectsSymbolicLinkEntries() throws {
    var entries = docsEntries()
    entries.append(
      .file(
        "release/docs/link",
        data: Data("target".utf8),
        externalAttributes: (0o120000 << 16)
      )
    )
    try TestZipWriter.write(entries, to: zipURL)
    let session = ZipImportSession(zipURL: zipURL, targetDirectory: target)
    XCTAssertThrowsError(try session.run { _ in })
  }

  func testRejectsEncryptedEntries() throws {
    var entries = docsEntries()
    entries.append(
      .file(
        "release/docs/assets/secret.bin",
        data: Data([1, 2, 3]),
        flags: 0x0001
      )
    )
    try TestZipWriter.write(entries, to: zipURL)
    let session = ZipImportSession(zipURL: zipURL, targetDirectory: target)
    XCTAssertThrowsError(try session.run { _ in })
  }

  func testMissingDocsIsRejected() throws {
    try TestZipWriter.write(
      [.file("index.html", data: Data("x".utf8))],
      to: zipURL
    )
    let session = ZipImportSession(zipURL: zipURL, targetDirectory: target)
    XCTAssertThrowsError(try session.run { _ in })
  }
}
