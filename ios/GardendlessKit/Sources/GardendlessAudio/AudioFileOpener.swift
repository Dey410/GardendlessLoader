import AVFoundation
import Foundation

/// Opens audio files for native playback, handling the game package's
/// convention of M4A containers disguised under `.mp3` paths.
public final class AudioFileOpener {
  private let lock = NSLock()
  private var aliasFiles: [String: URL] = [:]

  public init() {}

  public func open(
    _ file: URL,
    relativePath: String,
    container: AudioContainer
  ) throws -> AVAudioFile {
    if container == .m4a, file.pathExtension.lowercased() != "m4a" {
      return try AVAudioFile(forReading: alias(file, relativePath: relativePath))
    }
    return try AVAudioFile(forReading: file)
  }

  public func cleanup() {
    lock.lock()
    let files = Array(aliasFiles.values)
    aliasFiles.removeAll()
    lock.unlock()
    for file in files {
      try? FileManager.default.removeItem(at: file)
    }
  }

  private func alias(_ file: URL, relativePath: String) throws -> URL {
    lock.lock()
    if let existing = aliasFiles[relativePath] {
      lock.unlock()
      return existing
    }
    lock.unlock()

    let properties = try file.resourceValues(forKeys: [.fileSizeKey])
    let size = Int64(properties.fileSize ?? 0)
    let identity = "\(file.path):\(relativePath):\(size)"
    let directory = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    )[0]
      .appendingPathComponent("gardendless-native-sfx", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let alias = directory.appendingPathComponent("\(urlHash(identity)).m4a")
    if !FileManager.default.fileExists(atPath: alias.path) {
      do {
        try FileManager.default.linkItem(at: file, to: alias)
      } catch {
        try FileManager.default.copyItem(at: file, to: alias)
      }
    }
    lock.lock()
    aliasFiles[relativePath] = alias
    lock.unlock()
    return alias
  }

  private func urlHash(_ value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }
}
