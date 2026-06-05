import Foundation

enum ServiceState: String, Codable {
    case running
    case loadedNotRunning
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
}
