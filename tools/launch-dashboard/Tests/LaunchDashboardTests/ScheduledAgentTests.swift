import XCTest
@testable import LaunchDashboard

/// Interval/calendar agents (no KeepAlive) run briefly and exit; between runs they are
/// healthy, not "stopped".
final class ScheduledAgentTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ld-sched-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func writePlist(_ label: String, _ extra: [String: Any] = [:]) throws {
        var body: [String: Any] = ["Label": label, "ProgramArguments": ["/bin/true"]]
        body.merge(extra) { $1 }
        let data = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("\(label).plist"))
    }

    private func monitor(launchctlList: String) -> ServiceMonitor {
        let fake = FakeRunner()
        fake.responses["/bin/launchctl list"] = ProcessResult(
            stdout: "PID\tStatus\tLabel\n" + launchctlList, stderr: "", exitCode: 0)
        return ServiceMonitor(scanner: PlistScanner(directory: dir),
                              client: LaunchctlClient(runner: fake, uid: 501))
    }

    // MARK: PlistScanner

    func testScannerDescribesSchedules() throws {
        try writePlist("com.example.interval", ["StartInterval": 600])
        try writePlist("com.example.hourly", ["StartInterval": 7200])
        try writePlist("com.example.calendar", ["StartCalendarInterval": ["Hour": 7, "Minute": 0]])
        try writePlist("com.example.daemon", ["StartInterval": 600, "KeepAlive": true])
        try writePlist("com.example.plain")

        let byLabel = Dictionary(uniqueKeysWithValues:
            try PlistScanner(directory: dir).scan().map { ($0.label, $0.schedule) })
        XCTAssertEqual(byLabel["com.example.interval"], "every 10 min")
        XCTAssertEqual(byLabel["com.example.hourly"], "every 2 h")
        XCTAssertEqual(byLabel["com.example.calendar"], "on a calendar schedule")
        XCTAssertNil(try XCTUnwrap(byLabel["com.example.daemon"]))
        XCTAssertNil(try XCTUnwrap(byLabel["com.example.plain"]))
    }

    // MARK: ServiceMonitor

    func testScheduledAgentStates() throws {
        try writePlist("com.example.idle", ["StartInterval": 600])
        try writePlist("com.example.busy", ["StartInterval": 600])
        try writePlist("com.example.broken", ["StartInterval": 600])
        try writePlist("com.example.daemon")

        let snap = try monitor(launchctlList:
            "-\t0\tcom.example.idle\n77\t0\tcom.example.busy\n-\t1\tcom.example.broken\n-\t0\tcom.example.daemon\n"
        ).snapshot()
        let state = Dictionary(uniqueKeysWithValues: snap.map { ($0.label, $0.state) })
        XCTAssertEqual(state["com.example.idle"], .scheduled)
        XCTAssertEqual(state["com.example.busy"], .running)
        XCTAssertEqual(state["com.example.broken"], .failed)
        XCTAssertEqual(state["com.example.daemon"], .loadedNotRunning)
        XCTAssertEqual(snap.first { $0.label == "com.example.idle" }?.schedule, "every 10 min")
    }

    // MARK: /summary

    func testSummaryCountsIdleScheduledAgentAsUp() throws {
        try writePlist("com.example.idle", ["StartInterval": 600])
        try writePlist("com.example.broken", ["StartInterval": 600])
        let mon = monitor(launchctlList: "-\t0\tcom.example.idle\n-\t2\tcom.example.broken\n")
        let router = Router()
        Routes.register(router: router, monitor: mon, client: mon.client, token: "tok",
                        priorityLabels: ["com.example.idle", "com.example.broken"])

        let resp = router.handle(HTTPRequest(method: "GET", path: "/summary",
                                             headers: ["Authorization": "Bearer tok"], body: Data()))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: resp.body) as? [String: Any])
        XCTAssertEqual(obj["priorityDown"] as? Int, 1)
        let rows = try XCTUnwrap(obj["priority"] as? [[String: Any]])
        let up = Dictionary(uniqueKeysWithValues: rows.map { ($0["label"] as! String, $0["up"] as! Bool) })
        XCTAssertEqual(up["com.example.idle"], true)
        XCTAssertEqual(up["com.example.broken"], false)
    }

    // MARK: AutoRestarter

    func testAutoRestarterLeavesScheduledAgentsToLaunchd() {
        var restarted: [String] = []
        let r = AutoRestarter(now: { 1000 }, restart: { restarted.append($0) })
        r.observe([ServiceStatus(label: "a", state: .running, pid: 1, lastExitCode: 0,
                                 plistPath: nil, schedule: "every 10 min")])
        r.observe([ServiceStatus(label: "a", state: .failed, pid: nil, lastExitCode: 1,
                                 plistPath: nil, schedule: "every 10 min")])
        XCTAssertTrue(restarted.isEmpty)
    }
}
