import Foundation

public enum GpNextConstants {
  /// Tauri AppData directory identifier exposed by the compat bridge.
  public static let appDataBaseDirectoryID = 14
  public static let allowedImportExtensions: Set<String> = ["zip", "json", "json5"]
  public static let maxImportScanTailBytes = 65_557
}
