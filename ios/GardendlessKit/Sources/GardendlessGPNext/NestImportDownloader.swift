import CryptoKit
import Foundation

/// The GP-Next-facing reason a Nest download failed, such as NEST_HASH or
/// Nest's own error code (game-import-unsupported).
public struct NestImportError: LocalizedError {
  public let reason: String
  public var errorDescription: String? { reason }
}

/// GP-Next's download_nest_import contract. Nest answers
/// https://nest.pvzge.com/api/game-imports/<version> with a descriptor that
/// names a short-lived package URL, its SHA-256 and its size. GP-Next expects
/// the package framed as a little-endian u32 descriptor length, the
/// descriptor JSON and the package bytes, and validates all three again.
public final class NestImportDownloader: NSObject, URLSessionDataDelegate {
  public static let maximumPackageBytes = 100 * 1024 * 1024
  private static let maximumLevelBytes = 10_000_000
  private static let maximumDescriptorBytes = 64 * 1024
  private static let maximumHeaderBytes = 16 * 1024
  private static let uuidPattern = "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"

  private struct Descriptor {
    let header: Data
    let url: URL
    let sha256: String
    let byteLength: Int
  }

  private final class Stream {
    let file: URL
    let handle: FileHandle
    let expected: Descriptor
    let completion: (Result<URL, Error>) -> Void
    var hasher = SHA256()
    var received = 0
    var failure: String?

    init(file: URL, handle: FileHandle, expected: Descriptor, completion: @escaping (Result<URL, Error>) -> Void) {
      self.file = file
      self.handle = handle
      self.expected = expected
      self.completion = completion
    }
  }

  private let directory: URL
  private let delegateQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 240
    return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
  }()
  private let lock = NSLock()
  private var busy = false
  private var cancelled = false
  private var streams: [Int: Stream] = [:]

  /// Downloads go to `directory`; files left there by an earlier process are removed.
  public init(directory: URL) {
    self.directory = directory
    super.init()
    DispatchQueue.global(qos: .utility).async {
      let stale = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
      stale.forEach { try? FileManager.default.removeItem(at: $0) }
    }
  }

  /// Delivers a temporary file holding the framed package; the caller owns it.
  public func download(versionId: String, completion: @escaping (Result<URL, Error>) -> Void) {
    guard versionId.range(of: Self.uuidPattern, options: .regularExpression) != nil else {
      completion(.failure(NestImportError(reason: "NEST_INTENT")))
      return
    }
    lock.lock()
    let admitted = !busy && !cancelled
    if admitted { busy = true }
    lock.unlock()
    guard admitted else {
      completion(.failure(NestImportError(reason: "NEST_BUSY")))
      return
    }
    let finish: (Result<URL, Error>) -> Void = { [weak self] result in
      self?.lock.lock()
      self?.busy = false
      self?.lock.unlock()
      completion(result)
    }
    var request = URLRequest(url: URL(string: "https://nest.pvzge.com/api/game-imports/\(versionId)")!)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    session.dataTask(with: request) { [weak self] data, response, error in
      guard let self else { return }
      do {
        if error != nil { throw NestImportError(reason: "NEST_NETWORK") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = data ?? Data()
        guard body.count <= Self.maximumDescriptorBytes else { throw NestImportError(reason: "NEST_DESCRIPTOR") }
        guard status == 200 else {
          throw NestImportError(reason: Self.errorCode(body) ?? "NEST_HTTP_\(status)")
        }
        let descriptor = try Self.parse(body, versionId: versionId)
        try self.downloadPackage(descriptor, completion: finish)
      } catch {
        finish(.failure(error))
      }
    }.resume()
  }

  public func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
    session.invalidateAndCancel()
  }

  private func downloadPackage(_ descriptor: Descriptor, completion: @escaping (Result<URL, Error>) -> Void) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("nest-\(UUID().uuidString).bin")
    guard FileManager.default.createFile(atPath: file.path, contents: nil),
          let handle = try? FileHandle(forWritingTo: file) else {
      throw NestImportError(reason: "NEST_WRITE")
    }
    do {
      var length = UInt32(descriptor.header.count).littleEndian
      try handle.write(contentsOf: Data(bytes: &length, count: 4))
      try handle.write(contentsOf: descriptor.header)
    } catch {
      try? handle.close()
      try? FileManager.default.removeItem(at: file)
      throw NestImportError(reason: "NEST_WRITE")
    }
    var request = URLRequest(url: descriptor.url)
    // Without transparent decompression the received bytes are the bytes Nest hashed.
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let task = session.dataTask(with: request)
    // The descriptor's completion handler already runs on delegateQueue,
    // which owns `streams` together with the delegate callbacks.
    streams[task.taskIdentifier] = Stream(file: file, handle: handle, expected: descriptor, completion: completion)
    task.resume()
  }

  // MARK: URLSessionDataDelegate

  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let stream = streams[dataTask.taskIdentifier] else {
      completionHandler(.allow)
      return
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status != 200 {
      stream.failure = "NEST_HTTP_\(status)"
    } else if response.expectedContentLength > Int64(stream.expected.byteLength) {
      stream.failure = "NEST_LENGTH"
    }
    completionHandler(stream.failure == nil ? .allow : .cancel)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard let stream = streams[dataTask.taskIdentifier], stream.failure == nil else { return }
    stream.received += data.count
    guard stream.received <= stream.expected.byteLength else {
      stream.failure = "NEST_LENGTH"
      dataTask.cancel()
      return
    }
    stream.hasher.update(data: data)
    do { try stream.handle.write(contentsOf: data) } catch {
      stream.failure = "NEST_WRITE"
      dataTask.cancel()
    }
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let stream = streams.removeValue(forKey: task.taskIdentifier) else { return }
    var failure = stream.failure ?? (error == nil ? nil : "NEST_NETWORK")
    if failure == nil, stream.received != stream.expected.byteLength { failure = "NEST_LENGTH" }
    if failure == nil {
      let digest = stream.hasher.finalize().map { String(format: "%02x", $0) }.joined()
      if digest != stream.expected.sha256 { failure = "NEST_HASH" }
    }
    if failure == nil {
      do { try stream.handle.synchronize() } catch { failure = "NEST_WRITE" }
    }
    try? stream.handle.close()
    if let failure {
      try? FileManager.default.removeItem(at: stream.file)
      stream.completion(.failure(NestImportError(reason: failure)))
    } else {
      stream.completion(.success(stream.file))
    }
  }

  // MARK: Descriptor

  private static func errorCode(_ body: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let code = object["error"] as? String,
          code.range(of: "^[a-z0-9-]{1,64}$", options: .regularExpression) != nil else { return nil }
    return code
  }

  private static func parse(_ body: Data, versionId: String) throws -> Descriptor {
    guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let protocolVersion = json["protocolVersion"] as? NSNumber,
          CFGetTypeID(protocolVersion) != CFBooleanGetTypeID(), protocolVersion == 1,
          json["versionId"] as? String == versionId,
          let projectId = json["projectId"] as? String, projectId.hasPrefix("prj_"),
          String(projectId.dropFirst(4)).range(of: uuidPattern, options: .regularExpression) != nil,
          let name = json["name"] as? String, !name.isEmpty,
          let version = json["version"] as? String, !version.isEmpty,
          let sha256 = json["sha256"] as? String,
          sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
          let size = json["byteLength"] as? NSNumber, CFGetTypeID(size) != CFBooleanGetTypeID(),
          size.doubleValue.rounded(.towardZero) == size.doubleValue, size.doubleValue > 0,
          let expiresAt = json["expiresAt"] as? String, !expiresAt.isEmpty,
          let type = json["type"] as? String, let format = json["format"] as? String else {
      throw NestImportError(reason: "NEST_DESCRIPTOR")
    }
    let level = type == "level" && ["json", "json5"].contains(format)
    let archive = ["datapack", "mod"].contains(type) && format == "zip"
    guard level || archive else { throw NestImportError(reason: "NEST_UNSUPPORTED_FORMAT") }
    guard size.doubleValue <= Double(level ? maximumLevelBytes : maximumPackageBytes) else {
      throw NestImportError(reason: "NEST_LENGTH")
    }
    guard let raw = json["url"] as? String, let url = downloadURL(raw) else {
      throw NestImportError(reason: "NEST_DOWNLOAD_URL")
    }
    // Only the fields GP-Next reads travel on; the signed URL stays here.
    let header: [String: Any] = [
      "protocolVersion": 1,
      "versionId": versionId,
      "projectId": projectId,
      "type": type,
      "format": format,
      "version": version,
      "name": name,
      "expiresAt": expiresAt,
      "sha256": sha256,
      "byteLength": size.intValue,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: header),
          data.count <= maximumHeaderBytes else {
      throw NestImportError(reason: "NEST_DESCRIPTOR")
    }
    return Descriptor(header: data, url: url, sha256: sha256, byteLength: size.intValue)
  }

  /// Nest serves packages from its Cloudflare R2 bucket through presigned
  /// HTTPS URLs; the bytes must still match the descriptor's SHA-256.
  private static func downloadURL(_ raw: String) -> URL? {
    guard let components = URLComponents(string: raw),
          components.scheme == "https",
          components.user == nil, components.password == nil, components.fragment == nil,
          components.port == nil || components.port == 443,
          let host = components.host?.lowercased(),
          host == "nest.pvzge.com" || host.hasSuffix(".r2.cloudflarestorage.com") else { return nil }
    return components.url
  }
}
