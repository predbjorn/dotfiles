import Foundation

/// The merged, in-memory view of both config files. Pure value type; I/O is done by callers.
struct Keymap {
    var karabiner: KarabinerDocument
    var skhd: SkhdDocument

    init(karabinerText: String, skhdText: String) throws {
        karabiner = try KarabinerDocument(text: karabinerText)
        skhd = try SkhdDocument(text: skhdText)
    }

    var bindings: [Binding] { karabiner.bindings() + skhd.bindings() }
    var managed: [Binding] { bindings.filter { $0.managed } }
    var reference: [Binding] { bindings.filter { !$0.managed } }
    var conflicts: [Conflict] { ConflictEngine.find(bindings) }

    /// True iff the launchers have not yet been adopted (no managed bindings but reference bindings exist).
    var needsMigration: Bool { managed.isEmpty && !reference.isEmpty }
}
