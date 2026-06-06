import Foundation

/// POSIX shell-safe quoting for fields interpolated into generated launcher commands (D19).
/// Single-quote everything that isn't a known-safe bare word; escape embedded single quotes
/// with the close-quote/escaped-quote/reopen-quote idiom.
/// Contract: callers must place quoted values in fixed positional argument slots, not flag
/// positions — quoting does not defend against option-injection (e.g. a bare "-rf").
enum ShellQuote {
    private static let safe = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./")

    static func quote(_ s: String) -> String {
        if !s.isEmpty && s.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return s
        }
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
