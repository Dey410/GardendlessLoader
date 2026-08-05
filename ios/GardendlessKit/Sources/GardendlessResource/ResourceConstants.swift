import Foundation
import GardendlessCore

public enum ResourceConstants {
  public static let scheme = GameOrigin.scheme
  public static let host = GameOrigin.host
  public static let origin = GameOrigin.value
  public static let allowedMethods: Set<String> = ["GET", "HEAD"]
  public static let streamChunkSize = 128 * 1024
  public static let smallAudioByteLimit = 256 * 1024
}
