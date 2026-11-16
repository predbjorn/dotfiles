import Foundation

/// Runs the `simq` CLI as the human: Claude's session env is stripped so simq sees a person, not an agent.
enum SimqCLI {
    static func executable(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        env["SIMQ_BIN"] ?? "\(Paths.home)/.local/bin/simq"
    }

    /// Drops `CLAUDE_*` (so simq doesn't see an agent) and `SIMQ_NO_SKETCHYBAR` (so the badge updates).
    static func environment(from env: [String: String]) -> [String: String] {
        env.filter { !$0.key.hasPrefix("CLAUDE_") && $0.key != "SIMQ_NO_SKETCHYBAR" }
    }

    /// Exit codes: 0 ok, 1 error, 2 queued/timeout, 3 refused, 4 not allowed (not human).
    static func run(_ args: [String]) async -> (code: Int32, output: String) {
        let r = await Shell.run(executable(), args, env: environment(from: Shell.environment))
        return (r.status, [r.out, r.err].filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    /// simq asks for `--force` when e.g. disk space is short.
    static func needsForce(_ output: String) -> Bool { output.contains("--force") }
}
