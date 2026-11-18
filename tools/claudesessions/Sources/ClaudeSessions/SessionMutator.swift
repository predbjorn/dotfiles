import Foundation

public enum SessionMutatorError: Error, LocalizedError {
    case readFailed(String)
    case writeFailed(String)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .readFailed(let m), .writeFailed(let m), .malformed(let m): return m
        }
    }
}

public struct SessionMutator: Sendable {
    public init() {}

    /// Sets `isArchived` on the session's JSON file and returns an updated `Session`.
    ///
    /// Note: if the Claude desktop app is running, it may overwrite this change when it
    /// next persists state for that session. Callers may want to advise quitting the app first.
    public func setArchived(_ session: Session, archived: Bool) throws -> Session {
        guard let data = try? Data(contentsOf: session.path) else {
            throw SessionMutatorError.readFailed("Could not read \(session.path.path)")
        }
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SessionMutatorError.malformed("Session JSON is not an object")
        }
        json["isArchived"] = archived
        guard let newData = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            throw SessionMutatorError.writeFailed("Could not serialize updated JSON")
        }
        let tmp = session.path.appendingPathExtension("tmp")
        do {
            try newData.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(session.path, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw SessionMutatorError.writeFailed(error.localizedDescription)
        }
        return Session(
            id: session.id,
            cliSessionId: session.cliSessionId,
            store: session.store,
            title: session.title,
            cwd: session.cwd,
            project: session.project,
            branch: session.branch,
            worktreeName: session.worktreeName,
            archived: archived,
            lastFocusedAt: session.lastFocusedAt,
            lastActivityAt: session.lastActivityAt,
            createdAt: session.createdAt,
            path: session.path
        )
    }
}
