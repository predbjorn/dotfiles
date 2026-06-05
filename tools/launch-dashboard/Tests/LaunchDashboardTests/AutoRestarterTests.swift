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
