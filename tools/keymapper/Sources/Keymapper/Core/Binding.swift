import Foundation

enum SourceFile: String, Codable { case karabiner, skhd }

enum LauncherMechanism: String, Codable {
    case toggle   // bin/toggle_app.sh <App>
    case focus    // bin/focus_window_wrapper.sh <App> <bringToCurrent>
    case open     // open <path>  (space+f folder shortcuts)
}

/// A recognized launcher action. `rawCommand` is the verbatim source of truth (D11).
struct LauncherAction: Equatable {
    var mechanism: LauncherMechanism
    var target: String
    var focusBringToCurrent: Bool
    var rawCommand: String
}

/// One keymap binding. `launcher == nil` means an opaque action (e.g. yabai pipeline):
/// the chord is still parsed for conflict detection + cheatsheet (D29).
struct Binding: Equatable {
    var chord: Chord
    var source: SourceFile
    var managed: Bool
    var launcher: LauncherAction?
    var rawText: String
    var displayName: String
    var sourceLine: Int?   // 1-based line number in skhdrc (nil for karabiner bindings, D29)

    init(chord: Chord, source: SourceFile, managed: Bool, launcher: LauncherAction?,
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
