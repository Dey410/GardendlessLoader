import Foundation
import GardendlessCore

public enum AudioContainer: Equatable {
  case mp3
  case m4a
  case unsupported
}

public enum AudioContainerDetector {
  public static func detect(_ file: URL) throws -> AudioContainer {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 16) ?? Data()
    let brands = ["ftypM4A", "ftypisom", "ftypmp42"]
    if brands.contains(where: { data.range(of: Data($0.utf8)) != nil }) {
      return .m4a
    }
    let bytes = [UInt8](data)
    if data.starts(with: Data("ID3".utf8))
        || (bytes.count >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
      return .mp3
    }
    return .unsupported
  }
}
