import Foundation

/// Stable, machine-readable failure model shared by every GardendlessKit module.
public enum GameError: Error, LocalizedError {
  public enum Code: String, Sendable, Hashable {
    case invalidSession
    case invalidPath
    case resourceNotFound
    case methodNotAllowed
    case rangeNotSatisfiable
    case resourceReadFailed
    case zipInvalid
    case zipEncrypted
    case zipUnsupported
    case zipSymbolicLink
    case zipPathUnsafe
    case gpNextForbidden
    case gpNextUnavailable
    case exportInProgress
    case exportCancelled
    case exportFailed
    case nativeAudioFailed
    case loggingDegraded
    case unavailable
  }

  case failed(Code, String)
  case underlying(Code, String, Error)

  public var code: Code {
    switch self {
    case .failed(let code, _), .underlying(let code, _, _):
      return code
    }
  }

  public var message: String {
    switch self {
    case .failed(_, let message), .underlying(_, let message, _):
      return message
    }
  }

  public var errorDescription: String? {
    message
  }
}
