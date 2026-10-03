import Foundation
import GardendlessCore

public final class GpNextSelectionStager {
  private let stagingRoot: URL
  private let fileManager: FileManager
  private let maximumEntries = 10_000
  private let maximumBytes: Int64 = 512 * 1024 * 1024

  public init(
    gpNextRoot: URL,
    fileManager: FileManager = .default
  ) {
    stagingRoot = gpNextRoot.appendingPathComponent(
      ".gardendless-selection",
      isDirectory: true
    )
    self.fileManager = fileManager
  }

  public func stage(_ source: URL, directory: Bool) throws -> URL {
    try clear()
    try fileManager.createDirectory(
      at: stagingRoot.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: stagingRoot,
      withIntermediateDirectories: false
    )
    var budget = SelectionBudget(entries: directory ? -1 : 0, bytes: 0)
    do {
      try validate(source, budget: &budget)
      if directory {
        let values = try source.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
          throw GameError.failed(.gpNextForbidden, "请选择一个 Mod 目录")
        }
        let destination = stagingRoot.appendingPathComponent(
          "selection",
          isDirectory: true
        )
        try fileManager.createDirectory(
          at: destination,
          withIntermediateDirectories: false
        )
        for child in try fileManager.contentsOfDirectory(
          at: source,
          includingPropertiesForKeys: nil
        ) {
          try fileManager.copyItem(
            at: child,
            to: destination.appendingPathComponent(child.lastPathComponent)
          )
        }
        return destination
      }
      guard source.pathExtension.lowercased() == "zip" else {
        throw GameError.failed(.gpNextForbidden, "请选择 ZIP 格式的 Mod 包")
      }
      let destination = stagingRoot.appendingPathComponent("selection.zip")
      try fileManager.copyItem(at: source, to: destination)
      return destination
    } catch {
      try? clear()
      throw error
    }
  }

  public func clear() throws {
    guard fileManager.fileExists(atPath: stagingRoot.path) else { return }
    let values = try stagingRoot.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard values.isSymbolicLink != true else {
      throw GameError.failed(.gpNextForbidden, "选择暂存目录不能是符号链接")
    }
    try fileManager.removeItem(at: stagingRoot)
  }

  private func validate(
    _ url: URL,
    budget: inout SelectionBudget
  ) throws {
    let values = try url.resourceValues(
      forKeys: [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
      ]
    )
    guard values.isSymbolicLink != true else {
      throw GameError.failed(.gpNextForbidden, "选择内容包含符号链接")
    }
    budget.entries += 1
    guard budget.entries <= maximumEntries else {
      throw GameError.failed(.gpNextForbidden, "选择的 Mod 包文件数量过多")
    }
    if values.isDirectory == true {
      for child in try fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: nil
      ) {
        try validate(child, budget: &budget)
      }
      return
    }
    guard values.isRegularFile == true else {
      throw GameError.failed(.gpNextForbidden, "选择内容包含不支持的文件类型")
    }
    budget.bytes += Int64(values.fileSize ?? 0)
    guard budget.bytes <= maximumBytes else {
      throw GameError.failed(.gpNextForbidden, "选择的 Mod 包超过 512 MiB")
    }
  }
}

private struct SelectionBudget {
  var entries = 0
  var bytes: Int64 = 0
}
