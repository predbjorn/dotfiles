import Foundation

enum SourceFile: String, Codable { case karabiner, skhd }

enum LauncherMechanism: String, Codable {
    case toggle   // bin/toggle_app.sh <App>
    case focus    // bin/focus_window_wrapper.sh <App> <bringToCurrent>
    case open     // open <path>  (space+f folder shortcuts)
}

/// A recognized launcher action. `rawCommand` is the verbatim source of truth (D11);
/// structured fields are derived and used to regenerate via the SAME mechanism on edit.
struct LauncherAction: Equatable {
    var mechanism: LauncherMechanism
    var target: String          // app name or folder path
    var focusBringToCurrent: Bool   // only meaningful for .focus; false otherwise
    var rawCommand: String
}

/// One keymap binding. `launcher == nil` means an opaque/non-launcher action (e.g. a yabai pipeline):
/// the chord is still parsed so it participates in conflict detection + cheatsheet (D29).
struct Binding: Equatable {
    var chord: Chord
    var source: SourceFile
    var managed: Bool
    var launcher: LauncherAction?
    var rawText: String         // verbatim source span / shell command for round-trip (D8)
    var displayName: String     // for cheatsheet: app name, folder, or a short command summary
}
