import Foundation

public enum ResourceConstants {
  public static let scheme = "gardendless-game"
  public static let host = "localhost"
  public static let origin = "\(scheme)://\(host)"
  public static let allowedMethods: Set<String> = ["GET", "HEAD"]
  public static let streamChunkSize = 128 * 1024
  public static let smallAudioByteLimit = 256 * 1024
}
