import XCTest
@testable import Keymapper

final class CheatsheetTests: XCTestCase {
    private func b(_ layer: Layer, _ mods: [String], _ key: String, app: String,
                   managed: Bool = true) -> Binding {
        Binding(chord: Chord(layer: layer, modifiers: mods, key: key),
                source: .skhd, managed: managed,
                launcher: LauncherAction(mechanism: .toggle, target: app,
                                         focusBringToCurrent: false, rawCommand: ""),
                rawText: "", displayName: app)
    }

    func testMarkdownGroupsByLayerAndListsBindings() {
        let md = Cheatsheet.markdown(bindings: [
            b(.spaceLeader, [], "b", app: "Safari"),
            b(.skhdModifier, ["hyper"], "s", app: "Slack"),
        ], conflicts: [])
        XCTAssertTrue(md.contains("## space-leader"))
        XCTAssertTrue(md.contains("## skhd-modifier"))
        XCTAssertTrue(md.contains("Safari"))
        XCTAssertTrue(md.contains("Slack"))
    }

    func testMarkdownIncludesConflictsSectionWhenPresent() {
        let dup = b(.skhdModifier, ["hyper"], "b", app: "Safari")
        let conflicts = ConflictEngine.find([dup, dup])
        let md = Cheatsheet.markdown(bindings: [dup, dup], conflicts: conflicts)
        XCTAssertTrue(md.contains("## Conflicts"))
        // The chord must appear somewhere in the conflicts section.
        XCTAssertTrue(md.contains("b"))
    }

    func testNoConflictsSectionWhenNone() {
        let md = Cheatsheet.markdown(
            bindings: [b(.spaceLeader, [], "b", app: "Safari")],
            conflicts: [])
        XCTAssertFalse(md.contains("## Conflicts"))
    }

    func testReferenceBindingsAreTagged() {
        let md = Cheatsheet.markdown(bindings: [
            b(.spaceLeader, [], "b", app: "Safari", managed: false),
        ], conflicts: [])
        XCTAssertTrue(md.contains("_(reference)_"))
    }
}
