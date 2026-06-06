import Foundation

/// Atomic, backed-up writes for the repo config files.
/// - Backup BEFORE each write (D9).
/// - Write to a temp file on the same volume, then rename(2) (D17).
/// - Backups are user-only and pruned to the newest `retain` (D21, D22).
struct AtomicFileWriter {
    let backupDir: URL
    let timestamp: String
    let retain: Int

    init(backupDir: URL, timestamp: String = AtomicFileWriter.now(), retain: Int = 20) {
        self.backupDir = backupDir
        self.timestamp = timestamp
        self.retain = retain
    }

    static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// Backup (if the target exists) then atomically replace it. Prunes old backups afterward.
    func write(_ contents: String, to target: URL, backupStem stem: String) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try makeBackup(of: target, stem: stem)
            try prune(stem: stem)
        }
        try atomicReplace(target, with: Data(contents.utf8))
    }

    /// Copy the current target into the backup dir as `<stem>.<timestamp>.bak`, mode 0600. Returns its URL.
    @discardableResult
    func makeBackup(of target: URL, stem: String) throws -> URL {
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backup = backupDir.appendingPathComponent("\(stem).\(timestamp).bak")
        let data = try Data(contentsOf: target)
        try data.write(to: backup, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        return backup
    }

    /// Restore a backup over the target (used by the deployer's auto-revert, D25).
    func restore(_ backup: URL, to target: URL) throws {
        try atomicReplace(target, with: try Data(contentsOf: backup))
    }

    private func prune(stem: String) throws {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: backupDir.path)) ?? []
        let mine = all.filter { $0.hasPrefix("\(stem).") && $0.hasSuffix(".bak") }.sorted()
        guard mine.count > retain else { return }
        for name in mine.prefix(mine.count - retain) {
            try? FileManager.default.removeItem(at: backupDir.appendingPathComponent(name))
        }
    }

    /// Write to a temp file in the SAME directory (same volume) then rename — atomic (D17).
    /// Resolves a symlink target so we replace the real file rather than clobbering the link (D18).
    private func atomicReplace(_ target: URL, with data: Data) throws {
        let resolved = URL(fileURLWithPath: (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path))
            .map { link in
                link.hasPrefix("/") ? link
                    : target.deletingLastPathComponent().appendingPathComponent(link).path
            } ?? target.path)
        let dir = resolved.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(resolved.lastPathComponent).tmp-\(timestamp)")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(resolved, withItemAt: tmp)
    }
}
