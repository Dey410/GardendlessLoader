import Foundation
import WebKit
import XCTest
@testable import GardendlessCore

final class NetworkPolicyTests: XCTestCase {
  func testEncodedRulesBlockByDefaultBeforeAllowRules() throws {
    let encoded = try NetworkPolicy.encodedRules(for: ["github.com"])
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
  }

  func testAllowRuleRequiresActualHostAndOptionalNumericPort() throws {
    let encoded = try NetworkPolicy.encodedRules(for: ["github.com"])
    let rules = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]]
    )
    let trigger = try XCTUnwrap(rules.last?["trigger"] as? [String: Any])
    let pattern = try XCTUnwrap(trigger["url-filter"] as? String)
    let allowRule = try NSRegularExpression(pattern: pattern)
    for (raw, allowed) in [
      ("https://github.com/", true),
      ("https://api.github.com/repos", true),
      ("https://github.com:8443/repos", true),
      ("https://api.github.com:8443/repos", true),
      ("http://github.com/repos", false),
      ("https://github.com.evil.test/repos", false),
      ("https://notgithub.com/repos", false),
      ("https://github.com:password@evil.test/repos", false),
      ("https://github.com:443@evil.test/repos", false),
      ("https://api.github.com:8443@evil.test/repos", false),
      ("https://github.com@evil.test/repos", false),
    ] {
      let url = try XCTUnwrap(URL(string: raw))
      let serialized = url.absoluteString
      let matched = allowRule.firstMatch(
        in: serialized,
        range: NSRange(serialized.startIndex..., in: serialized)
      ) != nil
      XCTAssertEqual(matched, allowed, raw)
      if matched {
        XCTAssertTrue(url.host == "github.com" || url.host?.hasSuffix(".github.com") == true)
      }
    }
  }

  func testEncodedRulesAllowNoHostsWhenSetIsEmpty() throws {
    let encoded = try NetworkPolicy.encodedRules(for: [])
    let rules = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]]
    )
    XCTAssertEqual(rules.count, 2)
  }

  func testRulesCompileInWebKit() throws {
    let store = try XCTUnwrap(WKContentRuleListStore.default())
    let encoded = try NetworkPolicy.encodedRules(for: ["github.com"])
    let compiled = expectation(description: "content rules compile")
    store.compileContentRuleList(
      forIdentifier: "gardendless-kit-test-\(UUID().uuidString)",
      encodedContentRuleList: encoded
    ) { ruleList, error in
      XCTAssertNil(error)
      XCTAssertNotNil(ruleList)
      compiled.fulfill()
    }
    wait(for: [compiled], timeout: 5)
  }
}
