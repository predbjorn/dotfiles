import XCTest
@testable import LaunchDashboard

final class FakeRunner: ProcessRunner {
    var responses: [String: ProcessResult] = [:]
    var calls: [(String, [String])] = []
    func run(_ path: String, _ args: [String]) throws -> ProcessResult {
        calls.append((path, args))
        let key = ([path] + args).joined(separator: " ")
        return responses[key] ?? ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }
}

final class LaunchctlClientTests: XCTestCase {
    func testListParsesLoadedServices() throws {
        let fake = FakeRunner()
        let listOutput = """
        PID\tStatus\tLabel
        1234\t0\tcom.example.alpha
        -\t0\tcom.example.beta
        -\t127\tcom.example.gamma
        5678\t-9\tcom.example.delta
        """
        fake.responses["/bin/launchctl list"] =
            ProcessResult(stdout: listOutput, stderr: "", exitCode: 0)
        let client = LaunchctlClient(runner: fake, uid: 501)
        let map = try client.listLoaded()
        XCTAssertEqual(map["com.example.alpha"]?.pid, 1234)
        XCTAssertEqual(map["com.example.alpha"]?.lastExitCode, 0)
        XCTAssertNil(map["com.example.beta"]?.pid)
        XCTAssertEqual(map["com.example.gamma"]?.lastExitCode, 127)
        XCTAssertEqual(map["com.example.delta"]?.pid, 5678)
        XCTAssertEqual(map["com.example.delta"]?.lastExitCode, -9)
    }

    func testKickstartIssuesCorrectCommand() throws {
        let fake = FakeRunner()
        let client = LaunchctlClient(runner: fake, uid: 501)
        try client.kickstart(label: "com.example.alpha", restart: true)
        XCTAssertEqual(fake.calls.last?.0, "/bin/launchctl")
        XCTAssertEqual(fake.calls.last?.1, ["kickstart", "-k", "gui/501/com.example.alpha"])
    }

    func testBootstrapUsesPlistPath() throws {
        let fake = FakeRunner()
        let client = LaunchctlClient(runner: fake, uid: 501)
        try client.bootstrap(plistPath: "/path/to/foo.plist")
        XCTAssertEqual(fake.calls.last?.1, ["bootstrap", "gui/501", "/path/to/foo.plist"])
    }

    func testBootoutUsesDomainLabelTarget() throws {
        let fake = FakeRunner()
        let client = LaunchctlClient(runner: fake, uid: 501)
        try client.bootout(label: "com.example.alpha")
        XCTAssertEqual(fake.calls.last?.1, ["bootout", "gui/501/com.example.alpha"])
    }
}
