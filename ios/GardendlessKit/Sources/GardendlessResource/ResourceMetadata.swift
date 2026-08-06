import Foundation
import GardendlessCore

public struct ResourceMetadata {
  public let file: URL
  public let totalLength: Int64
  public let mimeType: String
  public let etag: String

  public init(file: URL, totalLength: Int64, mimeType: String, etag: String) {
    self.file = file
    self.totalLength = totalLength
    self.mimeType = mimeType
    self.etag = etag
  }

  public static func make(
    file: URL,
    relativePath: String,
    sandbox: PathSandbox
  ) throws -> ResourceMetadata {
    let properties = try sandbox.fileProperties(file)
    let mime: String
    if (relativePath as NSString).pathExtension.lowercased() == "mp3" {
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      let header = try handle.read(upToCount: 16) ?? Data()
      mime = ResourceMIME.detectAudioType(path: relativePath, header: header)
    } else {
      mime = ResourceMIME.type(for: relativePath)
    }
    return ResourceMetadata(
      file: file,
      totalLength: properties.length,
      mimeType: mime,
      etag: properties.etag
    )
  }
}
