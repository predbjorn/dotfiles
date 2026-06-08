import Foundation

/// Holds karabiner.json as a lossless JSONValue and exposes the SpaceLauncher launchers as Bindings.
/// Only the managed rule's shell_commands are mutated; everything else is preserved (D7, D24).
public struct KarabinerDocument {
    private var root: JSONValue
    public static let managedPrefix = "keymap: "
    public static let spaceLauncherName = "SpaceLauncher shortcuts"

    public init(text: String) throws { root = try JSONValue.parse(text) }

    public func serialized() -> String { root.serialized(indent: 2) + "\n" }

    // MARK: Reading
    public func bindings() -> [Binding] {
        guard let rule = spaceLauncherRule() else { return [] }
        let managed = (rule.description ?? "").hasPrefix(Self.managedPrefix)
        guard case .array(let mans)? = rule.value["manipulators"] else { return [] }
        var out: [Binding] = []
        for m in mans {
            guard let key = m["from"]?["key_code"]?.stringValue,
                  let to = m["to"]?.arrayValue,
                  let shell = to.compactMap({ $0["shell_command"]?.stringValue }).first
            else { continue }
            let names = Self.conditionNames(m)
            let layer: Layer = names.contains("space_f_mode") ? .spaceFLeader : .spaceLeader
            let action = LauncherCommand.parse(shell)
            out.append(Binding(
                chord: Chord(layer: layer, modifiers: [], key: key),
                source: .karabiner, managed: managed, launcher: action,
                rawText: shell,
                displayName: action?.target ?? shell))
        }
        return out
    }

    // MARK: Mutating
    public mutating func adoptSpaceLauncherRule() {
        root = Self.rewritingSpaceLauncherRule(in: root) { rule in
            let desc = rule["description"]?.stringValue ?? Self.spaceLauncherName
            if !desc.hasPrefix(Self.managedPrefix) {
                rule = rule.settingKey("description", to: .string(Self.managedPrefix + desc))
            }
        }
    }

    public mutating func setLauncherTarget(layer: Layer, key: String, action: LauncherAction) throws {
        let newShell = LauncherCommand.render(action)
        root = Self.rewritingSpaceLauncherRule(in: root) { rule in
            guard case .array(var mans)? = rule["manipulators"] else { return }
            for i in mans.indices {
                guard mans[i]["from"]?["key_code"]?.stringValue == key else { continue }
                let names = Self.conditionNames(mans[i])
                let mLayer: Layer = names.contains("space_f_mode") ? .spaceFLeader : .spaceLeader
                guard mLayer == layer else { continue }
                // Rewrite only the shell_command entry; preserve siblings (e.g. set_variable).
                guard case .array(var toArr)? = mans[i]["to"] else { continue }
                for ti in toArr.indices where toArr[ti]["shell_command"] != nil {
                    toArr[ti] = toArr[ti].settingKey("shell_command", to: .string(newShell))
                }
                mans[i] = mans[i].settingKey("to", to: .array(toArr))
            }
            rule = rule.settingKey("manipulators", to: .array(mans))
        }
    }

    // MARK: Helpers
    private struct Located { var value: JSONValue; var description: String? }

    /// Intentional asymmetry: reads return the rule from the FIRST matching profile, while writes
    /// (rewritingSpaceLauncherRule) apply to the rule in ALL profiles. The real file has one
    /// profile, so this is moot today.
    private func spaceLauncherRule() -> Located? {
        for rule in allRules() {
            if let d = rule["description"]?.stringValue,
               d == Self.spaceLauncherName || d == Self.managedPrefix + Self.spaceLauncherName {
                return Located(value: rule, description: d)
            }
        }
        return nil
    }

    private func allRules() -> [JSONValue] {
        guard case .array(let profiles)? = root["profiles"] else { return [] }
        var rules: [JSONValue] = []
        for p in profiles {
            if case .array(let rs)? = p["complex_modifications"]?["rules"] { rules += rs }
        }
        return rules
    }

    private static func conditionNames(_ manipulator: JSONValue) -> [String] {
        guard case .array(let conds)? = manipulator["conditions"] else { return [] }
        return conds.compactMap { $0["name"]?.stringValue }
    }

    /// Return a copy of `root` with `transform` applied to the SpaceLauncher rule in-place within
    /// the full object graph; every other key is preserved.
    private static func rewritingSpaceLauncherRule(
        in root: JSONValue, _ transform: (inout JSONValue) -> Void
    ) -> JSONValue {
        guard case .array(var profiles)? = root["profiles"] else { return root }
        for pi in profiles.indices {
            guard case .array(var rules)? = profiles[pi]["complex_modifications"]?["rules"] else { continue }
            for ri in rules.indices {
                guard let d = rules[ri]["description"]?.stringValue,
                      d == spaceLauncherName || d == managedPrefix + spaceLauncherName
                else { continue }
                transform(&rules[ri])
            }
            let cm = (profiles[pi]["complex_modifications"] ?? .object([]))
                .settingKey("rules", to: .array(rules))
            profiles[pi] = profiles[pi].settingKey("complex_modifications", to: cm)
        }
        return root.settingKey("profiles", to: .array(profiles))
    }
}

private extension JSONValue {
    var description: String? { self["description"]?.stringValue }

    /// Return a copy of this object with `key` set to `value`, preserving order (replacing in place
    /// if present, else appending).
    func settingKey(_ key: String, to value: JSONValue) -> JSONValue {
        guard case .object(var pairs) = self else { return .object([(key, value)]) }
        if let idx = pairs.firstIndex(where: { $0.0 == key }) { pairs[idx] = (key, value) }
        else { pairs.append((key, value)) }
        return .object(pairs)
    }
}
