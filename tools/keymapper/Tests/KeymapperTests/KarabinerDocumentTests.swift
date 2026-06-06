import XCTest
@testable import Keymapper

final class KarabinerDocumentTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testExtractsLauncherBindingsFromSpaceLauncherRule() throws {
        let doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        let bindings = doc.bindings()
        let b = bindings.first { $0.chord.key == "b" }!
        XCTAssertEqual(b.chord.layer, .spaceLeader)
        XCTAssertEqual(b.launcher?.mechanism, .toggle)
        XCTAssertEqual(b.launcher?.target, "Safari")
        let d = bindings.first { $0.chord.key == "d" }!
        XCTAssertEqual(d.chord.layer, .spaceFLeader)
        XCTAssertEqual(d.launcher?.mechanism, .open)
        XCTAssertEqual(d.launcher?.target, "~/Downloads")
    }

    func testUnmanagedUntilDescriptionHasPrefix() throws {
        let doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        XCTAssertTrue(doc.bindings().allSatisfy { !$0.managed })
    }

    func testAdoptRenamesRuleWithKeymapPrefixAndPreservesOtherJSON() throws {
        var doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        doc.adoptSpaceLauncherRule()
        let out = doc.serialized()
        XCTAssertTrue(out.contains("\"keymap: SpaceLauncher shortcuts\""))
        XCTAssertTrue(out.contains("\"future_field\""))
        XCTAssertTrue(out.contains("\"keep\""))
        let doc2 = try KarabinerDocument(text: out)
        XCTAssertTrue(doc2.bindings().allSatisfy { $0.managed })
    }

    func testSetLauncherTargetRewritesOnlyThatShellCommand() throws {
        var doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        doc.adoptSpaceLauncherRule()
        try doc.setLauncherTarget(layer: .spaceLeader, key: "b",
                                  action: LauncherAction(mechanism: .toggle, target: "Slack",
                                                         focusBringToCurrent: false, rawCommand: ""))
        let out = doc.serialized()
        XCTAssertTrue(out.contains("$HOME/.dotfiles/bin/toggle_app.sh Slack"))
        XCTAssertFalse(out.contains("toggle_app.sh Safari"))
        XCTAssertTrue(out.contains("open ~/Downloads"))
    }

    func testSerializeUsesTwoSpaceIndent() throws {
        let doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        XCTAssertTrue(doc.serialized().contains("\n  \"profiles\""))
    }
}
