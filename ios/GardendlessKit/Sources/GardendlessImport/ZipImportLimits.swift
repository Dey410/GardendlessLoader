import Foundation

public enum ZipImportLimits {
  public static let copyBufferSize = 64 * 1024
  public static let progressReportIntervalNanoseconds: UInt64 = 100_000_000
  public static let eocdMinimumLength = 22
  public static let eocdMaximumCommentLength = 0xffff
  public static let localHeaderLength = 30
  public static let centralHeaderLength = 46
}
