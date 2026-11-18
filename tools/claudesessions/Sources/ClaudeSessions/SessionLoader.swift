import Foundation

public struct SessionLoader: Sendable {
    public init() {}

    public func storeRoot(for store: SessionStore) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirName: String
        switch store {
        case .work: dirName = "Claude"
        case .personal: dirName = "Claude-Personal"
        }
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent(dirName)
            .appendingPathComponent("claude-code-sessions")
    }

    public func loadAll() -> [Session] {
        SessionStore.allCases.flatMap { load(store: $0) }
    }

    public func load(store: SessionStore) -> [Session] {
        let root = storeRoot(for: store)
        guard let urls = try? collectJSON(under: root) else { return [] }
        return urls.compactMap { decodeSession(at: $0, store: store) }
    }

    private func collectJSON(under root: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix("local_") && name.hasSuffix(".json") {
                out.append(url)
            }
        }
        return out
    }

    private func decodeSession(at url: URL, store: SessionStore) -> Session? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(no title)"
        let cwd = (json["cwd"] as? String) ?? (json["originCwd"] as? String) ?? "(unknown)"
        let id = (json["sessionId"] as? String)
            ?? url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "local_", with: "")
        let cliSessionId = (json["cliSessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let archived = (json["isArchived"] as? Bool) ?? false
        let branch = json["branch"] as? String
        let worktreeName = json["worktreeName"] as? String

        return Session(
            id: id,
            cliSessionId: cliSessionId,
            store: store,
            title: title,
            cwd: cwd,
            project: Self.projectFor(cwd: cwd),
            branch: (branch?.isEmpty ?? true) ? nil : branch,
            worktreeName: (worktreeName?.isEmpty ?? true) ? nil : worktreeName,
            archived: archived,
            lastFocusedAt: Self.date(from: json["lastFocusedAt"]),
            lastActivityAt: Self.date(from: json["lastActivityAt"]),
            createdAt: Self.date(from: json["createdAt"]),
            path: url
        )
    }

    private static func date(from raw: Any?) -> Date? {
        guard let ms = raw as? Double else {
            if let ms = raw as? Int { return Date(timeIntervalSince1970: Double(ms) / 1000) }
            return nil
        }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    public static func projectFor(cwd: String) -> String {
        if let range = cwd.range(of: "/.claude/worktrees/") {
            return String(cwd[..<range.lowerBound])
        }
        if let range = cwd.range(of: "-wt-") {
            return String(cwd[..<range.lowerBound])
        }
        return cwd
    }
}
