import Foundation

public enum SessionStore: String, CaseIterable, Hashable, Codable, Sendable {
    case work
    case personal

    public var displayName: String {
        switch self {
        case .work: return "Work"
        case .personal: return "Personal"
        }
    }
}

public struct Session: Identifiable, Hashable, Sendable {
    public let id: String              // desktop app's local sessionId
    public let cliSessionId: String?   // what `claude --resume` expects
    public let store: SessionStore
    public let title: String
    public let cwd: String
    public let project: String
    public let branch: String?
    public let worktreeName: String?
    public let archived: Bool
    public let lastFocusedAt: Date?
    public let lastActivityAt: Date?
    public let createdAt: Date?
    public let path: URL

    public var bestDate: Date? {
        lastFocusedAt ?? lastActivityAt ?? createdAt
    }

    public var isWorktree: Bool { worktreeName != nil }

    /// The ID to pass to `claude --resume`. Falls back to the desktop ID if no CLI ID is recorded.
    public var resumeId: String { cliSessionId ?? id }
}
