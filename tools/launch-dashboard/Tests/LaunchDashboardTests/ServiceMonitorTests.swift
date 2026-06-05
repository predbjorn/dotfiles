import XCTest
@testable import LaunchDashboard

final class ServiceMonitorTests: XCTestCase {
    func testSnapshotJoinsPlistsWithLoadedState() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-mon-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writePlist(at: dir, label: "com.example.alpha")
        try writePlist(at: dir, label: "com.example.beta")
        try writePlist(at: dir, label: "com.example.delta")

        let fake = FakeRunner()
        fake.responses["/bin/launchctl list"] = ProcessResult(
            stdout: "PID\tStatus\tLabel\n42\t0\tcom.example.alpha\n5678\t-9\tcom.example.delta\n",
            stderr: "", exitCode: 0)

        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let snap = try monitor.snapshot()

        XCTAssertEqual(snap.count, 3)
        let alpha = snap.first { $0.label == "com.example.alpha" }!
        let beta = snap.first { $0.label == "com.example.beta" }!
        let delta = snap.first { $0.label == "com.example.delta" }!
        XCTAssertEqual(alpha.state, .running)
        XCTAssertEqual(alpha.pid, 42)
        XCTAssertEqual(beta.state, .notLoaded)
        XCTAssertNil(beta.pid)
        XCTAssertEqual(delta.state, .running)
        XCTAssertEqual(delta.pid, 5678)
    }

    private func writePlist(at dir: URL, label: String) throws {
        let body: [String: Any] = ["Label": label, "ProgramArguments": ["/bin/true"]]
        let data = try PropertyListSerialization.data(fromPropertyList: body,
                                                      format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("\(label).plist"))
    }
}
