import XCTest
@testable import Keymapper

final class SkhdDocumentTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testUnchangedDocumentSerializesByteForByte() throws {
        let text = try fixture("skhdrc-sample")
        let doc = try SkhdDocument(text: text)
        XCTAssertEqual(doc.serialized(), text)
    }

    func testManagedBindingsComeFromFencedRegion() throws {
        let doc = try SkhdDocument(text: fixture("skhdrc-sample"))
        let managed = doc.bindings().filter { $0.managed }
        XCTAssertEqual(managed.count, 1)
        XCTAssertEqual(managed[0].chord.modifiers, ["cmd", "ctrl", "alt", "shift"]) // hyper expands
        XCTAssertEqual(managed[0].launcher?.target, "Slack")
    }

    func testReadOnlyLauncherLinesAreParsedAsUnmanagedBindings() throws {
        let doc = try SkhdDocument(text: fixture("skhdrc-sample"))
        let chrome = doc.bindings().first { $0.launcher?.target == "Google Chrome" }!
        XCTAssertFalse(chrome.managed)
        XCTAssertEqual(chrome.chord.layer, .skhdModifier)
    }

    func testMultiLineYabaiPipelineParsedAsOpaqueChordOnly() throws {
        let doc = try SkhdDocument(text: fixture("skhdrc-sample"))
        let opaque = doc.bindings().first { $0.chord.key == "n" }!
        XCTAssertNil(opaque.launcher)
        XCTAssertEqual(opaque.chord.layer, .skhdModifier)
    }

    func testSetManagedBindingRewritesOnlyTheFencedRegion() throws {
        var doc = try SkhdDocument(text: fixture("skhdrc-sample"))
        try doc.setManagedBindings([
            Binding(chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "m"),
                    source: .skhd, managed: true,
                    launcher: LauncherAction(mechanism: .focus, target: "Mail",
                                             focusBringToCurrent: false, rawCommand: ""),
                    rawText: "", displayName: "Mail")
        ])
        let out = doc.serialized()
        XCTAssertTrue(out.contains("$HOME/.dotfiles/bin/focus_window_wrapper.sh Mail false"))
        XCTAssertFalse(out.contains("focus_window_wrapper.sh Slack"))
        // Everything OUTSIDE the fence is preserved (the yabai pipeline survives verbatim).
        XCTAssertTrue(out.contains(#"jq 'map(select(."is-native-fullscreen" == false))[-1].index')"#))
    }

    func testCreatesFenceWhenAbsent() throws {
        var doc = try SkhdDocument(text: "hyper - b : echo hi\n")
        try doc.setManagedBindings([
            Binding(chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "p"),
                    source: .skhd, managed: true,
                    launcher: LauncherAction(mechanism: .toggle, target: "Spotify",
                                             focusBringToCurrent: false, rawCommand: ""),
                    rawText: "", displayName: "Spotify")
        ])
        let out = doc.serialized()
        XCTAssertTrue(out.contains("# >>> keymap-managed >>>"))
        XCTAssertTrue(out.contains("# <<< keymap-managed <<<"))
        XCTAssertTrue(out.contains("$HOME/.dotfiles/bin/toggle_app.sh Spotify"))
    }
}
