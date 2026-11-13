import Foundation

public enum SessionResumeError: Error, LocalizedError {
    case scriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .scriptFailed(let msg): return msg
        }
    }
}

public struct SessionResume: Sendable {
    public init() {}

    /// The shell command run in the terminal to resume a session.
    ///
    /// `claude --resume <id>` is cwd-scoped: it only finds a session in
    /// `~/.claude/projects/<encoded-cwd>/`, keyed by the directory the session ran
    /// in. When that directory was a git worktree that has since been deleted, a bare
    /// `cd` fails and (because of `&&`) `claude` never runs. The transcript still
    /// exists on disk, and the CLI locates it purely by the encoded cwd *path* — the
    /// directory need not be a real git worktree — so we recreate the directory first.
    /// `mkdir -p` is idempotent, so this is a no-op for sessions whose cwd still exists.
    public func resumeCommand(for session: Session) -> String {
        let escapedCwd = shellQuote(session.cwd)
        let escapedId = shellQuote(session.resumeId)
        return "mkdir -p \(escapedCwd) && cd \(escapedCwd) && claude --resume \(escapedId)"
    }

    /// Open iTerm2 and run the resume command in a new tab/window.
    public func resumeInITerm(session: Session) throws {
        let command = resumeCommand(for: session)
        let escapedCommand = appleScriptQuote(command)

        let script = """
        tell application "iTerm"
            activate
            if (count of windows) = 0 then
                create window with default profile
            else
                tell current window to create tab with default profile
            end if
            tell current session of current window to write text \(escapedCommand)
        end tell
        """
        try runAppleScript(script)
    }

    private func runAppleScript(_ source: String) throws {
        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SessionResumeError.scriptFailed("Could not compile AppleScript")
        }
        script.executeAndReturnError(&errorDict)
        if let errorDict {
            let msg = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw SessionResumeError.scriptFailed(msg)
        }
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
