import Foundation
import GardendlessCore

public struct BridgeRequest {
  public let id: String
  public let command: String
  public let namespace: String
  public let args: [String: Any]
  public let options: [String: Any]

  public static func decode(_ raw: String) throws -> BridgeRequest {
    guard raw.utf8.count <= BridgeConstants.maxMessageBytes,
          let data = raw.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data),
          let object = json as? [String: Any],
          let id = object["id"] as? String, !id.isEmpty,
          let command = object["command"] as? String, !command.isEmpty else {
      throw GameError.failed(.invalidSession, "Invalid bridge request")
    }
    return BridgeRequest(
      id: id,
      command: command,
      namespace: object["namespace"] as? String ?? "host",
      args: object["args"] as? [String: Any] ?? object,
      options: object["options"] as? [String: Any] ?? [:]
    )
  }
}

public enum BridgeCommand: String {
  case returnHome = "host:returnHome"
  case returnHomeLegacy = "host:return_home"
  case log = "host:log"
  case haptic = "host:haptic"
  case export = "host:export"
  case fileBegin = "file:begin"
  case fileChunk = "file:chunk"
  case fileFinish = "file:finish"

  public static func isExport(_ value: String) -> Bool { value == export.rawValue }

  public static func isFile(_ value: String) -> Bool {
    [fileBegin.rawValue, fileChunk.rawValue, fileFinish.rawValue].contains(value)
  }

  public static func isReturnHome(_ value: String) -> Bool {
    value == returnHome.rawValue || value == returnHomeLegacy.rawValue
  }
}
