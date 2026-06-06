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
        XCTAssertEqual(hex.key, "0x2f")
        XCTAssertEqual(hex.canonical, "skhd-modifier:ctrl+shift-0x2f")
    }

    func testDifferentLayersNeverEqualEvenWithSameKey() {
        let leader = Chord(layer: .spaceLeader, modifiers: [], key: "b")
        let modifier = Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "b")
        XCTAssertNotEqual(leader, modifier)
        XCTAssertNotEqual(leader.canonical, modifier.canonical)
    }
}
