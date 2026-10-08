import XCTest
@testable import Keymapper

final class ChordTests: XCTestCase {
    func testSkhdModifierChordCanonicalizesModifierOrder() {
        let a = Chord(layer: .skhdModifier, modifiers: ["shift", "ctrl"], key: "b")
        let b = Chord(layer: .skhdModifier, modifiers: ["ctrl", "shift"], key: "b")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.canonical, "skhd-modifier:ctrl+shift-b")
    }

    func testHyperIsNormalizedToItsModifierSet() {
        let hyper = Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "b")
        let expanded = Chord(layer: .skhdModifier, modifiers: ["cmd", "ctrl", "alt", "shift"], key: "b")
        XCTAssertEqual(hyper, expanded)
    }

    func testKeycodeAliasNormalization() {
        let hex = Chord(layer: .skhdModifier, modifiers: ["ctrl", "shift"], key: "0x2f")
        XCTAssertEqual(hex.key, "0x2F")
        XCTAssertEqual(hex.canonical, "skhd-modifier:ctrl+shift-0x2F")
    }

    func testHexKeycodeCaseVariantsAreEqual() {
        let upper = Chord(layer: .skhdModifier, modifiers: ["ctrl", "shift"], key: "0x2F")
        let lower = Chord(layer: .skhdModifier, modifiers: ["ctrl", "shift"], key: "0X2f")
        XCTAssertEqual(upper, lower)
        XCTAssertEqual(Set([upper, lower]).count, 1)
    }

    func testNamedKeysStayLowercase() {
        XCTAssertEqual(Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "B").key, "b")
        XCTAssertEqual(Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "Return").key, "return")
    }

    func testSkhdHexKeycodeRoundTripsWithUppercaseDigits() {
        let parsed = SkhdChord.parse("ctrl + shift - 0x2F")
        XCTAssertEqual(parsed?.key, "0x2F")
        XCTAssertEqual(parsed.map(SkhdChord.render), "ctrl + shift - 0x2F")
        // Lowercase input (e.g. typed in the editor) is normalised on the way out.
        XCTAssertEqual(SkhdChord.parse("ctrl + shift - 0x2f").map(SkhdChord.render), "ctrl + shift - 0x2F")
        XCTAssertEqual(SkhdChord.parse("ctrl + shift - 0x2f"), parsed)
    }

    func testDifferentLayersNeverEqualEvenWithSameKey() {
        let leader = Chord(layer: .spaceLeader, modifiers: [], key: "b")
        let modifier = Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "b")
        XCTAssertNotEqual(leader, modifier)
        XCTAssertNotEqual(leader.canonical, modifier.canonical)
    }
}
