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

    func testCombinesSurrogatePairEscapes() throws {
        let value = try JSONValue.parse(#"{"k":"😀"}"#)
        XCTAssertEqual(value["k"]?.stringValue, "😀")
    }

    func testBMPUnicodeEscapeStillWorks() throws {
        let value = try JSONValue.parse(#"{"k":"é"}"#)
        XCTAssertEqual(value["k"]?.stringValue, "é")
    }

    func testCombinesSurrogatePairEscapeSequence() throws {
        // Actual JSON \u escape for U+1F600 (😀) as a UTF-16 surrogate pair.
        let bs = "\u{5C}" // backslash
        let json = "{\"k\":\"\(bs)ud83d\(bs)ude00\"}"
        let value = try JSONValue.parse(json)
        XCTAssertEqual(value["k"]?.stringValue, "😀")
    }

    func testBMPUnicodeEscapeSequenceDecodes() throws {
        // Actual JSON \u escape for U+00E9 (é).
        let bs = "\u{5C}" // backslash
        let json = "{\"k\":\"\(bs)u00e9\"}"
        let value = try JSONValue.parse(json)
        XCTAssertEqual(value["k"]?.stringValue, "é")
    }
}
