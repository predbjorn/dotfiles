import Foundation

/// One-time first-run adoption of existing launchers into the managed model (D26). Idempotent.
/// - karabiner: adds the `keymap:` prefix to the SpaceLauncher rule description.
/// - skhd: wraps the existing unmanaged launcher bindings in the managed fence.
/// NOTE: the original launcher lines stay in the prefix/suffix (byte-fidelity); the conflict engine
/// will surface the resulting duplicate chords, and Plan-B's UI will guide removing the originals.
struct Migration {
    let karabinerURL: URL
    let skhdURL: URL
    let writer: AtomicFileWriter

    func run() throws {
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
        let unmanagedLaunchers = doc.bindings().filter { !$0.managed && $0.launcher != nil }
        guard !unmanagedLaunchers.isEmpty else { return } // nothing to adopt / already fenced
        var adopted = unmanagedLaunchers
        for i in adopted.indices { adopted[i].managed = true }
        try doc.setManagedBindings(adopted)
        try writer.write(doc.serialized(), to: skhdURL, backupStem: "skhdrc")
    }
}
