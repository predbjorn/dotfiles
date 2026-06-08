import Foundation

public struct Conflict: Equatable {
    public let chord: Chord
    public let bindings: [Binding]
}

public enum ConflictEngine {
    /// Group all bindings by canonical chord; any group with >1 binding is a within-layer conflict.
    /// (Canonical already encodes the layer, so cross-layer keys never group together — D14.)
    public static func find(_ bindings: [Binding]) -> [Conflict] {
        var groups: [String: (chord: Chord, items: [Binding])] = [:]
        for b in bindings {
            groups[b.chord.canonical, default: (b.chord, [])].items.append(b)
        }
        return groups.values
            .filter { $0.items.count > 1 }
            .map { Conflict(chord: $0.chord, bindings: $0.items) }
            .sorted { $0.chord.canonical < $1.chord.canonical }
    }
}
