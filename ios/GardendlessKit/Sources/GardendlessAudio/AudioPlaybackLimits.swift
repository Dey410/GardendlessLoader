import Foundation

public enum AudioPlaybackLimits {
  public static let voicePoolSize = 48
  public static let rateVoiceCount = 6
  public static let longChannelCount = 8
  public static let stalePlayInterval: TimeInterval = 0.15
  public static let excludedTokens: Set<String> = ["bgm", "music"]
  public static let supportedExtensions: Set<String> = ["mp3", "m4a"]
}
