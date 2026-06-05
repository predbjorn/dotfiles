import Foundation

final class ServiceMonitor {
    let scanner: PlistScanner
    let client: LaunchctlClient
    /// nil = watch all; otherwise only labels in this set are reported in the snapshot.
    let watchedLabels: Set<String>?

    init(scanner: PlistScanner, client: LaunchctlClient, watchedLabels: [String]? = nil) {
        self.scanner = scanner
        self.client = client
        let set = Set(watchedLabels ?? [])
        self.watchedLabels = set.isEmpty ? nil : set
    }

    func snapshot() throws -> [ServiceStatus] {
        let entries = try scanner.scan()
        let loaded = try client.listLoaded()
        // Watch-list filter: when set, keep only labels the user is watching.
        let watched = entries.filter { watchedLabels?.contains($0.label) ?? true }
        return watched.map { entry in
            if let live = loaded[entry.label] {
                // [FIX 1] running iff a PID exists; Status column never decides this.
                let state: ServiceState = live.pid != nil ? .running : .loadedNotRunning
                return ServiceStatus(
                    label: entry.label, state: state, pid: live.pid,
                    lastExitCode: live.lastExitCode, plistPath: entry.plistPath
                )
            }
            return ServiceStatus(
                label: entry.label, state: .notLoaded, pid: nil,
                lastExitCode: nil, plistPath: entry.plistPath
            )
        }
    }
}
