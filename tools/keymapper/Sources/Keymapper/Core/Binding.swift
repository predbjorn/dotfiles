import Foundation

public enum SourceFile: String, Codable { case karabiner, skhd }

public enum LauncherMechanism: String, Codable {
    case toggle   // bin/toggle_app.sh <App>
    case focus    // bin/focus_window_wrapper.sh <App> <bringToCurrent>
    case open     // open <path>  (space+f folder shortcuts)
}

/// A recognized launcher action. `rawCommand` is the verbatim source of truth (D11).
public struct LauncherAction: Equatable {
    public var mechanism: LauncherMechanism
    public var target: String
    public var focusBringToCurrent: Bool
    public var rawCommand: String

    public init(mechanism: LauncherMechanism, target: String, focusBringToCurrent: Bool, rawCommand: String) {
        self.mechanism = mechanism
        self.target = target
        self.focusBringToCurrent = focusBringToCurrent
        self.rawCommand = rawCommand
    }
}

/// One keymap binding. `launcher == nil` means an opaque action (e.g. yabai pipeline):
/// the chord is still parsed for conflict detection + cheatsheet (D29).
public struct Binding: Equatable {
    public var chord: Chord
    public var source: SourceFile
    public var managed: Bool
    public var launcher: LauncherAction?
    public var rawText: String
    public var displayName: String
    public var sourceLine: Int?   // 1-based line number in skhdrc (nil for karabiner bindings, D29)

    public init(chord: Chord, source: SourceFile, managed: Bool, launcher: LauncherAction?,
         rawText: String, displayName: String, sourceLine: Int? = nil) {
        self.chord = chord
        self.source = source
        self.managed = managed
        self.launcher = launcher
        self.rawText = rawText
        self.displayName = displayName
        self.sourceLine = sourceLine
    }
}
