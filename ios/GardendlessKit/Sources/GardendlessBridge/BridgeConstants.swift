import Foundation

public enum BridgeConstants {
  public static let handlerName = "gardendlessNative"
  public static let maxMessageBytes = 1024 * 1024
  public static func pendingRequestLimit(command: String, args: [String: Any]) -> Int {
    let control = command == "file:finish"
      && ["close", "cancel"].contains(args["action"] as? String ?? "")
    return control ? 72 : 64
  }

}
