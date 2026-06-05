import Foundation

final class ServiceMonitor {
    let scanner: PlistScanner
    let client: LaunchctlClient

    init(scanner: PlistScanner, client: LaunchctlClient) {
        self.scanner = scanner
        self.client = client
    }

    func snapshot() throws -> [ServiceStatus] {
        let entries = try scanner.scan()
        let loaded = try client.listLoaded()
        return entries.map { entry in
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
