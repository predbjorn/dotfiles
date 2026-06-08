import Foundation

/// The merged, in-memory view of both config files. Pure value type; I/O is done by callers.
public struct Keymap {
    public var karabiner: KarabinerDocument
    public var skhd: SkhdDocument

    public init(karabinerText: String, skhdText: String) throws {
        karabiner = try KarabinerDocument(text: karabinerText)
        skhd = try SkhdDocument(text: skhdText)
    }

    public var bindings: [Binding] { karabiner.bindings() + skhd.bindings() }
    public var managed: [Binding] { bindings.filter { $0.managed } }
    public var reference: [Binding] { bindings.filter { !$0.managed } }
    public var conflicts: [Conflict] { ConflictEngine.find(bindings) }

    /// True iff the launchers have not yet been adopted (no managed bindings but reference bindings exist).
    public var needsMigration: Bool { managed.isEmpty && !reference.isEmpty }
}
