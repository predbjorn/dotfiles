import Foundation
import Combine

/// The observable model for the Keymapper UI. Loads both config files, tracks in-flight edits,
/// and saves atomically (D27). Lives in the library target so it is testable without SwiftUI.
@MainActor
final class KeymapperViewModel: ObservableObject {
    @Published private(set) var keymap: Keymap?
    @Published private(set) var editedManaged: [Binding] = []   // working copy for pending edits
    @Published private(set) var isDirty: Bool = false
    @Published private(set) var skhdInSync: Bool = true
    @Published var loadError: String?    // set by loadReportingError(); cleared by view
    @Published var saveError: String?    // set by saveReportingError(); cleared by view
    @Published private(set) var needsMigration: Bool = false

    /// Hashes of each file as read at load time; used to detect concurrent external edits (D10).
    private var karabinerHash: Int = 0
    private var skhdHash: Int = 0

    let karabinerURL: URL
    let skhdURL: URL
    let deployer: any Deploying
    let writer: AtomicFileWriter

    init(
        karabinerURL: URL = Paths.karabinerRepo,
        skhdURL: URL = Paths.skhdRepo,
        deployer: any Deploying = Deployer.makeReal(),
        writer: AtomicFileWriter = AtomicFileWriter(backupDir: Paths.backupDir)
    ) {
        self.karabinerURL = karabinerURL
        self.skhdURL = skhdURL
        self.deployer = deployer
        self.writer = writer
    }

    // MARK: Load

    /// Load (or re-load) both config files. Resets all edit state.
    func load() throws {
        let karText = try String(contentsOf: karabinerURL, encoding: .utf8)
        let skhdText = try String(contentsOf: skhdURL, encoding: .utf8)
        karabinerHash = karText.hashValue
        skhdHash = skhdText.hashValue
        let km = try Keymap(karabinerText: karText, skhdText: skhdText)
        keymap = km
        editedManaged = km.managed
        isDirty = false
        needsMigration = km.needsMigration
        skhdInSync = (try? deployer.isInSync()) ?? true
    }

    /// Convenience wrapper used by AppDelegate so the caller doesn't need a try/catch.
    func loadReportingError() {
        do { try load() } catch { loadError = error.localizedDescription }
    }

    // MARK: Edit

    func updateBinding(_ binding: Binding) {
        guard let idx = editedManaged.firstIndex(where: {
            $0.chord == binding.chord && $0.source == binding.source
        }) else { return }
        editedManaged[idx] = binding
        isDirty = true
    }

    func addBinding(_ binding: Binding) {
        editedManaged.append(binding)
        isDirty = true
    }

    func removeBinding(at offsets: IndexSet) {
        // remove(atOffsets:) is SwiftUI-only; replicate it without importing SwiftUI.
        for index in offsets.reversed() {
            editedManaged.remove(at: index)
        }
        isDirty = true
    }

    // MARK: Save (D27 — one atomic write + deploy)

    /// Atomic save: re-read to detect concurrent edits (D10), write both files (D17, D21),
    /// validate (D25), then deploy skhd (D12). Throws on any failure; backups are preserved.
    func save() throws {
        guard var km = keymap else { return }

        // D10: re-read immediately before writing to detect concurrent external edits.
        let freshKar = try String(contentsOf: karabinerURL, encoding: .utf8)
        let freshSkhd = try String(contentsOf: skhdURL, encoding: .utf8)
        guard freshKar.hashValue == karabinerHash,
              freshSkhd.hashValue == skhdHash else {
            try load()   // reload before throwing so UI shows the current state
            throw SaveError.concurrentEdit
        }

        // Re-parse from the freshly-read text (avoids writing a stale base, D10).
        km = try Keymap(karabinerText: freshKar, skhdText: freshSkhd)

        // Apply karabiner edits: update each managed space-leader launcher's shell_command.
        for b in editedManaged where b.source == .karabiner {
            guard let action = b.launcher else { continue }
            try km.karabiner.setLauncherTarget(layer: b.chord.layer, key: b.chord.key, action: action)
        }

        // Apply skhd edits: regenerate the entire managed region (D8 verbatim passthrough outside).
        let skhdBindings = editedManaged.filter { $0.source == .skhd }
        try km.skhd.setManagedBindings(skhdBindings)

        // Serialize.
        let karText = km.karabiner.serialized()
        let skhdText = km.skhd.serialized()

        // Atomic write with backup (D17, D21). Backup is taken BEFORE each write.
        try writer.write(karText, to: karabinerURL, backupStem: "karabiner")
        try writer.write(skhdText, to: skhdURL, backupStem: "skhdrc")

        // D25: post-write semantic validation — re-parse and verify managed count.
        let writtenKar = try String(contentsOf: karabinerURL, encoding: .utf8)
        let writtenSkhd = try String(contentsOf: skhdURL, encoding: .utf8)
        let validated = try Keymap(karabinerText: writtenKar, skhdText: writtenSkhd)
        guard validated.managed.count == editedManaged.count else {
            // Backups are already on disk; caller surfaces the error so the user can restore manually.
            throw SaveError.validationFailed
        }

        // Deploy skhd (D12): copy repo skhdrc → deployed path, then skhd --reload.
        try deployer.apply()

        // Update in-memory state.
        keymap = validated
        editedManaged = validated.managed
        isDirty = false
        skhdInSync = true
        karabinerHash = writtenKar.hashValue
        skhdHash = writtenSkhd.hashValue
    }

    /// Convenience wrapper for the Save button action in SwiftUI.
    func saveReportingError() {
        do { try save() } catch { saveError = error.localizedDescription }
    }

    // MARK: Migration (D26)

    /// First-run: auto-adopt all existing launcher bindings into the managed model.
    func migrate() throws {
        let m = Migration(karabinerURL: karabinerURL, skhdURL: skhdURL, writer: writer)
        try m.run()
        try load()
    }

    // MARK: Drift (D13, D28)

    /// "Make it live" — re-deploy repo skhdrc when it diverged from the deployed copy.
    func makeItLive() throws {
        try deployer.apply()
        skhdInSync = true
    }
}

// MARK: - Errors

enum SaveError: Error, LocalizedError, Equatable {
    case concurrentEdit
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .concurrentEdit:
            return "The config file was modified externally — reloaded the latest version. Please review and save again."
        case .validationFailed:
            return "Write validation failed. Your backup was preserved in ~/Library/Application Support/Keymapper/backups/."
        }
    }
}
