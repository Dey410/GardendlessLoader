import Foundation
@testable import GardendlessNativeCore
import WebKit
import XCTest

final class RunnerTests: XCTestCase {
  private var root: URL!

  func testGameViewportLimitsSquareAndUltrawideWindows() {
    XCTAssertEqual(
      GameViewportSize.fit(CGSize(width: 1600, height: 1200)),
      CGSize(width: 1600, height: 1000)
    )
    XCTAssertEqual(
      GameViewportSize.fit(CGSize(width: 2400, height: 1080)),
      CGSize(width: 2040, height: 1080)
    )
  }

  func testGameViewportFillsSupportedAspectRatios() {
    XCTAssertEqual(
      GameViewportSize.fit(CGSize(width: 1600, height: 1000)),
      CGSize(width: 1600, height: 1000)
    )
    XCTAssertEqual(
      GameViewportSize.fit(CGSize(width: 1920, height: 1080)),
      CGSize(width: 1920, height: 1080)
    )
    XCTAssertEqual(
      GameViewportSize.fit(CGSize(width: 1700, height: 900)),
      CGSize(width: 1700, height: 900)
    )
  }

  func testNetworkPolicyBlocksByDefaultAndAllowsOnlyExactHostSuffixes() throws {
    let encoded = try NativeGameNetworkPolicy.encodedRules(for: ["github.com"])
    let rules = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]]
    )

    XCTAssertEqual(rules.count, 3)
    XCTAssertEqual(
      (rules[0]["action"] as? [String: String])?["type"],
      "block"
    )
    XCTAssertEqual(
      (rules[1]["action"] as? [String: String])?["type"],
      "block"
    )
    XCTAssertEqual(
      (rules[2]["action"] as? [String: String])?["type"],
      "ignore-previous-rules"
    )
    let trigger = try XCTUnwrap(rules[2]["trigger"] as? [String: Any])
    XCTAssertEqual(
      trigger["url-filter"] as? String,
      "^https://([a-z0-9-]+\\.)*github\\.com[:/]"
    )
    XCTAssertNil(trigger["unless-domain"])
  }

  func testNetworkPolicyRulesCompileInWebKit() throws {
    let store = try XCTUnwrap(WKContentRuleListStore.default())
    let encoded = try NativeGameNetworkPolicy.encodedRules(for: ["github.com"])
    let compiled = expectation(description: "content rules compile")
    store.compileContentRuleList(
      forIdentifier: "gardendless-test-\(UUID().uuidString)",
      encodedContentRuleList: encoded
    ) { ruleList, error in
      XCTAssertNil(error)
      XCTAssertNotNil(ruleList)
      compiled.fulfill()
    }
    wait(for: [compiled], timeout: 5)
  }

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-scheme-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("<html>game</html>".utf8).write(to: root.appendingPathComponent("index.html"))
    try Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: root.appendingPathComponent("asset.bin"))
    try Data("你好".utf8).write(to: root.appendingPathComponent("你好.json"))
    try Data([0, 0, 0, 24] + Array("ftypM4A ".utf8) + [0, 0, 0, 0])
      .write(to: root.appendingPathComponent("mislabeled.mp3"))
    try Data(Array("ID3genuine-mp3".utf8))
      .write(to: root.appendingPathComponent("genuine.mp3"))
  }

  override func tearDownWithError() throws {
    if root != nil {
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testRootGetAndHead() throws {
    let handler = try GameResourceSchemeHandler(resourceRoot: root)
    let get = try perform(handler, url: "gardendless-game://localhost/")
    XCTAssertEqual(get.statusCode, 200)
    XCTAssertEqual(String(data: get.body, encoding: .utf8), "<html>game</html>")
    XCTAssertEqual(get.headers["content-length"], "17")
    XCTAssertEqual(get.headers["cache-control"], "no-cache")

    let head = try perform(
      handler,
      url: "gardendless-game://localhost/index.html",
      method: "HEAD"
    )
    XCTAssertEqual(head.statusCode, 200)
    XCTAssertTrue(head.body.isEmpty)
    XCTAssertEqual(head.headers["content-length"], "17")
  }

  func testRangeEtagMimeAndUnicode() throws {
    let handler = try GameResourceSchemeHandler(resourceRoot: root)
    let partial = try perform(
      handler,
      url: "gardendless-game://localhost/asset.bin",
      headers: ["Range": "bytes=2-5"]
    )
    XCTAssertEqual(partial.statusCode, 206)
    XCTAssertEqual(partial.body, Data([2, 3, 4, 5]))
    XCTAssertEqual(partial.headers["content-range"], "bytes 2-5/10")
    XCTAssertEqual(partial.headers["accept-ranges"], "bytes")
    XCTAssertEqual(partial.headers["content-type"], "application/octet-stream")

    let notModified = try perform(
      handler,
      url: "gardendless-game://localhost/asset.bin",
      headers: ["If-None-Match": try XCTUnwrap(partial.headers["etag"])]
    )
    XCTAssertEqual(notModified.statusCode, 304)
    XCTAssertTrue(notModified.body.isEmpty)

    let unicode = try perform(
      handler,
      url: "gardendless-game://localhost/%E4%BD%A0%E5%A5%BD.json"
    )
    XCTAssertEqual(unicode.statusCode, 200)
    XCTAssertEqual(unicode.headers["content-type"], "application/json; charset=utf-8")
    XCTAssertEqual(String(data: unicode.body, encoding: .utf8), "你好")
  }

  func testMp3PathWithM4AContainerUsesAudioMp4MimeType() throws {
    let handler = try GameResourceSchemeHandler(resourceRoot: root)
    for (index, brand) in ["ftypM4A", "ftypisom", "ftypmp42"].enumerated() {
      let name = "mislabeled-\(index).mp3"
      try Data([0, 0, 0, 24] + Array(brand.utf8) + [0, 0, 0, 0])
        .write(to: root.appendingPathComponent(name))
      let response = try perform(
        handler,
        url: "gardendless-game://localhost/\(name)"
      )

      XCTAssertEqual(response.statusCode, 200)
      XCTAssertEqual(response.headers["content-type"], "audio/mp4")
    }

    let genuine = try perform(
      handler,
      url: "gardendless-game://localhost/genuine.mp3"
    )
    XCTAssertEqual(genuine.headers["content-type"], "audio/mpeg")
  }

  func testSmallAudioCacheServesRepeatedRangeInOneDataCallback() throws {
    let handler = try GameResourceSchemeHandler(resourceRoot: root)
    let file = root.appendingPathComponent("mislabeled.mp3")
    let contents = try Data(contentsOf: file)

    let first = try perform(
      handler,
      url: "gardendless-game://localhost/mislabeled.mp3"
    )
    XCTAssertEqual(first.dataCallbackCount, 1)

    try FileManager.default.removeItem(at: file)
    let repeated = try perform(
      handler,
      url: "gardendless-game://localhost/mislabeled.mp3",
      headers: ["Range": "bytes=4-11"]
    )
    XCTAssertEqual(repeated.statusCode, 206)
    XCTAssertEqual(repeated.body, contents.subdata(in: 4..<12))
    XCTAssertEqual(repeated.dataCallbackCount, 1)
  }

  func testStoppedAudioTaskReceivesNoFurtherCallbacks() throws {
    let handler = try GameResourceSchemeHandler(resourceRoot: root)
    let webView = WKWebView()
    let task = FakeSchemeTask(
      request: request(url: "gardendless-game://localhost/mislabeled.mp3")
    )
    let stopped = expectation(description: "scheme task stopped")
    task.finished.isInverted = true
    task.onResponse = {
      handler.webView(webView, stop: task)
      stopped.fulfill()
    }

    handler.webView(webView, start: task)
    wait(for: [stopped, task.finished], timeout: 0.25)
    XCTAssertTrue(task.body.isEmpty)
    XCTAssertNil(task.failure)
  }

  func testRejectsInvalidRangesMethodsOriginsAndTraversal() throws {
    let handler = try GameResourceSchemeHandler(resourceRoot: root)
    let range = try perform(
      handler,
      url: "gardendless-game://localhost/asset.bin",
      headers: ["Range": "bytes=99-100"]
    )
    XCTAssertEqual(range.statusCode, 416)
    XCTAssertEqual(range.headers["content-range"], "bytes */10")

    XCTAssertEqual(
      try perform(handler, url: "gardendless-game://localhost/index.html", method: "POST").statusCode,
      405
    )
    XCTAssertEqual(
      try perform(handler, url: "gardendless-game://foreign/index.html").statusCode,
      403
    )
    XCTAssertEqual(
      try perform(handler, url: "gardendless-game://localhost/%2e%2e/secret").statusCode,
      404
    )
    XCTAssertEqual(
      try perform(handler, url: "gardendless-game://localhost/%252e%252e/secret").statusCode,
      404
    )
  }

  func testRejectsSymbolicLinksAndSupportsConcurrentStreaming() throws {
    let outside = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-outside-\(UUID().uuidString)")
    try Data("outside".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("linked.bin"),
      withDestinationURL: outside
    )
    let handler = try GameResourceSchemeHandler(resourceRoot: root)
    XCTAssertEqual(
      try perform(handler, url: "gardendless-game://localhost/linked.bin").statusCode,
      404
    )

    let large = Data((0..<(4 * 1024 * 1024)).map { UInt8($0 & 0xff) })
    try large.write(to: root.appendingPathComponent("large.bin"))
    let tasks = (0..<8).map { index in
      FakeSchemeTask(
        request: request(
          url: "gardendless-game://localhost/large.bin",
          headers: ["Range": "bytes=\(index * 4096)-\(index * 4096 + 4095)"]
        )
      )
    }
    for task in tasks {
      handler.webView(WKWebView(), start: task)
    }
    wait(for: tasks.map(\.finished), timeout: 5)
    for task in tasks {
      XCTAssertNil(task.failure)
      XCTAssertEqual(task.statusCode, 206)
      XCTAssertEqual(task.body.count, 4096)
    }
  }

  func testSwitchingResourceRootsUsesTheNewHandlerRoot() throws {
    let other = FileManager.default.temporaryDirectory
      .appendingPathComponent("gardendless-other-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: other) }
    try Data("other".utf8).write(to: other.appendingPathComponent("index.html"))

    let first = try GameResourceSchemeHandler(resourceRoot: root)
    let second = try GameResourceSchemeHandler(resourceRoot: other)
    XCTAssertEqual(
      String(data: try perform(first, url: "gardendless-game://localhost/").body, encoding: .utf8),
      "<html>game</html>"
    )
    XCTAssertEqual(
      String(data: try perform(second, url: "gardendless-game://localhost/").body, encoding: .utf8),
      "other"
    )
  }

  private func perform(
    _ handler: GameResourceSchemeHandler,
    url: String,
    method: String = "GET",
    headers: [String: String] = [:]
  ) throws -> FakeSchemeTask {
    let task = FakeSchemeTask(request: request(url: url, method: method, headers: headers))
    handler.webView(WKWebView(), start: task)
    wait(for: [task.finished], timeout: 3)
    if let failure = task.failure {
      throw failure
    }
    return task
  }

  private func request(
    url: String,
    method: String = "GET",
    headers: [String: String] = [:]
  ) -> URLRequest {
    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = method
    for (name, value) in headers {
      request.setValue(value, forHTTPHeaderField: name)
    }
    return request
  }
}

private final class FakeSchemeTask: NSObject, WKURLSchemeTask, @unchecked Sendable {
  let request: URLRequest
  let finished = XCTestExpectation(description: "scheme task finished")
  private let lock = NSLock()
  private var response: URLResponse?
  private(set) var body = Data()
  private(set) var failure: Error?
  private(set) var dataCallbackCount = 0
  var onResponse: (() -> Void)?

  init(request: URLRequest) {
    self.request = request
  }

  var statusCode: Int? {
    lock.withLock { (response as? HTTPURLResponse)?.statusCode }
  }

  var headers: [String: String] {
    lock.withLock {
      guard let values = (response as? HTTPURLResponse)?.allHeaderFields else { return [:] }
      return Dictionary(uniqueKeysWithValues: values.compactMap { key, value in
        guard let key = key as? String else { return nil }
        return (key.lowercased(), String(describing: value))
      })
    }
  }

  func didReceive(_ response: URLResponse) {
    lock.withLock { self.response = response }
    onResponse?()
  }

  func didReceive(_ data: Data) {
    lock.withLock {
      body.append(data)
      dataCallbackCount += 1
    }
  }

  func didFinish() {
    finished.fulfill()
  }

  func didFailWithError(_ error: Error) {
    lock.withLock { failure = error }
    finished.fulfill()
  }
}

private extension NSLock {
  func withLock<T>(_ action: () -> T) -> T {
    lock()
    defer { unlock() }
    return action()
  }
}
