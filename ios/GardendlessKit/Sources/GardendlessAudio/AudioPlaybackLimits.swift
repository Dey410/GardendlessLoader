import Foundation

public enum AudioPlaybackLimits {
  public static let nodeCount = 16
  public static let stalePlayInterval: TimeInterval = 0.15
  public static let excludedTokens: Set<String> = ["bgm", "music"]
  public static let supportedExtensions: Set<String> = ["mp3", "m4a"]
}
