import Foundation

public enum ResourceMIME {
  public static func type(for path: String) -> String {
    switch (path as NSString).pathExtension.lowercased() {
    case "html", "htm":
      return "text/html; charset=utf-8"
    case "js", "mjs":
      return "application/javascript; charset=utf-8"
    case "css":
      return "text/css; charset=utf-8"
    case "json", "json5":
      return "application/json; charset=utf-8"
    case "wasm":
      return "application/wasm"
    case "svg":
      return "image/svg+xml"
    case "png":
      return "image/png"
    case "jpg", "jpeg":
      return "image/jpeg"
    case "gif":
      return "image/gif"
    case "webp":
      return "image/webp"
    case "mp3":
      return "audio/mpeg"
    case "m4a":
      return "audio/mp4"
    case "ogg":
      return "audio/ogg"
    case "wav":
      return "audio/wav"
    case "mp4":
      return "video/mp4"
    case "webm":
      return "video/webm"
    case "woff":
      return "font/woff"
    case "woff2":
      return "font/woff2"
    case "ttf":
      return "font/ttf"
    default:
      return "application/octet-stream"
    }
  }

  /// Some Gardendless builds disguise M4A containers as `.mp3`; sniff the
  /// header so WebKit receives the correct audio MIME type.
  public static func detectAudioType(
    path: String,
    header: Data
  ) -> String {
    guard (path as NSString).pathExtension.lowercased() == "mp3" else {
      return type(for: path)
    }
    let brands = ["ftypM4A", "ftypisom", "ftypmp42"]
    if brands.contains(where: { header.range(of: Data($0.utf8)) != nil }) {
      return "audio/mp4"
    }
    return "audio/mpeg"
  }
}
