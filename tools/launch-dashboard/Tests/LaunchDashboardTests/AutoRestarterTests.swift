import XCTest
@testable import LaunchDashboard

final class AutoRestarterTests: XCTestCase {
    func testFiresRestartOnRunningToCrashTransition() {
        var kicks: [String] = []
        let restarter = AutoRestarter(now: { 0 },
                                      restart: { label in kicks.append(label) })
        let s1 = ServiceStatus(label: "a", state: .running, pid: 1,
                               lastExitCode: 0, plistPath: nil)
        let s2 = ServiceStatus(label: "a", state: .loadedNotRunning, pid: nil,
                               lastExitCode: 1, plistPath: nil)
        restarter.observe([s1])
        restarter.observe([s2])
        XCTAssertEqual(kicks, ["a"])
    }

    func testDoesNotRestartGracefulExit() {
        var kicks: [String] = []
        let restarter = AutoRestarter(now: { 0 },
                                      restart: { label in kicks.append(label) })
        let s1 = ServiceStatus(label: "a", state: .running, pid: 1,
                               lastExitCode: 0, plistPath: nil)
        let s2 = ServiceStatus(label: "a", state: .loadedNotRunning, pid: nil,
                               lastExitCode: 0, plistPath: nil)
        restarter.observe([s1])
        restarter.observe([s2])
        XCTAssertEqual(kicks, [])
    }

    func testBackoffSkipsRestartIfTooSoon() {
        var time: TimeInterval = 0
        var kicks: [String] = []
        let restarter = AutoRestarter(now: { time },
                                      restart: { label in kicks.append(label) })
        let running = ServiceStatus(label: "a", state: .running, pid: 1,
                                    lastExitCode: 0, plistPath: nil)
        let crashed = ServiceStatus(label: "a", state: .loadedNotRunning, pid: nil,
                                    lastExitCode: 1, plistPath: nil)
        restarter.observe([running])
        restarter.observe([crashed])           // kick #1 at t=0
        time = 0.5
        restarter.observe([running])
        restarter.observe([crashed])           // still inside 1s window, skipped
        XCTAssertEqual(kicks, ["a"])
    }

    func testSecondCrashRestartsAfterBackoffWindow() {
        var time: TimeInterval = 0
        var kicks: [String] = []
        let restarter = AutoRestarter(now: { time }, restart: { kicks.append($0) })
        let running = ServiceStatus(label: "a", state: .running, pid: 1, lastExitCode: 0, plistPath: nil)
        let crashed = ServiceStatus(label: "a", state: .loadedNotRunning, pid: nil, lastExitCode: 1, plistPath: nil)
        restarter.observe([running])
        restarter.observe([crashed])      // kick #1 at t=0, backoff -> 2
        time = 3                          // past the 2s window
        restarter.observe([running])
        restarter.observe([crashed])      // kick #2 at t=3 (gate 3 >= 2)
        XCTAssertEqual(kicks, ["a", "a"])
    }

    func testSlowRecoveryDoesNotPrematurelyResetBackoff() {
        // Regression: a service that recovers slowly must NOT have its backoff reset on the
        // first running poll. With the bug, this produced 3 kicks; correct behavior is 2.
        var time: TimeInterval = 0
        var kicks: [String] = []
        let restarter = AutoRestarter(now: { time }, restart: { kicks.append($0) })
        let running = ServiceStatus(label: "a", state: .running, pid: 1, lastExitCode: 0, plistPath: nil)
        let crashed = ServiceStatus(label: "a", state: .loadedNotRunning, pid: nil, lastExitCode: 1, plistPath: nil)
        restarter.observe([running])
        restarter.observe([crashed])      // kick #1 at t=0, backoff -> 2
        time = 70                         // stayed crashed a long time, only now recovers
        restarter.observe([running])      // runningSince = 70; must NOT reset backoff (still 2)
        time = 70.5
        restarter.observe([crashed])      // kick #2; backoff -> 4 (would be 2 if reset bug present)
        time = 71
        restarter.observe([running])
        time = 73                         // 2.5s since kick #2: < 4 (fixed) but >= 2 (buggy)
        restarter.observe([crashed])      // must be SKIPPED with the fix
        XCTAssertEqual(kicks, ["a", "a"])
    }

    func testDoesNotRestartOwnLabel() {
        var kicks: [String] = []
        let restarter = AutoRestarter(now: { 0 },
                                      restart: { label in kicks.append(label) },
                                      ownLabel: "self")
        let running = ServiceStatus(label: "self", state: .running, pid: 1,
                                    lastExitCode: 0, plistPath: nil)
        let crashed = ServiceStatus(label: "self", state: .loadedNotRunning, pid: nil,
                                    lastExitCode: 1, plistPath: nil)
        restarter.observe([running])
        restarter.observe([crashed])
        XCTAssertEqual(kicks, [])
    }
}
