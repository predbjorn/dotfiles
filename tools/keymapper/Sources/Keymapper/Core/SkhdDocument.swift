import Foundation

/// Splits skhdrc into [prefix lines] [managed region] [suffix lines]. The managed region is regenerated
/// on edit; everything else passes through verbatim (D8). All binding lines (managed or not) are parsed
/// at chord level for the auditor (D29). Line numbers (1-based) are stored on each Binding for D29
/// open-at-line support.
public struct SkhdDocument {
    public static let openFence = "# >>> keymap-managed >>>"
    public static let closeFence = "# <<< keymap-managed <<<"

    private var prefix: [String]
    private var managedLines: [String]
    private var suffix: [String]
    private var hasFence: Bool

    public init(text: String) throws {
        let lines = text.components(separatedBy: "\n")
        if let open = lines.firstIndex(of: Self.openFence),
           let close = lines[open...].firstIndex(of: Self.closeFence) {
            prefix = Array(lines[..<open])
            managedLines = Array(lines[(open + 1)..<close])
            suffix = Array(lines[(close + 1)...])
            hasFence = true
        } else {
            prefix = lines
            managedLines = []
            suffix = []
            hasFence = false
        }
    }

    public func serialized() -> String {
        if !hasFence && managedLines.isEmpty {
            return prefix.joined(separator: "\n")
        }
        var out = prefix
        out.append(Self.openFence)
        out.append(contentsOf: managedLines)
        out.append(Self.closeFence)
        out.append(contentsOf: suffix)
        return out.joined(separator: "\n")
    }

    public func bindings() -> [Binding] {
        // Compute 0-based line offsets for each section so sourceLine is accurate.
        let prefixOffset = 0                                          // prefix starts at line 1 (offset 0)
        let managedOffset = prefix.count + 1                          // +1 for the open-fence line
        let suffixOffset = prefix.count + 1 + managedLines.count + 1 // +1 for close-fence line

        var out: [Binding] = []
        out += parseBindings(from: prefix, managed: false, startLineOffset: prefixOffset)
        out += parseBindings(from: managedLines, managed: true, startLineOffset: managedOffset)
        out += parseBindings(from: suffix, managed: false, startLineOffset: suffixOffset)
        return out
    }

    /// Replace the managed region with freshly rendered bindings. If no fence exists, one is created.
    public mutating func setManagedBindings(_ bindings: [Binding]) throws {
        managedLines = bindings.map { binding -> String in
            let chord = SkhdChord.render(binding.chord)
            let command = binding.launcher.map(LauncherCommand.render) ?? binding.rawText
            return "\(chord) : \(command)"
        }
        hasFence = true
    }

    // MARK: Line parsing

    /// Parse an array of raw lines into Bindings. `startLineOffset` is the 0-based index of
    /// `lines[0]` within the full file (so sourceLine = startLineOffset + localIndex + 1, 1-based).
    private func parseBindings(from lines: [String], managed: Bool, startLineOffset: Int) -> [Binding] {
        // Join skhd line-continuations (trailing backslash); track the first physical line of each logical line.
        var logical: [(text: String, firstLine: Int)] = []
        var buffer = ""
        var bufferLine = 0
        var inBuffer = false

        for (localIndex, raw) in lines.enumerated() {
            let lineNumber = startLineOffset + localIndex + 1  // 1-based
            if !inBuffer && isComment(raw) { continue }
            if !inBuffer { bufferLine = lineNumber; inBuffer = true }
            if raw.hasSuffix("\\") {
                buffer += String(raw.dropLast())
                continue
            }
            buffer += raw
            if !buffer.trimmingCharacters(in: .whitespaces).isEmpty {
                logical.append((buffer, bufferLine))
            }
            buffer = ""
            inBuffer = false
        }
        if !buffer.trimmingCharacters(in: .whitespaces).isEmpty {
            logical.append((buffer, bufferLine))
        }

        return logical.compactMap { (line, lineNum) -> Binding? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let lhs = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let rhs = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard let chord = SkhdChord.parse(lhs) else { return nil }
            let action = LauncherCommand.parse(rhs)
            return Binding(chord: chord, source: .skhd, managed: managed,
                           launcher: action, rawText: rhs,
                           displayName: action?.target ?? summarize(rhs),
                           sourceLine: lineNum)
        }
    }

    private func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }
    private func summarize(_ cmd: String) -> String {
        cmd.split(separator: " ").first.map(String.init) ?? cmd
    }
}

/// Parse/render an skhd chord LHS, e.g. "ctrl + shift + cmd - g" or "hyper - b".
public enum SkhdChord {
    public static func parse(_ lhs: String) -> Chord? {
        let parts = lhs.components(separatedBy: " - ")
        let key: String
        var mods: [String] = []
        if parts.count >= 2 {
            mods = parts[0].split(separator: "+").map { normalizeMod($0.trimmingCharacters(in: .whitespaces)) }
            key = parts[1].trimmingCharacters(in: .whitespaces)
        } else {
            key = lhs.trimmingCharacters(in: .whitespaces)
        }
        guard !key.isEmpty else { return nil }
        return Chord(layer: .skhdModifier, modifiers: mods.filter { !$0.isEmpty }, key: key)
    }

    public static func render(_ chord: Chord) -> String {
        if chord.modifiers.isEmpty { return chord.key }
        let set = Set(chord.modifiers)
        if set == Set(["cmd", "ctrl", "alt", "shift"]) { return "hyper - \(chord.key)" }
        return chord.modifiers.joined(separator: " + ") + " - " + chord.key
    }

    private static func normalizeMod(_ m: String) -> String {
        switch m.lowercased() {
        case "lcmd", "rcmd", "cmd", "command": return "cmd"
        case "lctrl", "rctrl", "ctrl", "control": return "ctrl"
        case "lalt", "ralt", "alt", "option", "opt": return "alt"
        case "lshift", "rshift", "shift": return "shift"
        case "hyper": return "hyper"
        default: return m.lowercased()
        }
    }
}
