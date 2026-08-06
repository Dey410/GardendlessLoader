import Foundation
import GardendlessCore

public struct ZipEntry {
  public let name: String
  public let compressionMethod: UInt16
  public let compressedSize: UInt64
  public let uncompressedSize: UInt64
  public let localHeaderOffset: UInt64
  public let externalAttributes: UInt32

  public init(
    name: String,
    compressionMethod: UInt16,
    compressedSize: UInt64,
    uncompressedSize: UInt64,
    localHeaderOffset: UInt64,
    externalAttributes: UInt32
  ) {
    self.name = name
    self.compressionMethod = compressionMethod
    self.compressedSize = compressedSize
    self.uncompressedSize = uncompressedSize
    self.localHeaderOffset = localHeaderOffset
    self.externalAttributes = externalAttributes
  }

  public var isDirectory: Bool {
    name.hasSuffix("/")
  }

  public var isSymbolicLink: Bool {
    ((externalAttributes >> 16) & 0o170000) == 0o120000
  }
}

public enum ZipArchiveReader {
  public static func read(from url: URL) throws -> [ZipEntry] {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let fileSize = (attributes[.size] as? NSNumber)?.uint64Value,
          fileSize >= UInt64(ZipImportLimits.eocdMinimumLength) else {
      throw GameError.failed(.zipInvalid, "无效的 ZIP 文件")
    }

    let zipFile = try FileHandle(forReadingFrom: url)
    defer { zipFile.closeFile() }

    let tailLength = min(
      fileSize,
      UInt64(
        ZipImportLimits.eocdMinimumLength
          + ZipImportLimits.eocdMaximumCommentLength
      )
    )
    zipFile.seek(toFileOffset: fileSize - tailLength)
    let tail = zipFile.readData(ofLength: Int(tailLength))
    let eocdOffset = try endOfCentralDirectoryOffset(in: tail)

    let totalEntries = uint16(tail, eocdOffset + 10)
    let centralDirectorySize = uint32(tail, eocdOffset + 12)
    let centralDirectoryOffset = uint32(tail, eocdOffset + 16)
    if totalEntries == UInt16.max
        || centralDirectorySize == UInt32.max
        || centralDirectoryOffset == UInt32.max {
      throw GameError.failed(.zipUnsupported, "暂不支持 ZIP64 格式")
    }

    zipFile.seek(toFileOffset: UInt64(centralDirectoryOffset))
    var entries: [ZipEntry] = []
    entries.reserveCapacity(Int(totalEntries))
    for _ in 0..<totalEntries {
      let header = try readData(from: zipFile, length: ZipImportLimits.centralHeaderLength)
      guard uint32(header, 0) == 0x02014b50 else {
        throw GameError.failed(.zipInvalid, "无效的 ZIP 中央目录")
      }

      let flags = uint16(header, 8)
      if flags & 0x0001 != 0 {
        throw GameError.failed(.zipEncrypted, "选择的 ZIP 已加密，无法导入")
      }

      let compressionMethod = uint16(header, 10)
      let compressedSize = uint32(header, 20)
      let uncompressedSize = uint32(header, 24)
      let fileNameLength = Int(uint16(header, 28))
      let extraLength = Int(uint16(header, 30))
      let commentLength = Int(uint16(header, 32))
      let externalAttributes = uint32(header, 38)
      let localHeaderOffset = uint32(header, 42)
      if compressedSize == UInt32.max
          || uncompressedSize == UInt32.max
          || localHeaderOffset == UInt32.max {
        throw GameError.failed(.zipUnsupported, "暂不支持 ZIP64 格式")
      }

      let nameData = try readData(from: zipFile, length: fileNameLength)
      let nameEncoding: String.Encoding = flags & 0x0800 == 0 ? .isoLatin1 : .utf8
      guard let name = String(data: nameData, encoding: nameEncoding)
              ?? String(data: nameData, encoding: .utf8) else {
        throw GameError.failed(.zipInvalid, "选择的 ZIP 包含无法识别的文件名")
      }

      if extraLength + commentLength > 0 {
        zipFile.seek(
          toFileOffset: zipFile.offsetInFile
            + UInt64(extraLength + commentLength)
        )
      }

      entries.append(
        ZipEntry(
          name: name,
          compressionMethod: compressionMethod,
          compressedSize: UInt64(compressedSize),
          uncompressedSize: UInt64(uncompressedSize),
          localHeaderOffset: UInt64(localHeaderOffset),
          externalAttributes: externalAttributes
        )
      )
    }
    return entries
  }

  private static func endOfCentralDirectoryOffset(in data: Data) throws -> Int {
    if data.count < ZipImportLimits.eocdMinimumLength {
      throw GameError.failed(.zipInvalid, "无效的 ZIP 文件")
    }
    for offset in stride(
      from: data.count - ZipImportLimits.eocdMinimumLength,
      through: 0,
      by: -1
    ) {
      guard uint32(data, offset) == 0x06054b50 else { continue }
      let commentLength = Int(uint16(data, offset + 20))
      if offset + ZipImportLimits.eocdMinimumLength + commentLength == data.count {
        return offset
      }
    }
    throw GameError.failed(.zipInvalid, "无效的 ZIP 文件")
  }

  static func localFileDataOffset(
    for entry: ZipEntry,
    in zipFile: FileHandle
  ) throws -> UInt64 {
    zipFile.seek(toFileOffset: entry.localHeaderOffset)
    let header = try readData(from: zipFile, length: ZipImportLimits.localHeaderLength)
    guard uint32(header, 0) == 0x04034b50 else {
      throw GameError.failed(.zipInvalid, "无效的 ZIP 本地文件头")
    }
    let fileNameLength = UInt64(uint16(header, 26))
    let extraLength = UInt64(uint16(header, 28))
    return entry.localHeaderOffset
      + UInt64(ZipImportLimits.localHeaderLength)
      + fileNameLength
      + extraLength
  }

  static func readData(from file: FileHandle, length: Int) throws -> Data {
    let data = file.readData(ofLength: length)
    guard data.count == length else {
      throw GameError.failed(.zipInvalid, "ZIP 文件内容不完整")
    }
    return data
  }

  static func uint16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
  }

  static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
      | UInt32(data[offset + 1]) << 8
      | UInt32(data[offset + 2]) << 16
      | UInt32(data[offset + 3]) << 24
  }
}
