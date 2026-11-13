import Foundation

public enum StatusFilter: String, CaseIterable, Hashable, Sendable {
    case active
    case archived
    case all

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .archived: return "Archived"
        case .all: return "All"
        }
    }
}

public enum AccountFilter: Hashable, Sendable {
    case all
    case store(SessionStore)

    public var displayName: String {
        switch self {
        case .all: return "All"
        case .store(let s): return s.displayName
        }
    }
}

public enum GroupMode: String, CaseIterable, Hashable, Sendable {
    case byProject
    case flat

    public var displayName: String {
        switch self {
        case .byProject: return "By project"
        case .flat: return "Flat"
        }
    }
}

public struct SessionFilters: Hashable, Sendable {
    public var status: StatusFilter
    public var account: AccountFilter
    public var project: String?  // nil = all
    public var search: String
    public var groupMode: GroupMode

    public static let initial = SessionFilters(
        status: .active,
        account: .all,
        project: nil,
        search: "",
        groupMode: .byProject
    )

    public init(
        status: StatusFilter,
        account: AccountFilter,
        project: String?,
        search: String,
        groupMode: GroupMode
    ) {
        self.status = status
        self.account = account
        self.project = project
        self.search = search
        self.groupMode = groupMode
    }

    public func apply(to sessions: [Session]) -> [Session] {
        sessions.filter { matches($0) }
    }

    public func matches(_ s: Session) -> Bool {
        switch status {
        case .active: if s.archived { return false }
        case .archived: if !s.archived { return false }
        case .all: break
        }
        switch account {
        case .all: break
        case .store(let store): if s.store != store { return false }
        }
        if let project, s.project != project { return false }
        if !search.isEmpty {
            let needle = search.lowercased()
            if !s.title.lowercased().contains(needle)
                && !s.cwd.lowercased().contains(needle) {
                return false
            }
        }
        return true
    }
}
