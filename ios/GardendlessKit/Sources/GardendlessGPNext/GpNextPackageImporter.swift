import Foundation
import GardendlessCore

public final class GpNextPackageImporter {
  private let gpNextRoot: URL

  public init(gpNextRoot: URL) {
    self.gpNextRoot = gpNextRoot
  }

  public func importPackages(
    from urls: [URL],
    confirmReplacement: (String) -> Bool
  ) throws {
    for url in urls {
      _ = try importPackage(url, confirmReplacement: confirmReplacement)
    }
  }

  @discardableResult
  public func importPackage(
    _ source: URL,
    confirmReplacement: (String) -> Bool
  ) throws -> String {
    let accessed = source.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        source.stopAccessingSecurityScopedResource()
      }
    }
    let name = safeFileName(source.lastPathComponent)
    let ext = source.pathExtension.lowercased()
    let destinationDirectory: URL
    switch ext {
    case "zip":
      destinationDirectory = gpNextRoot.appendingPathComponent(
        "packs",
        isDirectory: true
      )
    case "json", "json5":
      destinationDirectory = gpNextRoot.appendingPathComponent(
        "patches",
        isDirectory: true
      )
    default:
      throw GameError.failed(
        .gpNextForbidden,
        "不支持的 GP-Next 文件：\(name)"
      )
    }
    try FileManager.default.createDirectory(
      at: destinationDirectory,
      withIntermediateDirectories: true
    )
    let incoming = destinationDirectory.appendingPathComponent(
      ".\(name).incoming-\(UUID().uuidString)"
    )
    try FileManager.default.copyItem(at: source, to: incoming)
    defer { try? FileManager.default.removeItem(at: incoming) }

    if ext == "json" {
      _ = try JSONSerialization.jsonObject(with: Data(contentsOf: incoming))
    } else if ext == "json5" {
      guard (try incoming.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0
      else {
        throw GameError.failed(.gpNextForbidden, "\(name) 是空文件")
      }
    } else {
      guard zipContainsRootPackJSON(incoming) else {
        throw GameError.failed(
          .gpNextForbidden,
          "\(name) 缺少根目录 pack.json"
        )
      }
    }

    let destination = destinationDirectory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: destination.path)
        && !confirmReplacement(name) {
      return name
    }
    let backup = destinationDirectory.appendingPathComponent(
      ".\(name).backup-\(UUID().uuidString)"
    )
    let existed = FileManager.default.fileExists(atPath: destination.path)
    if existed {
      try FileManager.default.moveItem(at: destination, to: backup)
    }
    do {
      try FileManager.default.moveItem(at: incoming, to: destination)
      if existed {
        try? FileManager.default.removeItem(at: backup)
      }
    } catch {
      if existed && !FileManager.default.fileExists(atPath: destination.path) {
        try? FileManager.default.moveItem(at: backup, to: destination)
      }
      throw error
    }
    return name
  }

  public func zipContainsRootPackJSON(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url),
          let size = try? handle.seekToEnd(),
          size >= 22 else {
      return false
    }
    defer { try? handle.close() }
    let tailSize = min(
      size,
      UInt64(GpNextConstants.maxImportScanTailBytes)
    )
    try? handle.seek(toOffset: size - tailSize)
    guard let tail = try? handle.read(upToCount: Int(tailSize)) else {
      return false
    }
    let bytes = [UInt8](tail)
    guard let end = stride(
      from: bytes.count - 22,
      through: 0,
      by: -1
    ).first(where: {
      bytes[$0] == 0x50
        && bytes[$0 + 1] == 0x4b
        && bytes[$0 + 2] == 0x05
        && bytes[$0 + 3] == 0x06
    }) else {
      return false
    }
    let centralOffset = UInt64(bytes[end + 16])
      | UInt64(bytes[end + 17]) << 8
      | UInt64(bytes[end + 18]) << 16
      | UInt64(bytes[end + 19]) << 24
    let count = Int(bytes[end + 10]) | Int(bytes[end + 11]) << 8
    try? handle.seek(toOffset: centralOffset)
    for _ in 0..<count {
      guard let header = try? handle.read(upToCount: 46),
            header.count == 46 else {
        return false
      }
      let value = [UInt8](header)
      guard value[0...3].elementsEqual([0x50, 0x4b, 0x01, 0x02]) else {
        return false
      }
      let nameLength = Int(value[28]) | Int(value[29]) << 8
      let extraLength = Int(value[30]) | Int(value[31]) << 8
      let commentLength = Int(value[32]) | Int(value[33]) << 8
      guard let nameData = try? handle.read(upToCount: nameLength) else {
        return false
      }
      if String(data: nameData, encoding: .utf8)?
        .replacingOccurrences(of: "\\", with: "/") == "pack.json" {
        return true
      }
      let current = (try? handle.offset()) ?? 0
      try? handle.seek(
        toOffset: current + UInt64(extraLength + commentLength)
      )
    }
    return false
  }

  private func safeFileName(_ value: String) -> String {
    let base = value
      .replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/")
      .last
      .map(String.init) ?? ""
    let invalid = CharacterSet(charactersIn: ":*?\"<>|").union(.controlCharacters)
    let cleaned = base.unicodeScalars.map {
      invalid.contains($0) ? "_" : String($0)
    }
    .joined()
    return cleaned.isEmpty || cleaned == "." || cleaned == ".."
      ? "gardendless-export.json"
      : cleaned
  }
}
