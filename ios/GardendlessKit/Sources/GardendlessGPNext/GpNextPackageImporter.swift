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

    var prepared = incoming
    var normalized: URL?
    if ext == "json" {
      _ = try JSONSerialization.jsonObject(with: Data(contentsOf: incoming))
    } else if ext == "json5" {
      guard (try incoming.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0
      else {
        throw GameError.failed(.gpNextForbidden, "\(name) 是空文件")
      }
    } else {
      prepared = try GpNextPackArchiveNormalizer.prepare(
        incoming,
        in: destinationDirectory,
        displayName: name
      )
      if prepared != incoming {
        normalized = prepared
      }
    }
    defer {
      if let normalized {
        try? FileManager.default.removeItem(at: normalized)
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
      try FileManager.default.moveItem(at: prepared, to: destination)
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
