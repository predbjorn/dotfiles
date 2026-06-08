import Foundation

public enum Layer: String, Codable, CaseIterable {
    case spaceLeader = "space-leader"
    case spaceFLeader = "space-f-leader"
    case karabinerModifier = "karabiner-modifier"
    case skhdModifier = "skhd-modifier"
}

/// A normalized chord. Equality is by `canonical`, which folds modifier order and the `hyper` alias.
public struct Chord: Equatable, Hashable {
    public let layer: Layer
    public let modifiers: [String]   // normalized, deduped, sorted (lowercased)
    public let key: String           // verbatim key token (letter or hex keycode), lowercased for comparison

    private static let order = ["cmd", "ctrl", "alt", "shift"]
    private static let hyperSet = ["cmd", "ctrl", "alt", "shift"]

    public init(layer: Layer, modifiers: [String], key: String) {
        self.layer = layer
        self.key = key.lowercased()
        var mods = Set(modifiers.map { $0.lowercased() })
        if mods.contains("hyper") { mods.remove("hyper"); Chord.hyperSet.forEach { mods.insert($0) } }
        self.modifiers = Chord.order.filter { mods.contains($0) }
    }

    public var canonical: String {
        let mod = modifiers.isEmpty ? "" : modifiers.joined(separator: "+") + "-"
        return "\(layer.rawValue):\(mod)\(key)"
    }

    public static func == (l: Chord, r: Chord) -> Bool { l.canonical == r.canonical }
    public func hash(into hasher: inout Hasher) { hasher.combine(canonical) }
}
