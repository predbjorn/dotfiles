import XCTest
@testable import Keymapper

final class ShellQuoteTests: XCTestCase {
    func testPlainWordIsUnquotedWhenSafe() {
        XCTAssertEqual(ShellQuote.quote("Safari"), "Safari")
        XCTAssertEqual(ShellQuote.quote("Google_Chrome-1.2"), "Google_Chrome-1.2")
    }

    func testSpacesAreSingleQuoted() {
        XCTAssertEqual(ShellQuote.quote("Google Chrome"), "'Google Chrome'")
    }

    func testShellMetacharactersAreNeutralized() {
        XCTAssertEqual(ShellQuote.quote("evil; rm -rf ~"), "'evil; rm -rf ~'")
        XCTAssertEqual(ShellQuote.quote("a$(whoami)b"), "'a$(whoami)b'")
        XCTAssertEqual(ShellQuote.quote("a`id`b"), "'a`id`b'")
    }

    func testEmbeddedSingleQuoteIsEscaped() {
        XCTAssertEqual(ShellQuote.quote("it's"), "'it'\\''s'")
    }

    func testLoneSingleQuote() {
        XCTAssertEqual(ShellQuote.quote("'"), "''\\'''")
    }

    func testEmptyStringBecomesEmptyQuotedArg() {
        XCTAssertEqual(ShellQuote.quote(""), "''")
    }

    func testLeadingDashReturnedBarePerFixedSlotContract() {
        XCTAssertEqual(ShellQuote.quote("-rf"), "-rf")
    }
}
