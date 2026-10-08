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
    public let key: String           // key token: named keys lowercased; hex keycodes as `0x` + uppercase digits (skhd rejects lowercase hex)

    private static let order = ["cmd", "ctrl", "alt", "shift"]
    private static let hyperSet = ["cmd", "ctrl", "alt", "shift"]

    public init(layer: Layer, modifiers: [String], key: String) {
        self.layer = layer
        self.key = Chord.normalizeKey(key)
        var mods = Set(modifiers.map { $0.lowercased() })
        if mods.contains("hyper") { mods.remove("hyper"); Chord.hyperSet.forEach { mods.insert($0) } }
        self.modifiers = Chord.order.filter { mods.contains($0) }
    }

    /// skhd only parses hex keycodes with uppercase digits (`0x2F`), so normalise those; everything else is lowercased.
    static func normalizeKey(_ key: String) -> String {
        let lower = key.lowercased()
        guard lower.hasPrefix("0x"), lower.count > 2 else { return lower }
        return "0x" + lower.dropFirst(2).uppercased()
    }

    public var canonical: String {
        let mod = modifiers.isEmpty ? "" : modifiers.joined(separator: "+") + "-"
        return "\(layer.rawValue):\(mod)\(key)"
    }

    public static func == (l: Chord, r: Chord) -> Bool { l.canonical == r.canonical }
    public func hash(into hasher: inout Hasher) { hasher.combine(canonical) }
}
