import Foundation

/// One-time first-run adoption of existing launchers into the managed model (D26). Idempotent.
/// - karabiner: adds the `keymap:` prefix to the SpaceLauncher rule description.
/// - skhd: wraps the existing unmanaged launcher bindings in the managed fence.
/// NOTE: the original launcher lines stay in the prefix/suffix (byte-fidelity); the conflict engine
/// will surface the resulting duplicate chords, and Plan-B's UI will guide removing the originals.
public struct Migration {
    public let karabinerURL: URL
    public let skhdURL: URL
    public let writer: AtomicFileWriter

    public init(karabinerURL: URL, skhdURL: URL, writer: AtomicFileWriter) {
        self.karabinerURL = karabinerURL
        self.skhdURL = skhdURL
        self.writer = writer
    }

    public func run() throws {
        try migrateKarabiner()
        try migrateSkhd()
    }

    private func migrateKarabiner() throws {
        let text = try String(contentsOf: karabinerURL, encoding: .utf8)
        var doc = try KarabinerDocument(text: text)
        // Already migrated if all launcher bindings are managed.
        let bindings = doc.bindings()
        guard !bindings.isEmpty, bindings.contains(where: { !$0.managed }) else { return }
        doc.adoptSpaceLauncherRule()
        try writer.write(doc.serialized(), to: karabinerURL, backupStem: "karabiner")
    }

    private func migrateSkhd() throws {
        let text = try String(contentsOf: skhdURL, encoding: .utf8)
        var doc = try SkhdDocument(text: text)
        let allLaunchers = doc.bindings().filter { $0.launcher != nil }
        let managedLaunchers = allLaunchers.filter { $0.managed }
        let unmanagedLaunchers = allLaunchers.filter { !$0.managed }
        // Short-circuit if every unmanaged launcher chord already has a managed counterpart.
        let notYetFenced = unmanagedLaunchers.filter { u in
            !managedLaunchers.contains { $0.chord == u.chord }
        }
        guard !notYetFenced.isEmpty else { return }
        var adopted = unmanagedLaunchers
        for i in adopted.indices { adopted[i].managed = true }
        try doc.setManagedBindings(adopted)
        try writer.write(doc.serialized(), to: skhdURL, backupStem: "skhdrc")
    }
}
