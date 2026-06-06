import XCTest
@testable import Keymapper

final class MigrationTests: XCTestCase {
    // Minimal karabiner text: unmanaged SpaceLauncher rule with one app launcher.
    private let karabinerText = #"""
    {"profiles":[{"name":"Default","complex_modifications":{"rules":[{"description":"SpaceLauncher shortcuts","manipulators":[{"conditions":[{"type":"variable_if","name":"space_held","value":1}],"from":{"key_code":"b"},"to":[{"shell_command":"$HOME/.dotfiles/bin/toggle_app.sh Safari"}]}]}]}}]}
    """#

    // Minimal skhd text: NO fence — one unmanaged launcher line.
    private let skhdText = "hyper - s : ~/.dotfiles/bin/focus_window_wrapper.sh Slack false\n"

    private var dir: URL!
    private var karabinerURL: URL!
    private var skhdURL: URL!
    private var backups: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("km-mig-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        karabinerURL = dir.appendingPathComponent("karabiner.json")
        skhdURL = dir.appendingPathComponent("skhdrc")
        backups = dir.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try karabinerText.write(to: karabinerURL, atomically: true, encoding: .utf8)
        try skhdText.write(to: skhdURL, atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testNeedsMigrationBeforeRun() throws {
        let km = try Keymap(karabinerText: karabinerText, skhdText: skhdText)
        XCTAssertTrue(km.needsMigration)
    }

    func testMigrationAdoptsLaunchersAndIsIdempotent() throws {
        let writer = AtomicFileWriter(backupDir: backups)
        let migration = Migration(karabinerURL: karabinerURL, skhdURL: skhdURL, writer: writer)

        try migration.run()

        let km = try Keymap(
            karabinerText: try String(contentsOf: karabinerURL, encoding: .utf8),
            skhdText: try String(contentsOf: skhdURL, encoding: .utf8)
        )
        XCTAssertFalse(km.needsMigration)
        XCTAssertFalse(km.managed.isEmpty)

        // Idempotent: second run must not double-prefix or double-fence.
        try migration.run()
        let km2 = try Keymap(
            karabinerText: try String(contentsOf: karabinerURL, encoding: .utf8),
            skhdText: try String(contentsOf: skhdURL, encoding: .utf8)
        )
        XCTAssertFalse(km2.needsMigration)
        let skhdOut = try String(contentsOf: skhdURL, encoding: .utf8)
        XCTAssertEqual(skhdOut.components(separatedBy: "# >>> keymap-managed >>>").count - 1, 1, "fence must appear exactly once")
        let karabinerOut = try String(contentsOf: karabinerURL, encoding: .utf8)
        XCTAssertEqual(karabinerOut.components(separatedBy: "keymap: ").count - 1, 1, "prefix must appear exactly once")
    }

    func testMigrationWritesBackups() throws {
        let writer = AtomicFileWriter(backupDir: backups)
        let migration = Migration(karabinerURL: karabinerURL, skhdURL: skhdURL, writer: writer)
        try migration.run()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
        XCTAssertTrue(files.contains { $0.hasPrefix("karabiner.") && $0.hasSuffix(".bak") })
        XCTAssertTrue(files.contains { $0.hasPrefix("skhdrc.") && $0.hasSuffix(".bak") })
    }
}
