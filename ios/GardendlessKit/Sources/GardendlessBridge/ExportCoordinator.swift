import Darwin
import Foundation
import GardendlessCore
import GardendlessGPNext

/// Owns binary reads, GP writes, and Blob exports for one native session.
/// Descriptors, cursors, and picker transactions share this bounded IO queue.
public final class FileTaskCoordinator {
  public static let chunkBytes = 64 * 1024
  public static let maximumBytes = 512 * 1024 * 1024
  public static let maximumHandles = 8
  private static let maximumQueuedOperations = 16
  private static let maximumFinishedHandles = 128
  private static let handleLifetime: TimeInterval = 10 * 60

  private enum Outcome { case closed, committed, cancelled, expired, failed }
  private struct Finished {
    let reading: Bool
    let outcome: Outcome
  }
  private final class Transfer {
    let handle: FileHandle
    let temporary: URL?
    let destination: URL
    let reading: Bool
    let exporting: Bool
    let size: Int
    let deadline: TimeInterval
    var offset = 0
    var index = 0
    var exportPending = false

    init(handle: FileHandle, temporary: URL?, destination: URL,
         reading: Bool, exporting: Bool, size: Int, deadline: TimeInterval) {
      self.handle = handle
      self.temporary = temporary
      self.destination = destination
      self.reading = reading
      self.exporting = exporting
      self.size = size
      self.deadline = deadline
    }
  }

  /// Dismisses the matching picker on main; its success callback checks this owner first.
  public var onExportCancelled: ((URL, String) -> Void)?
  private let session: GameSession
  private let router: GpNextCommandRouter?
  private let now: () -> TimeInterval
  private let queue = DispatchQueue(label: "io.github.dey410.gardendless.file", qos: .userInitiated)
  private let lock = NSLock()
  private var alive = true
  private var queued = 0
  private var terminalHandles = Set<String>()
  private var transfers: [String: Transfer] = [:]
  private var finished: [String: Finished] = [:]
  private var finishedOrder: [String] = []
  private var pendingExports: [URL: String] = [:]
  private var deadlineTimer: DispatchSourceTimer?

  public init(session: GameSession, gpNextRouter: GpNextCommandRouter?,
              clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) throws {
    self.session = session
    router = gpNextRouter
    now = clock
    try FileManager.default.createDirectory(at: session.exportTemporaryRoot, withIntermediateDirectories: true)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 60, repeating: 60)
    timer.setEventHandler { [weak self] in self?.expireHandles() }
    timer.resume()
    deadlineTimer = timer
  }

  public var isActive: Bool {
    lock.lock()
    defer { lock.unlock() }
    return alive
  }

  public func exportHandle(for file: URL) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return alive ? pendingExports[file] : nil
  }

  /// The queue bound also applies to GP metadata/control disk operations.
  public func submit(command: String, arguments: [String: Any],
                     completion: @escaping (Result<GpNextAction, Error>) -> Void) {
    let control = command == "file:finish"
      && ["close", "cancel"].contains(arguments["action"] as? String ?? "")
    let terminal = control ? arguments["handle"] as? String : nil
    enqueue(terminal: terminal, work: { try self.dispatch(command, arguments) }, completion: completion)
  }

  public func submitGpNext(_ request: [String: Any],
                           completion: @escaping (Result<GpNextAction, Error>) -> Void) {
    enqueue(terminal: nil, work: {
      guard let router = self.router else { throw self.failure("GP-Next compatibility is unavailable") }
      return try router.dispatch(request)
    }, completion: completion)
  }

  private func enqueue(terminal: String?, work: @escaping () throws -> GpNextAction,
                       completion: @escaping (Result<GpNextAction, Error>) -> Void) {
    lock.lock()
    let admitted = alive && (terminal.map {
      (transfers[$0] != nil || finished[$0] != nil)
        && terminalHandles.count < Self.maximumHandles && terminalHandles.insert($0).inserted
    } ?? (queued < Self.maximumQueuedOperations))
    if admitted && terminal == nil { queued += 1 }
    lock.unlock()
    guard admitted else {
      deliver(.failure(failure("File task queue is full or handle is unknown")), completion)
      return
    }
    queue.async {
      let result: Result<GpNextAction, Error> = self.isActive
        ? Result { try work() } : .failure(self.failure("Game host is destroyed"))
      self.lock.lock()
      if let terminal { self.terminalHandles.remove(terminal) } else { self.queued -= 1 }
      self.lock.unlock()
      self.deliver(result, completion)
    }
  }

  private func deliver<T>(_ result: Result<T, Error>, _ completion: @escaping (Result<T, Error>) -> Void) {
    DispatchQueue.main.async { if self.isActive { completion(result) } }
  }

  public func destroy() {
    lock.lock()
    let wasAlive = alive
    alive = false
    lock.unlock()
    guard wasAlive else { return }
    deadlineTimer?.cancel()
    queue.async {
      for transfer in self.transfers.values {
        self.close(transfer, discard: true)
        if transfer.exportPending { try? FileManager.default.removeItem(at: transfer.destination) }
      }
      self.lock.lock()
      self.transfers.removeAll()
      self.pendingExports.removeAll()
      self.lock.unlock()
    }
  }

  /// System picker completion is serialized with JS cancellation and expiry.
  public func finishExport(handle: String, cancelled: Bool,
                           completion: @escaping (Result<Void, Error>) -> Void) {
    enqueue(terminal: handle, work: {
      if let old = self.finished[handle] {
        guard !cancelled, old.outcome == .committed else {
          throw self.failure("Export was cancelled or expired")
        }
        return .value(NSNull())
      }
      let transfer = try self.lookup(["handle": handle])
      guard transfer.exportPending else { throw self.failure("Export picker is not pending") }
      self.retire(handle, transfer, outcome: cancelled ? .cancelled : .committed)
      try? FileManager.default.removeItem(at: transfer.destination)
      return .value(NSNull())
    }, completion: { completion($0.map { _ in () }) })
  }

  private func dispatch(_ command: String, _ args: [String: Any]) throws -> GpNextAction {
    switch command {
    case "file:begin": return .value(try begin(args))
    case "file:chunk": return .value(try chunk(args))
    case "file:finish": return try finish(args)
    default: throw failure("Unknown file command")
    }
  }

  private func begin(_ args: [String: Any]) throws -> [String: Any] {
    guard transfers.count < Self.maximumHandles,
          let mode = args["mode"] as? String, ["read", "write"].contains(mode),
          let destination = args["destination"] as? String,
          ["gp-next", "export"].contains(destination) else { throw failure("Invalid file begin") }
    let reading = mode == "read"
    let writeSize = reading ? 0 : try integer(args, "totalBytes")
    let options = args["options"] as? [String: Any] ?? [:]
    guard options["append"] as? Bool != true else { throw failure("Append writes are unsupported") }
    let path: URL
    if destination == "gp-next" {
      guard session.hasGpNext, session.gpNextCompatible, let router,
            let rawPath = args["path"] as? String else { throw failure("GP-Next is unavailable or path is missing") }
      path = try reading
        ? router.resolveReadPath(path: rawPath, options: options)
        : router.resolveWritePath(path: rawPath, options: options)
    } else {
      guard !reading else { throw failure("Export is write-only") }
      let name = safeName(args["suggestedFilename"] as? String ?? "gardendless-export.json")
      let requested = session.exportTemporaryRoot.appendingPathComponent(name)
      let occupied = FileManager.default.fileExists(atPath: requested.path)
        || transfers.values.contains { $0.destination == requested }
      path = occupied
        ? session.exportTemporaryRoot.appendingPathComponent("\(UUID().uuidString.prefix(8))-\(name)")
        : requested
    }
    let transfer: Transfer
    let deadline = now() + Self.handleLifetime
    if reading {
      let descriptor = Darwin.open(path.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor >= 0 else { throw failure("Unable to open GP-Next file") }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      do {
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= Self.maximumBytes else { throw failure("Invalid file type or size") }
        transfer = Transfer(handle: handle, temporary: nil, destination: path,
                            reading: true, exporting: false, size: Int(info.st_size), deadline: deadline)
      } catch { try? handle.close(); throw error }
    } else {
      guard !transfers.values.contains(where: { !$0.reading && $0.destination == path }) else {
        throw failure("Another write owns this destination")
      }
      let temporary = path.deletingLastPathComponent().appendingPathComponent(".gardendless-file-\(UUID().uuidString)")
      let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { throw failure("Unable to create file transaction") }
      transfer = Transfer(handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true),
                          temporary: temporary, destination: path, reading: false,
                          exporting: destination == "export", size: writeSize, deadline: deadline)
    }
    let token = "\(session.sessionId)-\(UUID().uuidString)"
    lock.lock()
    transfers[token] = transfer
    lock.unlock()
    return ["handle": token, "sizeBytes": transfer.size]
  }

  private func chunk(_ args: [String: Any]) throws -> Any {
    let transfer = try lookup(args)
    guard !transfer.exportPending else { throw failure("Export commit is already pending") }
    guard try integer(args, "index") == transfer.index,
          try integer(args, "offset") == transfer.offset else { throw failure("File chunk is out of order") }
    let count: Int
    let result: Any
    if transfer.reading {
      count = try integer(args, "length")
      guard count > 0, count <= Self.chunkBytes, count <= transfer.size - transfer.offset else {
        throw failure("Invalid read chunk length")
      }
      let data = try transfer.handle.read(upToCount: count) ?? Data()
      guard data.count == count else { throw failure("File changed or read was incomplete") }
      result = ["data": data.base64EncodedString()]
    } else {
      guard let encoded = args["data"] as? String,
            encoded.utf8.count <= ((Self.chunkBytes + 2) / 3) * 4,
            let data = Data(base64Encoded: encoded), !data.isEmpty,
            data.count <= Self.chunkBytes, data.count <= transfer.size - transfer.offset else {
        throw failure("Invalid write chunk")
      }
      count = data.count
      try transfer.handle.write(contentsOf: data)
      result = NSNull()
    }
    transfer.index += 1
    transfer.offset += count
    return result
  }

  private func finish(_ args: [String: Any]) throws -> GpNextAction {
    guard let token = args["handle"] as? String, let action = args["action"] as? String,
          ["close", "commit", "cancel"].contains(action) else { throw failure("Invalid file finish") }
    if let old = finished[token] { return try terminalReply(old, action: action) }
    guard let transfer = transfers[token] else { throw failure("Unknown file handle") }
    if now() >= transfer.deadline {
      expire(token, transfer)
      return try terminalReply(Finished(reading: transfer.reading, outcome: .expired), action: action)
    }
    if action == "cancel" {
      retire(token, transfer, outcome: .cancelled)
      close(transfer, discard: true)
      if transfer.exportPending { cancelExport(transfer.destination, code: "cancelled") }
      return .value(NSNull())
    }
    guard !transfer.exportPending else { throw failure("Export commit is already pending") }
    if transfer.reading {
      guard action == "close" else { throw failure("Read handles require close") }
      try transfer.handle.close()
      retire(token, transfer, outcome: .closed)
      return .value(NSNull())
    }
    guard action == "commit", transfer.offset == transfer.size,
          let temporary = transfer.temporary else { throw failure("Write did not receive every byte") }
    if !transfer.exporting {
      _ = try router?.resolveWritePath(path: transfer.destination.path, options: [:])
    }
    try transfer.handle.synchronize()
    try transfer.handle.close()
    // This short critical section orders the final rename against destruction.
    lock.lock()
    let committed = alive && Darwin.rename(temporary.path, transfer.destination.path) == 0
    lock.unlock()
    guard committed else {
      retire(token, transfer, outcome: .failed)
      close(transfer, discard: true)
      throw failure("Unable to commit file transaction")
    }
    if transfer.exporting || router?.consumePendingExport(transfer.destination) == true {
      lock.lock()
      transfer.exportPending = true
      pendingExports[transfer.destination] = token
      lock.unlock()
      return .exportFile(transfer.destination)
    }
    retire(token, transfer, outcome: .committed)
    return .value(NSNull())
  }

  private func terminalReply(_ old: Finished, action: String) throws -> GpNextAction {
    if action == "cancel" { return .value(NSNull()) }
    guard (old.reading && action == "close") || (!old.reading && action == "commit") else {
      throw failure("Invalid finish action for file mode")
    }
    switch old.outcome {
    case .closed, .committed: return .value(NSNull())
    case .cancelled: throw failure("File transaction was cancelled")
    case .expired: throw failure("File transaction expired")
    case .failed: throw failure("File transaction failed")
    }
  }

  private func lookup(_ args: [String: Any]) throws -> Transfer {
    guard let token = args["handle"] as? String, let transfer = transfers[token] else {
      throw failure("File handle is unknown or belongs to another session")
    }
    if now() >= transfer.deadline {
      expire(token, transfer)
      throw failure("File transaction expired")
    }
    return transfer
  }

  private func retire(_ token: String, _ transfer: Transfer, outcome: Outcome) {
    lock.lock()
    transfers.removeValue(forKey: token)
    pendingExports.removeValue(forKey: transfer.destination)
    finished[token] = Finished(reading: transfer.reading, outcome: outcome)
    finishedOrder.append(token)
    while finishedOrder.count > Self.maximumFinishedHandles {
      finished.removeValue(forKey: finishedOrder.removeFirst())
    }
    lock.unlock()
  }

  private func expireHandles() {
    guard isActive else { return }
    for (token, transfer) in transfers.filter({ now() >= $0.value.deadline }) { expire(token, transfer) }
  }

  private func expire(_ token: String, _ transfer: Transfer) {
    retire(token, transfer, outcome: .expired)
    close(transfer, discard: true)
    if transfer.exportPending { cancelExport(transfer.destination, code: "deadline_exceeded") }
  }

  private func cancelExport(_ file: URL, code: String) {
    // Remove on this serial queue before another writer can reuse the path.
    // A late picker success observes the retired token and cannot report success.
    try? FileManager.default.removeItem(at: file)
    DispatchQueue.main.async { if self.isActive { self.onExportCancelled?(file, code) } }
  }

  private func integer(_ args: [String: Any], _ key: String) throws -> Int {
    guard let number = args[key] as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
          number.doubleValue >= 0, number.doubleValue <= Double(Self.maximumBytes) else {
      throw failure("\(key) must be a non-negative integer")
    }
    return number.intValue
  }

  private func close(_ transfer: Transfer, discard: Bool) {
    try? transfer.handle.close()
    if discard, let temporary = transfer.temporary { try? FileManager.default.removeItem(at: temporary) }
  }

  private func failure(_ message: String) -> GameError { .failed(.exportFailed, message) }

  private func safeName(_ raw: String) -> String {
    let name = (raw.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
      .replacingOccurrences(of: "[\\x00-\\x1f:*?\"<>|]", with: "_", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty || name == "." || name == ".." ? "gardendless-export.json" : name
  }

  deinit { deadlineTimer?.cancel() }
}
