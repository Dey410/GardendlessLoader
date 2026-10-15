import Foundation

public struct CachedAudioEntry {
  public let data: Data
  public let totalLength: Int64
  public let mimeType: String
  public let etag: String

  public init(data: Data, totalLength: Int64, mimeType: String, etag: String) {
    self.data = data
    self.totalLength = totalLength
    self.mimeType = mimeType
    self.etag = etag
  }
}
