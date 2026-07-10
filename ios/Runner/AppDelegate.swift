import Flutter
import UniformTypeIdentifiers
import UIKit
import zlib

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let resourceZipImporterChannelName =
    "io.github.dey410.gardendlessloader/resource_zip_importer"
  private let gameFileExporterChannelName =
    "io.github.dey410.gardendlessloader/game_file_exporter"
  private var pendingImportResult: FlutterResult?
  private var pendingImportTargetDirectory: String?
  private var zipImportInProgress = false
  private var pendingExportResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerResourceZipImporter()
    registerGameFileExporter()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerResourceZipImporter() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: resourceZipImporterChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickAndExtractDocsZip" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.pickAndExtractDocsZip(call: call, result: result)
    }
  }

  private func registerGameFileExporter() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: gameFileExporterChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "exportFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.exportFile(call: call, result: result)
    }
  }

  private func pickAndExtractDocsZip(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let targetDirectory = args["targetDirectory"] as? String,
          !targetDirectory.isEmpty else {
      result(FlutterError(
        code: "invalid_target_directory",
        message: "缺少导入目标目录",
        details: nil
      ))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self else {
        result(FlutterError(
          code: "missing_app_delegate",
          message: "无法获取 iOS 应用代理",
          details: nil
        ))
        return
      }

      guard let rootController = self.topViewController() else {
        result(FlutterError(
          code: "missing_view_controller",
          message: "Unable to present ZIP picker",
          details: nil
        ))
        return
      }

      if self.zipImportInProgress || self.pendingImportResult != nil {
        result(FlutterError(
          code: "zip_import_busy",
          message: "已有 ZIP 导入选择正在进行",
          details: nil
        ))
        return
      }

      let documentPicker = self.makeZipDocumentPicker()
      documentPicker.delegate = self
      documentPicker.allowsMultipleSelection = false
      documentPicker.modalPresentationStyle = .formSheet

      self.zipImportInProgress = true
      self.pendingImportResult = result
      self.pendingImportTargetDirectory = targetDirectory
      rootController.present(documentPicker, animated: true)
    }
  }

  private func makeZipDocumentPicker() -> UIDocumentPickerViewController {
    if #available(iOS 14.0, *) {
      return UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.zip],
        asCopy: true
      )
    }
    return UIDocumentPickerViewController(
      documentTypes: [
        "public.zip-archive",
        "com.pkware.zip-archive",
        "public.archive",
      ],
      in: .import
    )
  }

  private func finishPickedZipImport(
    zipUrl: URL,
    targetDirectory: String,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "missing_app_delegate",
            message: "无法获取 iOS 应用代理",
            details: nil
          ))
        }
        return
      }

      let didAccess = zipUrl.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          zipUrl.stopAccessingSecurityScopedResource()
        }
      }

      do {
        try self.extractDocsZip(
          from: zipUrl,
          to: URL(fileURLWithPath: targetDirectory, isDirectory: true)
        )
        DispatchQueue.main.async {
          self.zipImportInProgress = false
          result(targetDirectory)
        }
      } catch {
        DispatchQueue.main.async {
          self.zipImportInProgress = false
          result(FlutterError(
            code: "zip_import_failed",
            message: "无法导入选择的 ZIP：\(self.importErrorMessage(error))",
            details: nil
          ))
        }
      }
    }
  }

  private func exportFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterError(
        code: "invalid_arguments",
        message: "Missing export file path",
        details: nil
      ))
      return
    }

    let fileUrl = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileUrl.path) else {
      result(FlutterError(
        code: "file_not_found",
        message: "Export file does not exist",
        details: path
      ))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let rootController = self?.topViewController() else {
        result(FlutterError(
          code: "missing_view_controller",
          message: "Unable to present export sheet",
          details: nil
        ))
        return
      }

      if self?.pendingExportResult != nil {
        result(FlutterError(
          code: "export_in_progress",
          message: "Another export is already in progress",
          details: nil
        ))
        return
      }

      let documentPicker = self?.makeDocumentPicker(for: fileUrl)
      guard let documentPicker else {
        result(FlutterError(
          code: "missing_document_picker",
          message: "Unable to create export picker",
          details: nil
        ))
        return
      }
      documentPicker.delegate = self
      documentPicker.modalPresentationStyle = .formSheet
      if let popover = documentPicker.popoverPresentationController {
        let fallbackRect = CGRect(x: 1, y: 1, width: 1, height: 1)
        popover.sourceView = rootController.view
        popover.sourceRect = self?.sourceRect(from: args) ?? fallbackRect
        popover.permittedArrowDirections = []
      }

      self?.pendingExportResult = result
      rootController.present(documentPicker, animated: true)
    }
  }

  private func makeDocumentPicker(for fileUrl: URL) -> UIDocumentPickerViewController {
    if #available(iOS 14.0, *) {
      return UIDocumentPickerViewController(
        forExporting: [fileUrl],
        asCopy: true
      )
    }
    return UIDocumentPickerViewController(
      url: fileUrl,
      in: .exportToService
    )
  }

  private func sourceRect(from args: [String: Any]) -> CGRect {
    let x = args["originX"] as? Double ?? 1
    let y = args["originY"] as? Double ?? 1
    let width = max(args["originWidth"] as? Double ?? 1, 1)
    let height = max(args["originHeight"] as? Double ?? 1, 1)
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private func extractDocsZip(from zipUrl: URL, to targetDirectory: URL) throws {
    let entries = try readZipCentralDirectory(from: zipUrl)
    let docsPrefix = try findDocsPrefix(in: entries)
    guard let docsPrefix else {
      throw ZipImportError("选择的 ZIP 中没有找到有效的 docs 资源目录")
    }

    try resetDirectory(targetDirectory)

    let zipFile = try FileHandle(forReadingFrom: zipUrl)
    defer {
      zipFile.closeFile()
    }

    for entry in entries {
      if entry.isSymbolicLink {
        throw ZipImportError("选择的 ZIP 包含不支持的符号链接")
      }

      let archivePath = try safeArchivePath(entry.name)
      if !isWithinArchivePrefix(archivePath, prefix: docsPrefix) {
        continue
      }

      let relativePath = docsPrefix.isEmpty
        ? archivePath
        : String(archivePath.dropFirst(docsPrefix.count + 1))
      if relativePath.isEmpty {
        continue
      }

      let outputUrl = try targetUrl(
        for: relativePath,
        in: targetDirectory,
        isDirectory: entry.isDirectory
      )

      if entry.isDirectory {
        try FileManager.default.createDirectory(
          at: outputUrl,
          withIntermediateDirectories: true
        )
        continue
      }

      try FileManager.default.createDirectory(
        at: outputUrl.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )

      guard let output = OutputStream(url: outputUrl, append: false) else {
        throw ZipImportError("无法写入导入文件：\(relativePath)")
      }
      output.open()
      defer {
        output.close()
      }

      let dataOffset = try localFileDataOffset(for: entry, in: zipFile)
      zipFile.seek(toFileOffset: dataOffset)
      switch entry.compressionMethod {
      case 0:
        try copyStoredEntry(
          from: zipFile,
          compressedSize: entry.compressedSize,
          to: output
        )
      case 8:
        try inflateDeflatedEntry(
          from: zipFile,
          compressedSize: entry.compressedSize,
          to: output
        )
      default:
        throw ZipImportError("选择的 ZIP 包含不支持的压缩方式")
      }
    }
  }

  private func readZipCentralDirectory(from zipUrl: URL) throws -> [ZipEntry] {
    let attributes = try FileManager.default.attributesOfItem(atPath: zipUrl.path)
    guard let fileSize = (attributes[.size] as? NSNumber)?.uint64Value,
          fileSize >= UInt64(zipEndOfCentralDirectoryMinLength) else {
      throw ZipImportError("无效的 ZIP 文件")
    }

    let zipFile = try FileHandle(forReadingFrom: zipUrl)
    defer {
      zipFile.closeFile()
    }

    let tailLength = min(
      fileSize,
      UInt64(zipEndOfCentralDirectoryMinLength + zipMaxCommentLength)
    )
    zipFile.seek(toFileOffset: fileSize - tailLength)
    let tail = zipFile.readData(ofLength: Int(tailLength))
    let eocdOffset = try endOfCentralDirectoryOffset(in: tail)

    let totalEntries = uint16(tail, eocdOffset + 10)
    let centralDirectorySize = uint32(tail, eocdOffset + 12)
    let centralDirectoryOffset = uint32(tail, eocdOffset + 16)
    if totalEntries == UInt16.max ||
        centralDirectorySize == UInt32.max ||
        centralDirectoryOffset == UInt32.max {
      throw ZipImportError("暂不支持 ZIP64 格式")
    }

    zipFile.seek(toFileOffset: UInt64(centralDirectoryOffset))
    var entries: [ZipEntry] = []
    entries.reserveCapacity(Int(totalEntries))
    for _ in 0..<totalEntries {
      let header = try readData(from: zipFile, length: zipCentralHeaderLength)
      guard uint32(header, 0) == zipCentralHeaderSignature else {
        throw ZipImportError("无效的 ZIP 中央目录")
      }

      let flags = uint16(header, 8)
      if flags & 0x0001 != 0 {
        throw ZipImportError("选择的 ZIP 已加密，无法导入")
      }

      let compressionMethod = uint16(header, 10)
      let compressedSize = uint32(header, 20)
      let uncompressedSize = uint32(header, 24)
      let fileNameLength = Int(uint16(header, 28))
      let extraLength = Int(uint16(header, 30))
      let commentLength = Int(uint16(header, 32))
      let externalAttributes = uint32(header, 38)
      let localHeaderOffset = uint32(header, 42)
      if compressedSize == UInt32.max ||
          uncompressedSize == UInt32.max ||
          localHeaderOffset == UInt32.max {
        throw ZipImportError("暂不支持 ZIP64 格式")
      }

      let nameData = try readData(from: zipFile, length: fileNameLength)
      let nameEncoding: String.Encoding =
        flags & 0x0800 == 0 ? .isoLatin1 : .utf8
      guard let name = String(data: nameData, encoding: nameEncoding) ??
              String(data: nameData, encoding: .utf8) else {
        throw ZipImportError("选择的 ZIP 包含无法识别的文件名")
      }

      if extraLength + commentLength > 0 {
        zipFile.seek(
          toFileOffset: zipFile.offsetInFile + UInt64(extraLength + commentLength)
        )
      }

      entries.append(ZipEntry(
        name: name,
        compressionMethod: compressionMethod,
        compressedSize: UInt64(compressedSize),
        uncompressedSize: UInt64(uncompressedSize),
        localHeaderOffset: UInt64(localHeaderOffset),
        externalAttributes: externalAttributes
      ))
    }

    return entries
  }

  private func endOfCentralDirectoryOffset(in data: Data) throws -> Int {
    if data.count < zipEndOfCentralDirectoryMinLength {
      throw ZipImportError("无效的 ZIP 文件")
    }

    for offset in stride(
      from: data.count - zipEndOfCentralDirectoryMinLength,
      through: 0,
      by: -1
    ) {
      guard uint32(data, offset) == zipEndOfCentralDirectorySignature else {
        continue
      }
      let commentLength = Int(uint16(data, offset + 20))
      if offset + zipEndOfCentralDirectoryMinLength + commentLength == data.count {
        return offset
      }
    }

    throw ZipImportError("无效的 ZIP 文件")
  }

  private func findDocsPrefix(in entries: [ZipEntry]) throws -> String? {
    var filePaths = Set<String>()
    var directoryPaths = Set<String>()

    for entry in entries {
      if entry.isSymbolicLink {
        throw ZipImportError("选择的 ZIP 包含不支持的符号链接")
      }

      let archivePath = try safeArchivePath(entry.name)
      if entry.isDirectory {
        directoryPaths.insert(archivePath)
      } else {
        filePaths.insert(archivePath)
      }
    }

    var candidates = Set<String>()
    for path in filePaths where basename(path).lowercased() == "index.html" {
      candidates.insert(dirname(path))
    }

    return candidates.filter { candidate in
      func candidatePath(_ relativePath: String) -> String {
        candidate.isEmpty ? relativePath : "\(candidate)/\(relativePath)"
      }

      func hasFile(_ relativePath: String) -> Bool {
        filePaths.contains(candidatePath(relativePath))
      }

      func hasDirectory(_ relativePath: String) -> Bool {
        let path = candidatePath(relativePath)
        return directoryPaths.contains(path) ||
          filePaths.contains { filePath in filePath.hasPrefix("\(path)/") }
      }

      return hasFile("index.html") &&
        hasFile("src/settings.json") &&
        hasFile("src/import-map.json") &&
        hasDirectory("assets") &&
        hasDirectory("cocos-js") &&
        hasDirectory("src")
    }.sorted { first, second in
      let firstIsDocs = basename(first) == "docs"
      let secondIsDocs = basename(second) == "docs"
      if firstIsDocs != secondIsDocs {
        return firstIsDocs
      }
      return first.count < second.count
    }.first
  }

  private func localFileDataOffset(for entry: ZipEntry, in zipFile: FileHandle) throws -> UInt64 {
    zipFile.seek(toFileOffset: entry.localHeaderOffset)
    let header = try readData(from: zipFile, length: zipLocalHeaderLength)
    guard uint32(header, 0) == zipLocalHeaderSignature else {
      throw ZipImportError("无效的 ZIP 本地文件头")
    }
    let fileNameLength = UInt64(uint16(header, 26))
    let extraLength = UInt64(uint16(header, 28))
    return entry.localHeaderOffset + UInt64(zipLocalHeaderLength) +
      fileNameLength + extraLength
  }

  private func copyStoredEntry(
    from zipFile: FileHandle,
    compressedSize: UInt64,
    to output: OutputStream
  ) throws {
    var remaining = compressedSize
    while remaining > 0 {
      let readLength = Int(min(UInt64(zipCopyBufferSize), remaining))
      let data = zipFile.readData(ofLength: readLength)
      guard !data.isEmpty else {
        throw ZipImportError("ZIP 文件内容不完整")
      }
      try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
          return
        }
        try write(baseAddress, count: data.count, to: output)
      }
      remaining -= UInt64(data.count)
    }
  }

  private func inflateDeflatedEntry(
    from zipFile: FileHandle,
    compressedSize: UInt64,
    to output: OutputStream
  ) throws {
    var stream = z_stream()
    let initStatus = inflateInit2_(
      &stream,
      -MAX_WBITS,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initStatus == Z_OK else {
      throw ZipImportError("无法初始化 ZIP 解压器")
    }
    defer {
      inflateEnd(&stream)
    }

    var remaining = compressedSize
    var didEnd = false
    var outputBuffer = [UInt8](repeating: 0, count: zipCopyBufferSize)

    while remaining > 0 && !didEnd {
      let readLength = Int(min(UInt64(zipCopyBufferSize), remaining))
      let inputData = zipFile.readData(ofLength: readLength)
      guard !inputData.isEmpty else {
        throw ZipImportError("ZIP 文件内容不完整")
      }
      remaining -= UInt64(inputData.count)

      try inputData.withUnsafeBytes { rawBuffer in
        guard let inputBaseAddress =
                rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
          return
        }
        stream.next_in = UnsafeMutablePointer<Bytef>(
          mutating: inputBaseAddress
        )
        stream.avail_in = uInt(inputData.count)

        while stream.avail_in > 0 {
          let status = outputBuffer.withUnsafeMutableBufferPointer { outputPointer in
            stream.next_out = outputPointer.baseAddress
            stream.avail_out = uInt(outputPointer.count)
            return inflate(&stream, Z_NO_FLUSH)
          }

          let produced = outputBuffer.count - Int(stream.avail_out)
          if produced > 0 {
            try outputBuffer.withUnsafeBytes { outputRawBuffer in
              guard let outputBaseAddress =
                      outputRawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
              }
              try write(outputBaseAddress, count: produced, to: output)
            }
          }

          if status == Z_STREAM_END {
            didEnd = true
            break
          }
          if status != Z_OK {
            throw ZipImportError("ZIP 解压失败")
          }
        }
      }
    }

    if !didEnd {
      throw ZipImportError("ZIP 文件内容不完整")
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
        throw ZipImportError(
          output.streamError?.localizedDescription ?? "无法写入导入文件"
        )
      }
      totalWritten += written
    }
  }

  private func readData(from file: FileHandle, length: Int) throws -> Data {
    let data = file.readData(ofLength: length)
    guard data.count == length else {
      throw ZipImportError("ZIP 文件内容不完整")
    }
    return data
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

  private func targetUrl(
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
      throw ZipImportError("选择的 ZIP 包含 docs 外部路径")
    }
    return isDirectory
      ? URL(fileURLWithPath: target.path, isDirectory: true)
      : target
  }

  private func safeArchivePath(_ path: String) throws -> String {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    if normalized.hasPrefix("/") {
      throw ZipImportError("选择的 ZIP 包含不安全路径")
    }

    let parts = normalized
      .split(separator: "/", omittingEmptySubsequences: false)
      .compactMap { part -> String? in
        let value = String(part)
        return value.isEmpty || value == "." ? nil : value
      }
    if parts.isEmpty || parts.contains("..") {
      throw ZipImportError("选择的 ZIP 包含不安全路径")
    }
    return parts.joined(separator: "/")
  }

  private func isWithinArchivePrefix(_ path: String, prefix: String) -> Bool {
    prefix.isEmpty || path == prefix || path.hasPrefix("\(prefix)/")
  }

  private func basename(_ path: String) -> String {
    path.split(separator: "/").last.map(String.init) ?? path
  }

  private func dirname(_ path: String) -> String {
    guard let index = path.lastIndex(of: "/") else {
      return ""
    }
    return String(path[..<index])
  }

  private func importErrorMessage(_ error: Error) -> String {
    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription {
      return description
    }
    return error.localizedDescription
  }

  private func uint16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) |
      UInt16(data[offset + 1]) << 8
  }

  private func uint32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset]) |
      UInt32(data[offset + 1]) << 8 |
      UInt32(data[offset + 2]) << 16 |
      UInt32(data[offset + 3]) << 24
  }

  private func topViewController() -> UIViewController? {
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let pendingImportResult {
      pendingImportResult(nil)
      self.pendingImportResult = nil
      pendingImportTargetDirectory = nil
      zipImportInProgress = false
      return
    }

    pendingExportResult?(FlutterError(
      code: "export_cancelled",
      message: "Export was cancelled",
      details: nil
    ))
    pendingExportResult = nil
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    if let pendingImportResult {
      let targetDirectory = pendingImportTargetDirectory
      self.pendingImportResult = nil
      pendingImportTargetDirectory = nil

      guard let zipUrl = urls.first, let targetDirectory else {
        zipImportInProgress = false
        pendingImportResult(nil)
        return
      }

      finishPickedZipImport(
        zipUrl: zipUrl,
        targetDirectory: targetDirectory,
        result: pendingImportResult
      )
      return
    }

    pendingExportResult?(nil)
    pendingExportResult = nil
  }
}

private struct ZipEntry {
  let name: String
  let compressionMethod: UInt16
  let compressedSize: UInt64
  let uncompressedSize: UInt64
  let localHeaderOffset: UInt64
  let externalAttributes: UInt32

  var isDirectory: Bool {
    name.hasSuffix("/")
  }

  var isSymbolicLink: Bool {
    let unixMode = (externalAttributes >> 16) & 0o170000
    return unixMode == 0o120000
  }
}

private struct ZipImportError: LocalizedError {
  init(_ message: String) {
    self.message = message
  }

  private let message: String

  var errorDescription: String? {
    message
  }
}

private let zipLocalHeaderSignature: UInt32 = 0x04034b50
private let zipCentralHeaderSignature: UInt32 = 0x02014b50
private let zipEndOfCentralDirectorySignature: UInt32 = 0x06054b50
private let zipLocalHeaderLength = 30
private let zipCentralHeaderLength = 46
private let zipEndOfCentralDirectoryMinLength = 22
private let zipMaxCommentLength = 0xffff
private let zipCopyBufferSize = 64 * 1024
