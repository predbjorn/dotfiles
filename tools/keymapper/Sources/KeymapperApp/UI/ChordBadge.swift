import SwiftUI
import Keymapper

/// Renders a chord as individual keycap-style button tokens.
/// Modifier symbols are grouped into one token; the key is a second token.
/// Space-leader chords show [space] or [space][f] prefix tokens.
///
///   hyper - b        →  [⌘⌃⌥⇧] [b]
///   ctrl + shift - b →  [⌃⇧] [b]
///   space b          →  [space] [b]
///   space f c        →  [space] [f] [c]
struct ChordBadge: View {
    let chord: Chord
    /// Tint colour — use `.accentColor` for managed rows, `Color(.secondaryLabelColor)` for reference.
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                KeyCapToken(label: token, tint: tint)
            }
        }
    }

    // MARK: Token decomposition

    private var tokens: [String] {
        switch chord.layer {
        case .spaceLeader:
            return ["space", chord.key]
        case .spaceFLeader:
            return ["space", "f", chord.key]
        case .skhdModifier, .karabinerModifier:
            let modStr = chord.modifiers.compactMap { modSymbol($0) }.joined()
            return modStr.isEmpty ? [chord.key] : [modStr, chord.key]
        }
    }

    private func modSymbol(_ mod: String) -> String? {
        switch mod {
        case "cmd":   return "⌘"
        case "ctrl":  return "⌃"
        case "alt":   return "⌥"
        case "shift": return "⇧"
        default:      return mod.isEmpty ? nil : mod
        }
    }
}

// MARK: - KeyCapToken

private struct KeyCapToken: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .monospaced, weight: .medium))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
