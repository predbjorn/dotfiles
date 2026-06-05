import XCTest
@testable import LaunchDashboard

final class CrashTrackerTests: XCTestCase {
    private func status(_ label: String, _ state: ServiceState, exit: Int?) -> ServiceStatus {
        ServiceStatus(label: label, state: state, pid: state == .running ? 1 : nil,
                      lastExitCode: exit, plistPath: nil)
    }

    func testEmitsOnceOnCrashTransitionThenDedups() {
        let t = CrashTracker()
        XCTAssertTrue(t.update([status("a", .running, exit: 0)]).isEmpty)
        let ev = t.update([status("a", .loadedNotRunning, exit: 1)])
        XCTAssertEqual(ev.map(\.label), ["a"])
        XCTAssertEqual(t.crashed, ["a"])
        XCTAssertTrue(t.update([status("a", .loadedNotRunning, exit: 1)]).isEmpty)
    }

    func testGracefulExitDoesNotEmit() {
        let t = CrashTracker()
        _ = t.update([status("a", .running, exit: 0)])
        XCTAssertTrue(t.update([status("a", .loadedNotRunning, exit: 0)]).isEmpty)
        XCTAssertTrue(t.crashed.isEmpty)
    }

    func testRecoveryReArmsAndReEmits() {
        let t = CrashTracker()
        _ = t.update([status("a", .running, exit: 0)])
        _ = t.update([status("a", .loadedNotRunning, exit: 1)])   // crash 1
        let recovered = t.update([status("a", .running, exit: 1)]) // back up
        XCTAssertTrue(recovered.isEmpty)
        XCTAssertTrue(t.crashed.isEmpty)
        let ev = t.update([status("a", .loadedNotRunning, exit: 1)]) // crash 2
        XCTAssertEqual(ev.map(\.label), ["a"])
    }

    func testAlreadyDownAtStartupDoesNotEmit() {
        let t = CrashTracker()
        XCTAssertTrue(t.update([status("a", .loadedNotRunning, exit: 1)]).isEmpty)
        XCTAssertTrue(t.crashed.isEmpty)
    }
}
