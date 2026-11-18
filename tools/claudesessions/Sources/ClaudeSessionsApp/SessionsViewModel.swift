import Foundation
import SwiftUI
import ClaudeSessions

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var filters: SessionFilters = .initial
    @Published var loadError: String?
    @Published var actionError: String?

    private let loader = SessionLoader()
    private let resumer = SessionResume()
    private let mutator = SessionMutator()

    func reload() {
        sessions = loader.loadAll()
    }

    func resume(_ session: Session) {
        do {
            try resumer.resumeInITerm(session: session)
        } catch {
            actionError = error.localizedDescription
        }
    }

    func setArchived(_ session: Session, archived: Bool) {
        do {
            let updated = try mutator.setArchived(session, archived: archived)
            if let idx = sessions.firstIndex(where: { $0.path == updated.path }) {
                sessions[idx] = updated
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    var filtered: [Session] {
        filters.apply(to: sessions).sorted { lhs, rhs in
            (lhs.bestDate ?? .distantPast) > (rhs.bestDate ?? .distantPast)
        }
    }

    var allProjects: [String] {
        let names = Set(sessions.map(\.project))
        return names.sorted()
    }

    var grouped: [(project: String, sessions: [Session])] {
        let f = filtered
        var byProject: [String: [Session]] = [:]
        for s in f {
            byProject[s.project, default: []].append(s)
        }
        return byProject
            .map { (project: $0.key, sessions: $0.value) }
            .sorted { lhs, rhs in
                let lhsMax = lhs.sessions.compactMap(\.bestDate).max() ?? .distantPast
                let rhsMax = rhs.sessions.compactMap(\.bestDate).max() ?? .distantPast
                return lhsMax > rhsMax
            }
    }
}
