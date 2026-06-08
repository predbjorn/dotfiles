import XCTest
@testable import Keymapper

// MARK: - Mock

struct MockDeployer: Deploying {
    var syncResult: Bool = true
    var applyError: Error? = nil
    func isInSync() throws -> Bool { syncResult }
    func apply() throws { if let e = applyError { throw e } }
}

// MARK: - Tests

@MainActor
final class KeymapperViewModelTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("kmvm-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Helpers

    private var karURL: URL  { dir.appendingPathComponent("karabiner.json") }
    private var skhdURL: URL { dir.appendingPathComponent("skhdrc") }
    private var backupDir: URL { dir.appendingPathComponent("backups") }

    /// Minimal karabiner.json with one SpaceLauncher binding. `managed` adds the keymap: prefix.
    private func writeKar(managed: Bool = false) throws {
        let prefix = managed ? "keymap: " : ""
        let text = """
        {
          "profiles": [{
            "name": "Default profile",
            "complex_modifications": {
              "rules": [{
                "description": "\(prefix)SpaceLauncher shortcuts",
                "manipulators": [{
                  "type": "basic",
                  "from": {"key_code": "b"},
                  "to": [{"shell_command": "$HOME/.dotfiles/bin/toggle_app.sh Safari"}]
                }]
              }]
            }
          }]
        }
        """
        try text.write(to: karURL, atomically: true, encoding: .utf8)
    }

    /// Minimal skhdrc with one binding. `managed` wraps it in the fence.
    private func writeSkhd(managed: Bool = false) throws {
        let text: String
        if managed {
            text = """
            # >>> keymap-managed >>>
            hyper - s : ~/.dotfiles/bin/focus_window_wrapper.sh Slack false
            # <<< keymap-managed <<<
            """
        } else {
            text = "hyper - s : ~/.dotfiles/bin/focus_window_wrapper.sh Slack false\n"
        }
        try text.write(to: skhdURL, atomically: true, encoding: .utf8)
    }

    private func makeVM(deployer: (any Deploying)? = nil) -> KeymapperViewModel {
        KeymapperViewModel(
            karabinerURL: karURL,
            skhdURL: skhdURL,
            deployer: deployer ?? MockDeployer(),
            writer: AtomicFileWriter(backupDir: backupDir)
        )
    }

    // MARK: Tests

    func testLoadPopulatesEditedManagedAndClearsDirty() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM()
        try vm.load()
        XCTAssertNotNil(vm.keymap)
        XCTAssertEqual(vm.editedManaged.count, 2)   // 1 karabiner + 1 skhd managed binding
        XCTAssertFalse(vm.isDirty)
        XCTAssertFalse(vm.needsMigration)
    }

    func testLoadSetsNeedsMigrationWhenUnmanaged() throws {
        try writeKar(managed: false)
        try writeSkhd(managed: false)
        let vm = makeVM()
        try vm.load()
        XCTAssertTrue(vm.needsMigration)
    }

    func testMigrateConvertsUnmanagedToManaged() throws {
        try writeKar(managed: false)
        try writeSkhd(managed: false)
        let vm = makeVM()
        try vm.load()
        XCTAssertTrue(vm.needsMigration)
        try vm.migrate()
        XCTAssertFalse(vm.needsMigration)
        XCTAssertFalse(vm.editedManaged.isEmpty)
        // Written skhdrc must contain the fence.
        let written = try String(contentsOf: skhdURL, encoding: .utf8)
        XCTAssertTrue(written.contains("# >>> keymap-managed >>>"))
    }

    func testAddBindingSetsDirtyAndAppendsToEditedManaged() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM()
        try vm.load()
        let before = vm.editedManaged.count
        vm.addBinding(Binding(
            chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "m"),
            source: .skhd, managed: true,
            launcher: LauncherAction(mechanism: .toggle, target: "Mail",
                                     focusBringToCurrent: false, rawCommand: ""),
            rawText: "", displayName: "Mail"
        ))
        XCTAssertTrue(vm.isDirty)
        XCTAssertEqual(vm.editedManaged.count, before + 1)
    }

    func testRemoveBindingSetsDirty() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM()
        try vm.load()
        let before = vm.editedManaged.count
        vm.removeBinding(at: IndexSet(integer: 0))
        XCTAssertTrue(vm.isDirty)
        XCTAssertEqual(vm.editedManaged.count, before - 1)
    }

    func testSaveClearsDirtyAndWritesNewBinding() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM(deployer: MockDeployer())
        try vm.load()
        vm.addBinding(Binding(
            chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "p"),
            source: .skhd, managed: true,
            launcher: LauncherAction(mechanism: .toggle, target: "Spotify",
                                     focusBringToCurrent: false, rawCommand: ""),
            rawText: "", displayName: "Spotify"
        ))
        try vm.save()
        XCTAssertFalse(vm.isDirty)
        XCTAssertTrue(vm.skhdInSync)   // deployer.apply() succeeded; skhdInSync reset to true
        let written = try String(contentsOf: skhdURL, encoding: .utf8)
        XCTAssertTrue(written.contains("toggle_app.sh Spotify"))
    }

    func testSaveThrowsConcurrentEditWhenFileChangedExternally() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM()
        try vm.load()
        vm.addBinding(Binding(
            chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "q"),
            source: .skhd, managed: true,
            launcher: LauncherAction(mechanism: .toggle, target: "Test",
                                     focusBringToCurrent: false, rawCommand: ""),
            rawText: "", displayName: "Test"
        ))
        // External modification — simulates Karabiner GUI or another process writing the file.
        try "# externally modified\n".write(to: skhdURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try vm.save()) { error in
            XCTAssertEqual(error as? SaveError, .concurrentEdit)
        }
    }

    func testMakeItLiveCallsDeployAndSetsSyncTrue() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM(deployer: MockDeployer(syncResult: false))
        try vm.load()
        XCTAssertFalse(vm.skhdInSync)
        try vm.makeItLive()
        XCTAssertTrue(vm.skhdInSync)
    }
}
