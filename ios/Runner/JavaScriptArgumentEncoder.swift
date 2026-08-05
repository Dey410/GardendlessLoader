import Foundation

enum JavaScriptArgumentEncoder {
  static func string(_ value: String) -> String? {
    guard let data = try? JSONSerialization.data(
      withJSONObject: value,
      options: [.fragmentsAllowed]
    ),
          let encoded = String(data: data, encoding: .utf8) else {
      return nil
    }
    return encoded
  }
}
