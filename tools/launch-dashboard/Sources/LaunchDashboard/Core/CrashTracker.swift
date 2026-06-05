import Foundation

final class CrashTracker {
    struct Event: Equatable { let label: String; let exitCode: Int? }

    private var running: [String: Bool] = [:]
    private(set) var crashed: Set<String> = []

    /// Precondition: called only on the serial work queue (see AppDelegate). [FIX 10]
    /// Returns labels that *newly* crashed this tick (running→stopped, non-zero exit).
    func update(_ statuses: [ServiceStatus]) -> [Event] {
        var events: [Event] = []
        for s in statuses {
            let isRunning = (s.state == .running)
            // First sighting: seed prior state with the current one so there is no phantom transition.
            let wasRunning = running[s.label] ?? isRunning
            let crashedNow = wasRunning && !isRunning && (s.lastExitCode ?? 0) != 0
            if crashedNow, !crashed.contains(s.label) {
                crashed.insert(s.label)
                events.append(Event(label: s.label, exitCode: s.lastExitCode))
            }
            if isRunning { crashed.remove(s.label) }   // recovery re-arms
            running[s.label] = isRunning
        }
        return events
    }
}
