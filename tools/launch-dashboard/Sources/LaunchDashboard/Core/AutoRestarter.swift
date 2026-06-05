import Foundation

final class AutoRestarter {
    private struct Track {
        var lastRunning: Bool
        var lastRestartAt: TimeInterval
        var backoffSeconds: TimeInterval
        var runningSince: TimeInterval   // when it most recently transitioned into running
    }
    private var tracks: [String: Track] = [:]
    private let now: () -> TimeInterval
    private let restart: (String) -> Void
    private let ownLabel: String?
    private let maxBackoff: TimeInterval = 300

    init(now: @escaping () -> TimeInterval,
         restart: @escaping (String) -> Void,
         ownLabel: String? = nil) {
        self.now = now
        self.restart = restart
        self.ownLabel = ownLabel
    }

    /// Precondition: called only on the serial work queue (see AppDelegate). [FIX 10]
    func observe(_ statuses: [ServiceStatus]) {
        for s in statuses where s.label != ownLabel {   // [FIX 12]
            var t = tracks[s.label] ?? Track(lastRunning: false,
                                             lastRestartAt: -.infinity,
                                             backoffSeconds: 1,
                                             runningSince: -.infinity)
            let isRunning = (s.state == .running)
            // Crash = running→stopped transition with a non-zero exit recorded at that moment.
            let crashed = t.lastRunning && !isRunning && (s.lastExitCode ?? 0) != 0
            if crashed, now() - t.lastRestartAt >= t.backoffSeconds {
                restart(s.label)
                t.lastRestartAt = now()
                t.backoffSeconds = min(t.backoffSeconds * 2, maxBackoff)
            }
            // Record when the service most recently became running.
            if isRunning && !t.lastRunning {
                t.runningSince = now()
            }
            // Reset backoff only after it has been stably running for a while.
            if isRunning, now() - t.runningSince > 60 {
                t.backoffSeconds = 1
            }
            t.lastRunning = isRunning
            tracks[s.label] = t
        }
    }
}
