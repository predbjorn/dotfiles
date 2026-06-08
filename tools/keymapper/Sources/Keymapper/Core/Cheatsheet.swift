import Foundation

public enum Cheatsheet {
    public static func markdown(bindings: [Binding], conflicts: [Conflict]) -> String {
        var out = "# Keymap Cheatsheet\n"
        for layer in Layer.allCases {
            let inLayer = bindings
                .filter { $0.chord.layer == layer }
                .sorted { $0.chord.canonical < $1.chord.canonical }
            guard !inLayer.isEmpty else { continue }
            out += "\n## \(layer.rawValue)\n\n"
            for b in inLayer {
                let tag = b.managed ? "" : " _(reference)_"
                out += "- `\(chordLabel(b.chord))` → \(b.displayName)\(tag)\n"
            }
        }
        if !conflicts.isEmpty {
            out += "\n## Conflicts\n\n"
            for c in conflicts {
                let names = c.bindings.map { $0.displayName }.joined(separator: ", ")
                out += "- `\(chordLabel(c.chord))`: \(names)\n"
            }
        }
        return out
    }

    private static func chordLabel(_ chord: Chord) -> String {
        switch chord.layer {
        case .spaceLeader:        return "space \(chord.key)"
        case .spaceFLeader:       return "space f \(chord.key)"
        case .karabinerModifier,
             .skhdModifier:       return SkhdChord.render(chord)
        }
    }
}
