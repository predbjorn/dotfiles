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

    func testBootedWithoutLeaseIsNotFree() throws {
        var s = try XCTUnwrap(Simq.load(home: fixture))
        let now = Date(timeIntervalSince1970: 1600 + 7 * 60)
        s.booted = ["Sim-B"]
        XCTAssertEqual(s.state(of: "Sim-B", now: now), .booted(leftoverOf: nil))
        XCTAssertEqual(s.state(of: "Sim-B", now: now).text,
                       "booted outside simq · sessions can't take it until it's shut down")
        XCTAssertEqual(s.badge(pool: "Sim-B", running: true)?.0, "simq Sim-B · booted outside simq")
        s.lastHolders = ["Sim-B": "cb1ff49c-deee"]
        XCTAssertEqual(s.state(of: "Sim-B", now: now).text,
                       "booted, no lease · kept for session cb1f… if it resumes")
        s.booted = ["Sim-A"]  // a held device stays held, booted or not
        XCTAssertEqual(s.state(of: "Sim-A", now: now), .held(project: "loving-cray", idleMinutes: 7))
    }

    func testLastHoldersDecoded() throws {
        let policy = try XCTUnwrap(FileManager.default.contents(atPath: fixture + "/policy.json"))
        let s = try XCTUnwrap(Simq.parse(policy: policy, state: Data(#"{"last_holders": {"Sim-B": "s9"}}"#.utf8)))
        XCTAssertEqual(s.lastHolders, ["Sim-B": "s9"])
    }

    func testBootedSimsFromSimctl() {
        let json = #"{"devices": {"rt": [{"udid": "U2", "name": "Sim-B", "state": "Booted"}, {"udid": "X", "name": "Other"}]}}"#
        XCTAssertEqual(Simq.bootedSims(simctlJSON: Data(json.utf8), iosPool: ["Sim-A": "U1", "Sim-B": "U2"]), ["Sim-B"])
        XCTAssertEqual(Simq.bootedSims(simctlJSON: Data("nope".utf8), iosPool: ["Sim-A": "U1"]), [])
    }

    func testRunningEmulatorsFromAdb() {
        let listing = "List of devices attached\nemulator-5554\tdevice\nemulator-5556\toffline\nR58M\tdevice\n"
        XCTAssertEqual(Simq.runningEmulators(adbDevices: listing), ["emulator-5554"])
    }

    func testDeletingPinnedImageWarns() {
        let pinned = SystemImage(path: "/sdk/x", relative: "system-images/android-35/google_apis_playstore/arm64-v8a",
                                 size: 2_000_000_000, usedBy: ["Emu-B"], simqPinned: true)
        let t = DeleteTarget.image(pinned)
        XCTAssertEqual(t.title, "Delete simq's pinned system image android-35 · google_apis_playstore · arm64-v8a?")
        XCTAssertTrue(t.message.hasPrefix(Simq.pinnedDeleteWarning(pool: "emulators")))
        var plain = pinned
        plain.simqPinned = false
        XCTAssertFalse(DeleteTarget.image(plain).message.contains("simq"))
    }

    func testGradleRulesFromPolicy() throws {
        let policy = #"""
        {"ios_runtime": "rt", "android_image": "img", "ios_pool": {}, "android_pool": [],
         "gradle_versions": ["9.3.1", "'9.3.1'", "8.11.1", "9.0.0"],
         "android_paths": {"/h/Hacking/NorsCare/nors": ["android/", "*js*"],
                           "/h/Hacking/projects/tren": ["tren_android/"]}}
        """#
        let s = try XCTUnwrap(Simq.parse(policy: Data(policy.utf8), state: nil))
        XCTAssertEqual(s.allowedGradle, ["9.3.1", "9.0.0", "8.11.1"])
        XCTAssertEqual(s.invalidGradleEntries, ["'9.3.1'"])
        XCTAssertEqual(s.androidPathRows.map(\.repo), ["nors", "tren"])
        XCTAssertEqual(s.androidPathRows[0].paths,
                       "android/, tren_android/, native-android/ + JS changes (src/, app/, *.ts, *.tsx, package.json, app.json, app.config.*)")
        XCTAssertEqual(s.androidPathRows[1].paths, "tren_android/")
        XCTAssertTrue(s.allowsGradle("8.11.1"))
        XCTAssertFalse(s.allowsGradle("9.2.0"))
    }

    func testWrapperRows() throws {
        let s = try XCTUnwrap(Simq.load(home: fixture))
        let c = Checkout(repo: "tren", repoPath: "/h/tren", worktree: nil, path: "/h/tren")
        var scan = ProjectScan()
        scan.gradle = ["8.11.1": [c], "8.11.1-bin": [c], "9.2.0": [c], "10.0": [c]]
        let rows = s.wrapperRows(scan)
        XCTAssertEqual(rows.map(\.version), ["10.0", "9.2.0", "8.11.1"])
        XCTAssertEqual(rows.map(\.allowed), [false, false, true])
        XCTAssertEqual(rows[2].who, "pinned by tren")
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
        XCTAssertEqual(s.requests.map(\.id), [5, 3, 1])
        XCTAssertEqual(s.pendingRequests, 2, "approving requests don't count as pending")
        XCTAssertEqual(s.requests.map(\.status), ["approving", "pending", "pending"])
        XCTAssertTrue(s.requests[0].isApproving)
        XCTAssertEqual(s.requests[0].type, "sdk")
        XCTAssertEqual(s.requests[1].type, "download")
        let r = s.requests[2]
        XCTAssertEqual(r.type, "create")
        XCTAssertEqual(r.detail, "simctl create")
        XCTAssertEqual(r.reason, "need a spare sim")
        XCTAssertEqual(r.cwd, "/tmp")
        XCTAssertEqual(r.created, Date(timeIntervalSince1970: 1700))
        XCTAssertEqual(s.requests[1].projectName, "nors")
    }

    func testApprovingOnlyStateIsNotPending() throws {
        let state = Data(#"{"requests":[{"id":7,"status":"approving","type":"avd","command":"a"},{"id":8,"status":"denied","command":"b"}]}"#.utf8)
        let s = try XCTUnwrap(Simq.parse(policy: Data("{}".utf8), state: state))
        XCTAssertEqual(s.requests.map(\.id), [7])
        XCTAssertEqual(s.pendingRequests, 0)
        XCTAssertFalse(s.summary().contains("pending"))
    }

    func testOnlyDownloadCanPin() {
        let types = ["download", "create", "avd", "sdk", "wrapper", "steal", "delete", "erase-other", "other"]
        let pinnable = types.filter {
            Simq.Request(id: 1, type: $0, project: nil, command: "", detail: nil, reason: nil, cwd: nil, created: nil).canPin
        }
        XCTAssertEqual(pinnable, ["download"])
    }

    func testReleasePrompt() throws {
        let s = try XCTUnwrap(Simq.load(home: fixture))
        let now = Date(timeIntervalSince1970: 100_000)
        func lease(_ session: String, idleMin: Double) -> Simq.Lease {
            .init(device: "Sim-A", kind: "ios", sessionID: session, project: "/x/tren", since: nil,
                  lastActivity: now.addingTimeInterval(-idleMin * 60))
        }
        XCTAssertNil(s.releasePrompt(lease("human", idleMin: 500), now: now), "Preben's own: no dialog")
        XCTAssertEqual(s.releasePrompt(lease("s-1", idleMin: 50), now: now),
                       "Sim-A is held by tren, idle 50m (it may still be running a command). Release?")
        XCTAssertEqual(s.releasePrompt(lease("s-1", idleMin: 3), now: now),
                       "Sim-A is in use by tren (last activity 3m ago). Release anyway?")
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
        let env = ["CLAUDE_CODE_SESSION_ID": "x", "CLAUDE_PID": "1", "CLAUDECODE": "1", "HOME": "/h",
                   "SIMQ_NO_SKETCHYBAR": "1", "CLAUDECODE_X": "kept"]
        XCTAssertEqual(SimqCLI.environment(from: env), ["HOME": "/h", "CLAUDECODE_X": "kept"])
    }

    func testExecutableOverride() {
        XCTAssertEqual(SimqCLI.executable(env: ["SIMQ_BIN": "/x/simq"]), "/x/simq")
        XCTAssertTrue(SimqCLI.executable(env: [:]).hasSuffix("/.local/bin/simq"))
    }

    func testNeedsForce() {
        XCTAssertTrue(SimqCLI.needsForce("only 3.0 GB free, need 9 GB (use --force to override)"))
        XCTAssertFalse(SimqCLI.needsForce("approved #2"))
    }

    @MainActor
    func testActKeepsOutputOnItsRowAndReloads() async throws {
        let old = ProcessInfo.processInfo.environment["SIMQ_BIN"]
        defer { if let old { setenv("SIMQ_BIN", old, 1) } else { unsetenv("SIMQ_BIN") } }

        setenv("SIMQ_BIN", "/bin/echo", 1)
        let model = SimqModel(home: fixture, pollBooted: false)
        XCTAssertEqual(model.simq?.pendingRequests, 2)
        await model.act("req-3", ["approve", "3"])
        XCTAssertEqual(model.rowMessage, ["req-3": "approve 3"])
        XCTAssertEqual(model.lastCommand, "simq approve 3")
        XCTAssertEqual(model.lastResult, "approve 3", "pane-wide result outlives the row")
        XCTAssertFalse(model.running)
        XCTAssertNotNil(model.simq)

        setenv("SIMQ_BIN", "/usr/bin/false", 1)
        await model.act("dev-Sim-A", ["release", "Sim-A"])
        XCTAssertEqual(model.rowMessage["dev-Sim-A"], "Error (exit 1)")
        XCTAssertEqual(model.rowMessage["req-3"], "approve 3")
        XCTAssertEqual(model.lastCommand, "simq release Sim-A")
        XCTAssertEqual(model.lastResult, "Error (exit 1)")
    }

    @MainActor
    func testModelWithoutHomeIsNotSetUp() {
        XCTAssertNil(SimqModel(home: "/nonexistent/simq-\(UUID())", pollBooted: false).simq)
    }

    @MainActor
    func testReloadKeepsLastGoodStateOnBadReads() throws {
        let fm = FileManager.default
        let home = NSTemporaryDirectory() + "simq-\(UUID())"
        try fm.copyItem(atPath: fixture, toPath: home)
        defer { try? fm.removeItem(atPath: home) }

        let model = SimqModel(home: home, pollBooted: false)
        XCTAssertEqual(model.simq?.requests.map(\.id), [5, 3, 1])

        try Data("{partial".utf8).write(to: URL(fileURLWithPath: home + "/state.json"))
        model.reload()
        XCTAssertEqual(model.simq?.requests.map(\.id), [5, 3, 1], "bad state.json keeps the last good state")

        try Data("{partial".utf8).write(to: URL(fileURLWithPath: home + "/policy.json"))
        model.reload()
        XCTAssertEqual(model.simq?.requests.map(\.id), [5, 3, 1], "bad policy.json keeps the last good state")

        try fm.removeItem(atPath: home + "/policy.json")
        model.reload()
        XCTAssertNil(model.simq, "no policy.json means not set up")
    }

    @MainActor
    func testReloadWithoutStateFileIsAllFree() throws {
        let fm = FileManager.default
        let home = NSTemporaryDirectory() + "simq-\(UUID())"
        try fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: home) }
        try fm.copyItem(atPath: fixture + "/policy.json", toPath: home + "/policy.json")
        let model = SimqModel(home: home, pollBooted: false)
        XCTAssertEqual(model.simq?.requests.count, 0)
        XCTAssertEqual(model.simq?.state(of: "Sim-A"), .free)
    }
}
