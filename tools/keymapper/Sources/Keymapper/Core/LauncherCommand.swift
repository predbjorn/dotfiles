import Foundation

/// Parse/render the three recognized launcher command shapes. Anything else is opaque (parse -> nil).
public enum LauncherCommand {
    public static let toggleScript = "$HOME/.dotfiles/bin/toggle_app.sh"
    public static let focusScript  = "$HOME/.dotfiles/bin/focus_window_wrapper.sh"

    public static func parse(_ command: String) -> LauncherAction? {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        let tokens = tokenize(cmd)
        guard let first = tokens.first else { return nil }
        let script = (first as NSString).lastPathComponent

        switch script {
        case "toggle_app.sh":
            guard tokens.count == 2 else { return nil }
            return LauncherAction(mechanism: .toggle, target: tokens[1],
                                  focusBringToCurrent: false, rawCommand: command)
        case "focus_window_wrapper.sh":
            guard tokens.count == 2 || tokens.count == 3 else { return nil }
            let flag = tokens.count >= 3 ? (tokens[2] == "true") : false
            return LauncherAction(mechanism: .focus, target: tokens[1],
                                  focusBringToCurrent: flag, rawCommand: command)
        default:
            if first == "open", tokens.count == 2 {
                return LauncherAction(mechanism: .open, target: tokens[1],
                                      focusBringToCurrent: false, rawCommand: command)
            }
            return nil
        }
    }

    public static func render(_ a: LauncherAction) -> String {
        switch a.mechanism {
        case .toggle: return "\(toggleScript) \(ShellQuote.quote(a.target))"
        case .focus:  return "\(focusScript) \(ShellQuote.quote(a.target)) \(a.focusBringToCurrent ? "true" : "false")"
        case .open:   return "open \(ShellQuote.quote(a.target))"
        }
    }

    /// Minimal shell tokenizer: splits on whitespace, honoring single and double quotes. No expansion.
    public static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character? = nil
        var hasToken = false
        for ch in s {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch; hasToken = true
            } else if ch == " " || ch == "\t" {
                if hasToken { tokens.append(current); current = ""; hasToken = false }
            } else {
                current.append(ch); hasToken = true
            }
        }
        if hasToken { tokens.append(current) }
        return tokens
    }
}
