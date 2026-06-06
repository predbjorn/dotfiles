import XCTest
@testable import Keymapper

final class JSONValueTests: XCTestCase {
    func testPreservesObjectKeyOrder() throws {
        let json = #"{"z":1,"a":2,"m":{"y":true,"b":false}}"#
        let value = try JSONValue.parse(json)
        XCTAssertEqual(value.serialized(indent: nil), #"{"z":1,"a":2,"m":{"y":true,"b":false}}"#)
    }

    func testPreservesUnknownNestedKeysThroughMutation() throws {
        let json = #"{"rules":[{"description":"x","future_field":[1,2,3]}]}"#
        let value = try JSONValue.parse(json)
        XCTAssertEqual(value.serialized(indent: nil), json)
    }

    func testPrettyPrintsWithTwoSpaceIndent() throws {
        let value = try JSONValue.parse(#"{"a":[1,2]}"#)
        XCTAssertEqual(value.serialized(indent: 2), "{\n  \"a\": [\n    1,\n    2\n  ]\n}")
    }

    func testObjectSubscriptAndArrayAccess() throws {
        let value = try JSONValue.parse(#"{"rules":[{"description":"keymap: x"}]}"#)
        guard case .array(let rules)? = value["rules"] else { return XCTFail("rules not array") }
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0]["description"]?.stringValue, "keymap: x")
    }
}
