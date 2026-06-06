import Foundation

/// Makes skhd changes live with the minimal scoped step (D12): copy repo skhdrc to the deployed path,
/// then `skhd --reload` via argv with an absolute path (D20). karabiner is symlinked (no deploy step).
struct Deployer {
    let skhdRepo: URL
    let skhdDeployed: URL
    let runner: ProcessRunner
    let skhdPath: String

    static func makeReal() -> Deployer {
        Deployer(skhdRepo: Paths.skhdRepo, skhdDeployed: Paths.skhdDeployed,
                 runner: RealProcessRunner(), skhdPath: resolveSkhd())
    }

    /// Prefer Homebrew's path; fall back if neither exists (caller surfaces errors).
    static func resolveSkhd() -> String {
        for p in ["/opt/homebrew/bin/skhd", "/usr/local/bin/skhd"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return "/opt/homebrew/bin/skhd"
    }

    /// True iff repo and deployed files have identical byte content.
    func isInSync() throws -> Bool {
        guard FileManager.default.fileExists(atPath: skhdDeployed.path) else { return false }
        let a = try Data(contentsOf: skhdRepo)
        let b = try Data(contentsOf: skhdDeployed)
        return a == b
    }

    /// Copy repo → deployed (FileManager, not a shelled cp — D20), then reload skhd.
    func apply() throws {
        try FileManager.default.createDirectory(
            at: skhdDeployed.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: skhdDeployed.path) {
            try FileManager.default.removeItem(at: skhdDeployed)
        }
        try FileManager.default.copyItem(at: skhdRepo, to: skhdDeployed)
        let r = try runner.run(skhdPath, ["--reload"])
        if r.exitCode != 0 { throw DeployError.reloadFailed(r.stderr) }
    }
}

enum DeployError: Error, Equatable { case reloadFailed(String) }
