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
        XCTAssertEqual(s.summary(now: now), "simq: 1/2 sims held · 0/1 emulators held · 1 queued · 1 pending request")
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
}
