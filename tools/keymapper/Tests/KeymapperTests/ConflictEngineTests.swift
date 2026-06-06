import XCTest
@testable import Keymapper

final class ConflictEngineTests: XCTestCase {
    private func b(_ layer: Layer, _ mods: [String], _ key: String, app: String, managed: Bool = true) -> Binding {
        Binding(chord: Chord(layer: layer, modifiers: mods, key: key), source: .skhd, managed: managed,
                launcher: LauncherAction(mechanism: .toggle, target: app, focusBringToCurrent: false, rawCommand: ""),
                rawText: "", displayName: app)
    }

    func testSameChordSameLayerIsConflict() {
        let conflicts = ConflictEngine.find([
            b(.skhdModifier, ["hyper"], "b", app: "Safari"),
            b(.skhdModifier, ["cmd", "ctrl", "alt", "shift"], "b", app: "Slack"), // == hyper
        ])
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].chord.key, "b")
        XCTAssertEqual(conflicts[0].bindings.count, 2)
    }

    func testSameKeyDifferentLayerIsNotConflict() {
        let conflicts = ConflictEngine.find([
            b(.spaceLeader, [], "b", app: "Safari"),
            b(.skhdModifier, ["hyper"], "b", app: "Slack"),
        ])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func testConflictDetectedEvenWhenOneSideIsReadOnly() {
        let conflicts = ConflictEngine.find([
            b(.skhdModifier, ["hyper"], "b", app: "Safari", managed: true),
            b(.skhdModifier, ["hyper"], "b", app: "Other", managed: false),
        ])
        XCTAssertEqual(conflicts.count, 1)
    }

    func testNoConflictWhenAllDistinct() {
        let conflicts = ConflictEngine.find([
            b(.skhdModifier, ["hyper"], "b", app: "Safari"),
            b(.skhdModifier, ["hyper"], "s", app: "Slack"),
        ])
        XCTAssertTrue(conflicts.isEmpty)
    }
}
