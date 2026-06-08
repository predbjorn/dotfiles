import Foundation

public enum Paths {
    /// $DOTFILES or ~/.dotfiles. We always edit the REPO files, never the deployed symlink/copy (D18).
    public static var dotfiles: URL {
        if let env = ProcessInfo.processInfo.environment["DOTFILES"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dotfiles")
    }
    public static var karabinerRepo: URL { dotfiles.appendingPathComponent(".config/karabiner.json") }
    public static var skhdRepo: URL { dotfiles.appendingPathComponent(".config/skhdrc") }

    /// Where sync.sh copies skhdrc for skhd to read. Used only for drift detection, never edited.
    public static var skhdDeployed: URL {
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return xdg.appendingPathComponent("skhd/skhdrc")
    }

    /// Backups live outside the repo, user-only (D21).
    public static var backupDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keymapper/backups")
    }
}
