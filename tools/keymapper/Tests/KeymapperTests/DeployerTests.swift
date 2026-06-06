import XCTest
@testable import Keymapper

private final class FakeRunner: ProcessRunner {
    var calls: [(String, [String])] = []
    var result = ProcessResult(stdout: "", stderr: "", exitCode: 0)
    func run(_ launchPath: String, _ args: [String]) throws -> ProcessResult {
        calls.append((launchPath, args)); return result
    }
}

final class DeployerTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("km-dep-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testIsInSyncComparesRepoAndDeployed() throws {
        let repo = dir.appendingPathComponent("skhdrc")
        let deployed = dir.appendingPathComponent("deployed")
        try "same\n".write(to: repo, atomically: true, encoding: .utf8)
        try "same\n".write(to: deployed, atomically: true, encoding: .utf8)
        let dep = Deployer(skhdRepo: repo, skhdDeployed: deployed,
                           runner: FakeRunner(), skhdPath: "/opt/homebrew/bin/skhd")
        XCTAssertTrue(try dep.isInSync())
        try "changed\n".write(to: repo, atomically: true, encoding: .utf8)
        XCTAssertFalse(try dep.isInSync())
    }

    func testApplyCopiesRepoToDeployedAndReloadsViaArgv() throws {
        let repo = dir.appendingPathComponent("skhdrc")
        let deployed = dir.appendingPathComponent("sub/deployed")
        try "rules v1\n".write(to: repo, atomically: true, encoding: .utf8)
        let runner = FakeRunner()
        let dep = Deployer(skhdRepo: repo, skhdDeployed: deployed,
                           runner: runner, skhdPath: "/opt/homebrew/bin/skhd")
        try dep.apply()
        XCTAssertEqual(try String(contentsOf: deployed, encoding: .utf8), "rules v1\n")
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].0, "/opt/homebrew/bin/skhd")   // absolute path, no sh -c
        XCTAssertEqual(runner.calls[0].1, ["--reload"])
    }

    func testApplyThrowsWhenReloadFails() throws {
        let repo = dir.appendingPathComponent("skhdrc")
        let deployed = dir.appendingPathComponent("deployed")
        try "rules\n".write(to: repo, atomically: true, encoding: .utf8)
        let runner = FakeRunner()
        runner.result = ProcessResult(stdout: "", stderr: "config error", exitCode: 1)
        let dep = Deployer(skhdRepo: repo, skhdDeployed: deployed,
                           runner: runner, skhdPath: "/opt/homebrew/bin/skhd")
        XCTAssertThrowsError(try dep.apply())
    }
}
