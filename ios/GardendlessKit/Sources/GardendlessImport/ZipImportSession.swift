import Foundation
import GardendlessCore
import zlib

public struct ImportProgress: Equatable {
  public let phase: String
  public let processedBytes: Int64
  public let totalBytes: Int64
  public let processedFiles: Int
  public let totalFiles: Int
  public let message: String

  public init(
    phase: String,
    processedBytes: Int64 = 0,
    totalBytes: Int64 = 0,
    processedFiles: Int = 0,
    totalFiles: Int = 0,
    message: String
  ) {
    self.phase = phase
    self.processedBytes = processedBytes
    self.totalBytes = totalBytes
    self.processedFiles = processedFiles
    self.totalFiles = totalFiles
    self.message = message
  }
}

public final class ZipImportSession {
  private let zipURL: URL
  private let targetDirectory: URL
  private let progressIntervalNanoseconds: UInt64
  private var lastProgressReportAt: UInt64 = 0

  public init(
    zipURL: URL,
    targetDirectory: URL,
    progressIntervalNanoseconds: UInt64 =
      ZipImportLimits.progressReportIntervalNanoseconds
  ) {
    self.zipURL = zipURL
    self.targetDirectory = targetDirectory
    self.progressIntervalNanoseconds = progressIntervalNanoseconds
  }

  public func run(
    onProgress: @escaping (ImportProgress) -> Void
  ) throws -> URL {
    let attributes = try FileManager.default.attributesOfItem(atPath: zipURL.path)
    let sourceBytes = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    report(
      onProgress,
      phase: "receiving",
      totalBytes: Int64(sourceBytes),
      message: "正在读取 ZIP",
      force: true
    )
    let entries = try ZipArchiveReader.read(from: zipURL)
    report(
      onProgress,
      phase: "receiving",
      processedBytes: Int64(sourceBytes),
      totalBytes: Int64(sourceBytes),
      message: "已读取 ZIP",
      force: true
    )
    guard let docsPrefix = try DocsDirectoryFinder.find(in: entries) else {
      throw GameError.failed(
        .zipInvalid,
        "选择的 ZIP 中没有找到有效的 docs 资源目录"
      )
    }

    try resetDirectory(targetDirectory)

    var selected: [(entry: ZipEntry, archivePath: String)] = []
    for entry in entries {
      if entry.isSymbolicLink {
        throw GameError.failed(.zipSymbolicLink, "选择的 ZIP 包含不支持的符号链接")
      }
      let archivePath = try DocsDirectoryFinder.safeArchivePath(entry.name)
      if DocsDirectoryFinder.isWithinArchivePrefix(
        archivePath,
        prefix: docsPrefix
      ) {
        selected.append((entry, archivePath))
      }
    }
    let fileEntries = selected.filter { !$0.entry.isDirectory }
    let totalFiles = fileEntries.count
    let totalBytes = fileEntries.reduce(Int64(0)) {
      $0 + Int64($1.entry.uncompressedSize)
    }
    var processedFiles = 0
    var processedBytes: Int64 = 0
    report(
      onProgress,
      phase: "extracting",
      totalBytes: totalBytes,
      totalFiles: totalFiles,
      message: "正在解压资源",
      force: true
    )

    let zipFile = try FileHandle(forReadingFrom: zipURL)
    defer { zipFile.closeFile() }

    for selectedEntry in selected {
      let entry = selectedEntry.entry
      let archivePath = selectedEntry.archivePath
      let relativePath = docsPrefix.isEmpty
        ? archivePath
        : String(archivePath.dropFirst(docsPrefix.count + 1))
      if relativePath.isEmpty {
        continue
      }

      let outputURL = try targetURL(
        for: relativePath,
        in: targetDirectory,
        isDirectory: entry.isDirectory
      )
      if entry.isDirectory {
        try FileManager.default.createDirectory(
          at: outputURL,
          withIntermediateDirectories: true
        )
        continue
      }

      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      guard let output = OutputStream(url: outputURL, append: false) else {
        throw GameError.failed(.zipInvalid, "无法写入导入文件：\(relativePath)")
      }
      output.open()
      defer { output.close() }

      let dataOffset = try ZipArchiveReader.localFileDataOffset(
        for: entry,
        in: zipFile
      )
      zipFile.seek(toFileOffset: dataOffset)
      let onBytesWritten: (Int) -> Void = { [weak self] count in
        processedBytes += Int64(count)
        self?.report(
          onProgress,
          phase: "extracting",
          processedBytes: processedBytes,
          totalBytes: totalBytes,
          processedFiles: processedFiles,
          totalFiles: totalFiles,
          message: "正在解压资源"
        )
      }
      switch entry.compressionMethod {
      case 0:
        try copyStoredEntry(
          from: zipFile,
          compressedSize: entry.compressedSize,
          to: output,
          onBytesWritten: onBytesWritten
        )
      case 8:
        try inflateDeflatedEntry(
          from: zipFile,
          compressedSize: entry.compressedSize,
          to: output,
          onBytesWritten: onBytesWritten
        )
      default:
        throw GameError.failed(.zipUnsupported, "选择的 ZIP 包含不支持的压缩方式")
      }
      processedFiles += 1
      report(
        onProgress,
        phase: "extracting",
        processedBytes: processedBytes,
        totalBytes: totalBytes,
        processedFiles: processedFiles,
        totalFiles: totalFiles,
        message: "正在解压资源",
        force: true
      )
    }
    return targetDirectory
  }

  private func copyStoredEntry(
    from zipFile: FileHandle,
    compressedSize: UInt64,
    to output: OutputStream,
    onBytesWritten: (Int) -> Void
  ) throws {
    var remaining = compressedSize
    while remaining > 0 {
      let readLength = Int(
        min(UInt64(ZipImportLimits.copyBufferSize), remaining)
      )
      let data = zipFile.readData(ofLength: readLength)
      guard !data.isEmpty else {
        throw GameError.failed(.zipInvalid, "ZIP 文件内容不完整")
      }
      try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
          return
        }
        try write(baseAddress, count: data.count, to: output)
      }
      onBytesWritten(data.count)
      remaining -= UInt64(data.count)
    }
  }

  private func inflateDeflatedEntry(
    from zipFile: FileHandle,
    compressedSize: UInt64,
    to output: OutputStream,
    onBytesWritten: (Int) -> Void
  ) throws {
    var stream = z_stream()
    let initStatus = inflateInit2_(
      &stream,
      -MAX_WBITS,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initStatus == Z_OK else {
      throw GameError.failed(.zipInvalid, "无法初始化 ZIP 解压器")
    }
    defer { inflateEnd(&stream) }

    var remaining = compressedSize
    var didEnd = false
    var outputBuffer = [UInt8](
      repeating: 0,
      count: ZipImportLimits.copyBufferSize
    )

    func pump() throws -> (status: Int32, produced: Int) {
      let status = outputBuffer.withUnsafeMutableBufferPointer { outputPointer in
        stream.next_out = outputPointer.baseAddress
        stream.avail_out = uInt(outputPointer.count)
        return inflate(&stream, Z_NO_FLUSH)
      }
      let produced = outputBuffer.count - Int(stream.avail_out)
      if produced > 0 {
        try outputBuffer.withUnsafeBytes { outputRawBuffer in
          guard let outputBaseAddress = outputRawBuffer
            .bindMemory(to: UInt8.self)
            .baseAddress else {
            return
          }
          try write(outputBaseAddress, count: produced, to: output)
        }
        onBytesWritten(produced)
      }
      return (status, produced)
    }

    while remaining > 0 && !didEnd {
      let readLength = Int(
        min(UInt64(ZipImportLimits.copyBufferSize), remaining)
      )
      let inputData = zipFile.readData(ofLength: readLength)
      guard !inputData.isEmpty else {
        throw GameError.failed(.zipInvalid, "ZIP 文件内容不完整")
      }
      remaining -= UInt64(inputData.count)

      try inputData.withUnsafeBytes { rawBuffer in
        guard let inputBaseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
          return
        }
        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBaseAddress)
        stream.avail_in = uInt(inputData.count)

        while stream.avail_in > 0 {
          let (status, _) = try pump()
          if status == Z_STREAM_END {
            didEnd = true
            break
          }
          if status != Z_OK {
            throw GameError.failed(.zipInvalid, "ZIP 解压失败")
          }
        }
      }
    }
    while !didEnd {
      stream.next_in = nil
      stream.avail_in = 0
      let (status, produced) = try pump()
      if status == Z_STREAM_END {
        didEnd = true
        break
      }
      if produced == 0 || status != Z_OK {
        throw GameError.failed(.zipInvalid, "ZIP 文件内容不完整")
      }
    }
  }

  private func write(
    _ pointer: UnsafePointer<UInt8>,
    count: Int,
    to output: OutputStream
  ) throws {
    var totalWritten = 0
    while totalWritten < count {
      let written = output.write(
        pointer.advanced(by: totalWritten),
        maxLength: count - totalWritten
      )
      if written <= 0 {
        throw GameError.failed(
          .zipInvalid,
          output.streamError?.localizedDescription ?? "无法写入导入文件"
        )
      }
      totalWritten += written
    }
  }

  private func resetDirectory(_ directory: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: directory.path) {
      let children = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )
      for child in children {
        try fileManager.removeItem(at: child)
      }
    }
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
  }

  private func targetURL(
    for relativePath: String,
    in root: URL,
    isDirectory: Bool
  ) throws -> URL {
    var target = root
    let components = relativePath.split(separator: "/").map(String.init)
    for component in components {
      target.appendPathComponent(component, isDirectory: false)
    }
    let rootPath = root.standardizedFileURL.path
    let targetPath = target.standardizedFileURL.path
    guard targetPath == rootPath || targetPath.hasPrefix("\(rootPath)/") else {
      throw GameError.failed(.zipPathUnsafe, "选择的 ZIP 包含 docs 外部路径")
    }
    return isDirectory
      ? URL(fileURLWithPath: target.path, isDirectory: true)
      : target
  }

  private func report(
    _ onProgress: @escaping (ImportProgress) -> Void,
    phase: String,
    processedBytes: Int64 = 0,
    totalBytes: Int64 = 0,
    processedFiles: Int = 0,
    totalFiles: Int = 0,
    message: String,
    force: Bool = false
  ) {
    let now = DispatchTime.now().uptimeNanoseconds
    if !force && now - lastProgressReportAt < progressIntervalNanoseconds {
      return
    }
    lastProgressReportAt = now
    onProgress(
      ImportProgress(
        phase: phase,
        processedBytes: processedBytes,
        totalBytes: totalBytes,
        processedFiles: processedFiles,
        totalFiles: totalFiles,
        message: message
      )
    )
  }
}
