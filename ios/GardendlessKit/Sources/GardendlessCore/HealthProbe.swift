import Foundation

public struct HealthReport: Equatable, Sendable {
  public let writable: Bool
  public let message: String

  public init(writable: Bool, message: String) {
    self.writable = writable
    self.message = message
  }
}

public enum HealthProbe {
  /// Verifies that the native host can create, write, and remove files.
  public static func run(
    probeDirectory: URL = FileManager.default.temporaryDirectory
  ) -> HealthReport {
    do {
      try FileManager.default.createDirectory(
        at: probeDirectory,
        withIntermediateDirectories: true
      )
      let probe = probeDirectory
        .appendingPathComponent(".gardendless-health-\(UUID().uuidString)")
      try Data("ok".utf8).write(to: probe, options: .atomic)
      try FileManager.default.removeItem(at: probe)
      return HealthReport(writable: true, message: "file system is writable")
    } catch {
      return HealthReport(writable: false, message: error.localizedDescription)
    }
  }
}
