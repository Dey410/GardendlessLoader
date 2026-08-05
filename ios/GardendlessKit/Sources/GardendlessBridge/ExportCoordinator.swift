import Foundation
import GardendlessCore

/// Receives chunked save data from the page and stages one export file until
/// the user picks a save location.
public final class ExportCoordinator {
  public struct ActiveExport {
    public let token: String
    public let file: URL
    public let expectedBytes: Int
    public let mimeType: String
    public let fileName: String
  }

  private let temporaryRoot: URL
  private let configuration: GameConfiguration
  private let lock = NSLock()
  private var active: ActiveExport?
  private var handle: FileHandle?
  private var writtenBytes = 0
  private var nextIndex = 0

  public init(
    temporaryRoot: URL,
    configuration: GameConfiguration = .default
  ) throws {
    self.temporaryRoot = temporaryRoot
    self.configuration = configuration
    try FileManager.default.createDirectory(
      at: temporaryRoot,
      withIntermediateDirectories: true
    )
  }

  public func begin(
    sessionId: String,
    suggestedFilename: String,
    mimeType: String,
    totalBytes: Int
  ) throws -> String {
    lock.lock()
    defer { lock.unlock() }
    guard active == nil, handle == nil else {
      throw GameError.failed(.exportInProgress, "Another export is active")
    }
    guard totalBytes >= 0, totalBytes <= configuration.maxExportBytes else {
      throw GameError.failed(.exportFailed, "Export size is invalid")
    }
    let name = safeFileName(suggestedFilename)
    let file = temporaryRoot.appendingPathComponent(
      ".chunk-\(UUID().uuidString)-\(name)"
    )
    guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
      throw GameError.failed(.exportFailed, "Unable to create export file")
    }
    let writingHandle = try FileHandle(forWritingTo: file)
    let export = ActiveExport(
      token: "\(sessionId)-\(UUID().uuidString)",
      file: file,
      expectedBytes: totalBytes,
      mimeType: mimeType.isEmpty ? "application/octet-stream" : mimeType,
      fileName: name
    )
    active = export
    handle = writingHandle
    writtenBytes = 0
    nextIndex = 0
    return export.token
  }

  public func append(token: String, index: Int, data: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    guard let export = active, let handle,
          export.token == token,
          index == nextIndex,
          data.count <= configuration.maxExportChunkBytes,
          writtenBytes + data.count <= export.expectedBytes else {
      throw GameError.failed(.exportFailed, "Export chunk sequence is invalid")
    }
    try handle.write(contentsOf: data)
    writtenBytes += data.count
    nextIndex += 1
  }

  public func commit(token: String) throws -> URL {
    lock.lock()
    defer { lock.unlock() }
    guard let export = active, let handle,
          export.token == token,
          writtenBytes == export.expectedBytes else {
      throw GameError.failed(.exportFailed, "Export did not receive every byte")
    }
    try handle.close()
    self.handle = nil
    var destination = temporaryRoot.appendingPathComponent(export.fileName)
    if FileManager.default.fileExists(atPath: destination.path) {
      destination = temporaryRoot.appendingPathComponent(
        "\(UUID().uuidString.prefix(8))-\(export.fileName)"
      )
    }
    try FileManager.default.moveItem(at: export.file, to: destination)
    active = nil
    writtenBytes = 0
    nextIndex = 0
    return destination
  }

  public func abort(token: String) {
    lock.lock()
    defer { lock.unlock() }
    guard let export = active, export.token == token else { return }
    try? handle?.close()
    handle = nil
    try? FileManager.default.removeItem(at: export.file)
    active = nil
    writtenBytes = 0
    nextIndex = 0
  }

  public func cancelActive() {
    lock.lock()
    defer { lock.unlock() }
    guard let export = active else { return }
    try? handle?.close()
    handle = nil
    try? FileManager.default.removeItem(at: export.file)
    active = nil
    writtenBytes = 0
    nextIndex = 0
  }

  public func finishAfterPicker(for file: URL) {
    lock.lock()
    defer { lock.unlock() }
    try? FileManager.default.removeItem(at: file)
  }

  private func safeFileName(_ value: String) -> String {
    let base = (value.replacingOccurrences(of: "\\", with: "/") as NSString)
      .lastPathComponent
    let cleaned = base
      .replacingOccurrences(
        of: "[\\x00-\\x1f:*?\"<>|]",
        with: "_",
        options: .regularExpression
      )
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty || cleaned == "." || cleaned == ".."
      ? "gardendless-export.json"
      : cleaned
  }
}
