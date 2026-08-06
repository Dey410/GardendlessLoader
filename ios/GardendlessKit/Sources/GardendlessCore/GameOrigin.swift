import Foundation

/// Fixed synthetic origin served by the native iOS game host.
public enum GameOrigin {
  public static let scheme = "gardendless-game"
  public static let host = "localhost"
  public static let value = "\(scheme)://\(host)"
}
