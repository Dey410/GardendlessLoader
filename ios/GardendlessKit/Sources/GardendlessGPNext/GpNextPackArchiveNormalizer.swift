import Foundation
import GardendlessCore
import GardendlessImport

enum GpNextPackArchiveNormalizer {
  static func prepare(
    _ source: URL,
    in directory: URL,
    displayName: String
  ) throws -> URL {
    let entries = try ZipArchiveReader.read(from: source)
    let selected = try normalizedEntries(entries, displayName: displayName)
    guard let selected else {
      return source
    }

    let output = directory.appendingPathComponent(
      ".\(displayName).normalized-\(UUID().uuidString)"
    )
    do {
      try writeArchive(selected, from: source, to: output)
      return output
    } catch {
      try? FileManager.default.removeItem(at: output)
      throw error
    }
  }

  private static func normalizedEntries(
    _ entries: [ZipEntry],
    displayName: String
  ) throws -> [(entry: ZipEntry, name: String)]? {
    var meaningful: [(entry: ZipEntry, path: String)] = []
    for entry in entries {
      if entry.isSymbolicLink {
        throw GameError.failed(
          .zipSymbolicLink,
          "\(displayName) 包含不支持的符号链接"
        )
      }
      let path = try DocsDirectoryFinder.safeArchivePath(entry.name)
      if isMetadataArtifact(path) {
        continue
      }
      meaningful.append((entry, path))
    }

    if meaningful.contains(where: { !$0.entry.isDirectory && $0.path == "pack.json" }) {
      return nil
    }

    let candidates = Set(
      meaningful.compactMap { item -> String? in
        guard !item.entry.isDirectory else { return nil }
        let parts = item.path.split(separator: "/")
        guard parts.count == 2, parts[1] == "pack.json" else { return nil }
        return String(parts[0])
      }
    )
    guard candidates.count == 1, let wrapper = candidates.first else {
      throw missingRootPack(displayName)
    }
    let prefix = "\(wrapper)/"
    guard meaningful.allSatisfy({ item in
      item.path == wrapper || item.path.hasPrefix(prefix)
    }) else {
      throw missingRootPack(displayName)
    }

    var names = Set<String>()
    var normalized: [(entry: ZipEntry, name: String)] = []
    for item in meaningful {
      guard item.path.hasPrefix(prefix) else { continue }
      var name = String(item.path.dropFirst(prefix.count))
      if name.isEmpty { continue }
      if item.entry.isDirectory {
        name += "/"
      }
      guard names.insert(name).inserted else {
        throw GameError.failed(
          .zipInvalid,
          "\(displayName) 规范化后包含重复路径"
        )
      }
      normalized.append((item.entry, name))
    }
    guard normalized.contains(where: {
      !$0.entry.isDirectory && $0.name == "pack.json"
    }) else {
      throw missingRootPack(displayName)
    }
    return normalized
  }

  private static func isMetadataArtifact(_ path: String) -> Bool {
    let parts = path.split(separator: "/")
    return parts.contains("__MACOSX") || parts.last == ".DS_Store"
  }

  private static func missingRootPack(_ displayName: String) -> GameError {
    GameError.failed(
      .gpNextForbidden,
      "\(displayName) 缺少根目录 pack.json，且未找到唯一的单层外壳目录"
    )
  }

  private static func writeArchive(
    _ selected: [(entry: ZipEntry, name: String)],
    from sourceURL: URL,
    to outputURL: URL
  ) throws {
    guard selected.count <= Int(UInt16.max) else {
      throw GameError.failed(.zipUnsupported, "GP-Next ZIP 文件条目过多")
    }
    guard FileManager.default.createFile(
      atPath: outputURL.path,
      contents: nil
    ) else {
      throw GameError.failed(.zipInvalid, "无法创建规范化 GP-Next ZIP")
    }

    let source = try FileHandle(forReadingFrom: sourceURL)
    let output = try FileHandle(forWritingTo: outputURL)
    defer {
      source.closeFile()
      output.closeFile()
    }

    var centralRecords: [Data] = []
    for item in selected {
      guard item.entry.compressedSize <= UInt64(UInt32.max),
            item.entry.uncompressedSize <= UInt64(UInt32.max),
            output.offsetInFile <= UInt64(UInt32.max) else {
        throw GameError.failed(.zipUnsupported, "暂不支持 ZIP64 格式")
      }
      let nameData = Data(item.name.utf8)
      guard nameData.count <= Int(UInt16.max) else {
        throw GameError.failed(.zipInvalid, "GP-Next ZIP 文件名过长")
      }
      let localOffset = UInt32(output.offsetInFile)
      let compressedSize = UInt32(item.entry.compressedSize)
      let uncompressedSize = UInt32(item.entry.uncompressedSize)

      var local = Data()
      local.appendLE(UInt32(0x04034b50))
      local.appendLE(UInt16(20))
      local.appendLE(UInt16(0x0800))
      local.appendLE(item.entry.compressionMethod)
      local.appendLE(UInt16(0))
      local.appendLE(UInt16(0))
      local.appendLE(item.entry.crc32)
      local.appendLE(compressedSize)
      local.appendLE(uncompressedSize)
      local.appendLE(UInt16(nameData.count))
      local.appendLE(UInt16(0))
      local.append(nameData)
      output.write(local)

      let dataOffset = try ZipArchiveReader.localFileDataOffset(
        for: item.entry,
        in: source
      )
      source.seek(toFileOffset: dataOffset)
      try copy(
        item.entry.compressedSize,
        from: source,
        to: output
      )

      var central = Data()
      central.appendLE(UInt32(0x02014b50))
      central.appendLE(UInt16(0x0314))
      central.appendLE(UInt16(20))
      central.appendLE(UInt16(0x0800))
      central.appendLE(item.entry.compressionMethod)
      central.appendLE(UInt16(0))
      central.appendLE(UInt16(0))
      central.appendLE(item.entry.crc32)
      central.appendLE(compressedSize)
      central.appendLE(uncompressedSize)
      central.appendLE(UInt16(nameData.count))
      central.appendLE(UInt16(0))
      central.appendLE(UInt16(0))
      central.appendLE(UInt16(0))
      central.appendLE(UInt16(0))
      central.appendLE(item.entry.externalAttributes)
      central.appendLE(localOffset)
      central.append(nameData)
      centralRecords.append(central)
    }

    guard output.offsetInFile <= UInt64(UInt32.max) else {
      throw GameError.failed(.zipUnsupported, "暂不支持 ZIP64 格式")
    }
    let centralOffset = UInt32(output.offsetInFile)
    for record in centralRecords {
      output.write(record)
    }
    let centralSize = output.offsetInFile - UInt64(centralOffset)
    guard centralSize <= UInt64(UInt32.max) else {
      throw GameError.failed(.zipUnsupported, "暂不支持 ZIP64 格式")
    }
    var end = Data()
    end.appendLE(UInt32(0x06054b50))
    end.appendLE(UInt16(0))
    end.appendLE(UInt16(0))
    end.appendLE(UInt16(selected.count))
    end.appendLE(UInt16(selected.count))
    end.appendLE(UInt32(centralSize))
    end.appendLE(centralOffset)
    end.appendLE(UInt16(0))
    output.write(end)
  }

  private static func copy(
    _ byteCount: UInt64,
    from source: FileHandle,
    to output: FileHandle
  ) throws {
    var remaining = byteCount
    while remaining > 0 {
      let length = Int(
        min(UInt64(ZipImportLimits.copyBufferSize), remaining)
      )
      let data = source.readData(ofLength: length)
      guard data.count == length else {
        throw GameError.failed(.zipInvalid, "ZIP 文件内容不完整")
      }
      output.write(data)
      remaining -= UInt64(data.count)
    }
  }
}

private extension Data {
  mutating func appendLE(_ value: UInt16) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
  }

  mutating func appendLE(_ value: UInt32) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
  }
}
