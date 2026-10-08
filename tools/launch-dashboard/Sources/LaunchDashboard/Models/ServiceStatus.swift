import Foundation

enum ServiceState: String, Codable {
    case running
    case loadedNotRunning
    case scheduled   // interval/calendar agent idle between runs, last exit 0
    case failed      // interval/calendar agent idle between runs, last exit non-zero
    case notLoaded
    case unknown
}

struct ServiceStatus: Codable, Identifiable, Equatable {
    var id: String { label }
    let label: String
    let state: ServiceState
    let pid: Int?
    /// NOTE: this is launchctl's *last* wait/exit status. It is stale for running jobs and
    /// is only meaningful at a running→stopped transition. Do not treat it as a health flag.
    let lastExitCode: Int?
    let plistPath: String?
    var schedule: String? = nil

    /// Healthy: running, or a scheduled agent waiting for its next run.
    var isUp: Bool { state == .running || state == .scheduled }
}
