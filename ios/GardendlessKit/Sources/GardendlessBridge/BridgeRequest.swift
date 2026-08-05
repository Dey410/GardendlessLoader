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
  case setWatermark = "host:setWatermark"
  case setWatermarkLegacy = "host:set_watermark"
  case log = "host:log"
  case export = "host:export"
  case exportBegin = "host:exportBegin"
  case exportChunk = "host:exportChunk"
  case exportCommit = "host:exportCommit"
  case exportAbort = "host:exportAbort"

  public static func isExport(_ value: String) -> Bool {
    [
      export.rawValue,
      exportBegin.rawValue,
      exportChunk.rawValue,
      exportCommit.rawValue,
      exportAbort.rawValue,
    ].contains(value)
  }

  public static func isWatermark(_ value: String) -> Bool {
    value == setWatermark.rawValue || value == setWatermarkLegacy.rawValue
  }

  public static func isReturnHome(_ value: String) -> Bool {
    value == returnHome.rawValue || value == returnHomeLegacy.rawValue
  }
}
