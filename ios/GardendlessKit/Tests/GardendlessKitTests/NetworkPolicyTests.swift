import Foundation
import WebKit
import XCTest
@testable import GardendlessCore

final class NetworkPolicyTests: XCTestCase {
  func testEncodedRulesBlockByDefaultAndAllowOnlyExactHostSuffixes() throws {
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
    let trigger = try XCTUnwrap(rules[2]["trigger"] as? [String: Any])
    XCTAssertEqual(
      trigger["url-filter"] as? String,
      "^https://([a-z0-9-]+\\.)*github\\.com[:/]"
    )
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
