import Foundation

/// IO wrapper around a cloudflared config.yml: reads/parses ingress rules, toggles a rule
/// (writing through any symlink to the real file), and reloads the tunnel LaunchAgent.
struct CloudflaredController {
    let configPath: URL          // may be a symlink (e.g. ~/.cloudflared/config.yml → dotfiles)
    let runner: ProcessRunner
    let uid: uid_t
    let cloudflaredLabel: String

    static func makeDefault(config: Config) -> CloudflaredController {
        let raw = config.cloudflaredConfigPath ?? "~/.cloudflared/config.yml"
        let path = NSString(string: raw).expandingTildeInPath
        return CloudflaredController(
            configPath: URL(fileURLWithPath: path),
            runner: RealProcessRunner(),
            uid: getuid(),
            cloudflaredLabel: config.cloudflaredLabel ?? "com.prebenhafnor.cloudflared"
        )
    }

    func rules() throws -> [IngressRule] {
        let text = try String(contentsOf: configPath, encoding: .utf8)
        return IngressConfigParser.parse(text)
    }

    /// Bring `hostname` to the desired enabled state. No-op (no write, no reload) if already there.
    func setEnabled(hostname: String, enabled: Bool) throws {
        let text = try String(contentsOf: configPath, encoding: .utf8)
        guard let rule = IngressConfigParser.parse(text).first(where: { $0.hostname == hostname }),
              !rule.isCatchAll, rule.enabled != enabled
        else { return }
        let newText = IngressConfigParser.toggle(text, hostname: hostname)
        try writeThroughSymlink(newText)
        try LaunchctlClient(runner: runner, uid: uid)
            .kickstart(label: cloudflaredLabel, restart: true)
    }

    /// Atomic write that follows a symlink to its real target (so we never replace the symlink
    /// itself), preserving the target's POSIX permissions.
    private func writeThroughSymlink(_ text: String) throws {
        let target = configPath.resolvingSymlinksInPath()
        let fm = FileManager.default
        let perms = ((try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
                     as? NSNumber)?.intValue ?? 0o644
        let tmp = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).tmp-\(uid)")
        try Data(text.utf8).write(to: tmp, options: .atomic)
        try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: tmp.path)
        _ = try fm.replaceItemAt(target, withItemAt: tmp)
    }
}
