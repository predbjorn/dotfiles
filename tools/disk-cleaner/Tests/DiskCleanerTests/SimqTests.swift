import XCTest
@testable import DiskCleaner

final class SimqTests: XCTestCase {
    private var fixture: String { Bundle.module.resourcePath! + "/Fixtures/simq" }

    func testMissingHomeShowsNothing() {
        XCTAssertNil(Simq.load(home: "/nonexistent/simq-\(UUID())"))
    }

    func testCorruptPolicyShowsNothing() {
        XCTAssertNil(Simq.parse(policy: Data("{not json".utf8), state: nil))
        XCTAssertNil(Simq.parse(policy: Data("[1, 2]".utf8), state: nil))
    }

    func testPolicyWithoutStateIsAllFree() throws {
        let policy = try XCTUnwrap(FileManager.default.contents(atPath: fixture + "/policy.json"))
        let s = try XCTUnwrap(Simq.parse(policy: policy, state: Data("{partial".utf8)))
        XCTAssertEqual(s.state(of: "Sim-A"), .free)
        XCTAssertEqual(s.summary(), "simq: 0/2 sims held · 0/1 emulators held")
    }

    func testFixturePolicyAndState() throws {
        let s = try XCTUnwrap(Simq.load(home: fixture))
        XCTAssertEqual(s.iosRuntime, "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
        XCTAssertEqual(s.androidImage, "system-images/android-35/google_apis_playstore/arm64-v8a")
        XCTAssertEqual(s.gradleVersions, ["8.11.1", "9.0.0", "9.3.1"])
        XCTAssertEqual(s.poolName(udid: "AAAAAAAA-0000-0000-0000-000000000001"), "Sim-A")
        XCTAssertNil(s.poolName(udid: "not-in-pool"))
        XCTAssertEqual(s.poolName(avd: "Emu-A"), "Emu-A")

        let now = Date(timeIntervalSince1970: 1600 + 7 * 60)
        XCTAssertEqual(s.state(of: "Sim-A", now: now), .held(project: "loving-cray", idleMinutes: 7))
        XCTAssertEqual(s.state(of: "Sim-A", now: now).text, "held by loving-cray (idle 7m)")
        XCTAssertEqual(s.state(of: "Sim-B", now: now), .free)
        XCTAssertEqual(s.state(of: "Emu-A", now: now), .reserved)
        XCTAssertEqual(s.summary(now: now), "simq: 1/2 sims held · 0/1 emulators held · 1 queued · 2 pending requests")
    }

    func testBadges() throws {
        let s = try XCTUnwrap(Simq.load(home: fixture))
        XCTAssertEqual(s.badge(pool: nil, running: true)?.0, "Running · outside simq pool")
        XCTAssertNil(s.badge(pool: nil, running: false))
        XCTAssertEqual(s.badge(pool: "Sim-A", running: true)?.0, "simq Sim-A · held")
        XCTAssertEqual(s.badge(pool: "Sim-B", running: false)?.0, "simq Sim-B · free")
    }

    func testGradleUsagePin() throws {
        var scan = ProjectScan()
        scan.simq = try XCTUnwrap(Simq.load(home: fixture))
        XCTAssertEqual(scan.gradleUsage("9.0.0-bin").pinnedBy, "simq")
        XCTAssertNil(scan.gradleUsage("9.8.1-bin").pinnedBy)
        XCTAssertEqual(scan.gradleUsage("9.8.1-bin").badge.0, "Unused")
    }

    func testPendingRequestsDecoded() throws {
        let s = try XCTUnwrap(Simq.load(home: fixture))
        XCTAssertEqual(s.requests.map(\.id), [3, 1])
        XCTAssertEqual(s.pendingRequests, 2)
        let r = s.requests[1]
        XCTAssertEqual(r.type, "command")
        XCTAssertEqual(r.detail, "create sim X")
        XCTAssertEqual(r.reason, "need a spare sim")
        XCTAssertEqual(r.cwd, "/tmp")
        XCTAssertEqual(r.created, Date(timeIntervalSince1970: 1700))
        XCTAssertEqual(s.requests[0].projectName, "nors")
    }

    func testRequestsWithoutIntIDSkipped() throws {
        let policy = Data("{}".utf8)
        let state = Data(#"{"requests":[{"status":"pending","command":"a"},{"id":"x","status":"pending","command":"b"},{"id":5,"status":"pending","command":"c"}]}"#.utf8)
        let s = try XCTUnwrap(Simq.parse(policy: policy, state: state))
        XCTAssertEqual(s.requests.map(\.id), [5])
    }

    func testQueuesDecoded() throws {
        let s = try XCTUnwrap(Simq.load(home: fixture))
        let ios = try XCTUnwrap(s.queues["ios"])
        XCTAssertEqual(ios.count, 1)
        XCTAssertEqual(ios[0].project, "/Users/me/Hacking/NorsCare/nors")
        XCTAssertEqual(ios[0].sessionID, "s-2")
        XCTAssertEqual(s.queued["ios"], 1)
    }

    func testIdle() throws {
        let s = try XCTUnwrap(Simq.load(home: fixture))
        XCTAssertEqual(s.idleMinutesLimit, 45)
        let now = Date(timeIntervalSince1970: 100_000)
        func lease(_ session: String, idleMin: Double) -> Simq.Lease {
            .init(device: "d", kind: "ios", sessionID: session, project: nil, since: nil,
                  lastActivity: now.addingTimeInterval(-idleMin * 60))
        }
        XCTAssertTrue(s.isIdle(lease("s-1", idleMin: 46), now: now))
        XCTAssertFalse(s.isIdle(lease("s-1", idleMin: 44), now: now))
        XCTAssertFalse(s.isIdle(lease("human", idleMin: 500), now: now))
    }

    func testIdleLimitFromPolicy() throws {
        let s = try XCTUnwrap(Simq.parse(policy: Data(#"{"idle_minutes": 10}"#.utf8), state: nil))
        XCTAssertEqual(s.idleMinutesLimit, 10)
    }

    func testHalfWrittenStateKeepsPolicy() throws {
        let policy = try XCTUnwrap(FileManager.default.contents(atPath: fixture + "/policy.json"))
        let s = try XCTUnwrap(Simq.parse(policy: policy, state: Data("{partial".utf8)))
        XCTAssertTrue(s.requests.isEmpty)
        XCTAssertEqual(s.iosRuntime, "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
    }

    func testEnvStripsClaude() {
        let env = ["CLAUDE_CODE_SESSION_ID": "x", "CLAUDE_PID": "1", "HOME": "/h", "SIMQ_NO_SKETCHYBAR": "1"]
        XCTAssertEqual(SimqCLI.environment(from: env), ["HOME": "/h"])
    }

    func testExecutableOverride() {
        XCTAssertEqual(SimqCLI.executable(env: ["SIMQ_BIN": "/x/simq"]), "/x/simq")
        XCTAssertTrue(SimqCLI.executable(env: [:]).hasSuffix("/.local/bin/simq"))
    }

    func testNeedsForce() {
        XCTAssertTrue(SimqCLI.needsForce("only 3.0 GB free, need 9 GB (use --force to override)"))
        XCTAssertFalse(SimqCLI.needsForce("approved #2"))
    }
}
