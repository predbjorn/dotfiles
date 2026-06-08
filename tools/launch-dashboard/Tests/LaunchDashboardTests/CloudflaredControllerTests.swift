import XCTest
@testable import LaunchDashboard

private final class RecordingRunner: ProcessRunner {
    var calls: [[String]] = []
    func run(_ launchPath: String, _ args: [String]) throws -> ProcessResult {
        calls.append([launchPath] + args)
        return ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }
}

final class CloudflaredControllerTests: XCTestCase {
    private let sample = """
    ingress:
      - hostname: local3000.prebenhafnor.com
        service: http://localhost:3000
      - service: http_status:404
    """

    func testSetEnabledFalseCommentsRuleThroughSymlinkAndReloads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cf-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("config.yml")
        let link = dir.appendingPathComponent("config.link.yml")
        try sample.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let runner = RecordingRunner()
        let c = CloudflaredController(configPath: link, runner: runner, uid: 501,
                                      cloudflaredLabel: "com.prebenhafnor.cloudflared")
        try c.setEnabled(hostname: "local3000.prebenhafnor.com", enabled: false)

        // Symlink still a symlink → we wrote through to the real target.
        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
        // Rule is now disabled.
        let rules = try c.rules()
        XCTAssertEqual(rules.first { $0.hostname == "local3000.prebenhafnor.com" }?.enabled, false)
        // Tunnel was reloaded.
        XCTAssertEqual(runner.calls, [["/bin/launchctl", "kickstart", "-k",
                                       "gui/501/com.prebenhafnor.cloudflared"]])
    }

    func testSetEnabledNoOpWhenAlreadyInDesiredState() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cf-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("config.yml")
        try sample.write(to: target, atomically: true, encoding: .utf8)

        let runner = RecordingRunner()
        let c = CloudflaredController(configPath: target, runner: runner, uid: 501,
                                      cloudflaredLabel: "com.prebenhafnor.cloudflared")
        try c.setEnabled(hostname: "local3000.prebenhafnor.com", enabled: true)  // already enabled
        XCTAssertTrue(runner.calls.isEmpty)  // no write, no reload
    }
}
