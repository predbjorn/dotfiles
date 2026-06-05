# Launch Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Revision note (post structured review):** This plan was revised after a multi-agent design review (Skeptic / Constraint Guardian / User Advocate / Arbiter). The fixes for the 15 accepted objections are folded into the relevant tasks and called out with **[FIX N]** markers. Highest-impact changes: crash detection is now **transition-based and deduplicated** (not derived from the persistent `launchctl list` Status column), the HTTP server **binds to loopback only**, remote exposure is gated by **Cloudflare Access** rather than a bare bearer token, and the secret is **never logged**.

**Goal:** Build a native macOS menu bar app that monitors all user LaunchAgents, auto-restarts crashed ones, sends crash notifications, exposes an authenticated **loopback-only** HTTP API for local/remote control, and is optionally reachable through the user's existing cloudflared tunnel **behind Cloudflare Access**.

**Architecture:** Swift Package Manager executable (no Xcode project). NSStatusItem menu bar app with a SwiftUI popover. A polling `ServiceMonitor` reads `~/Library/LaunchAgents/*.plist` and queries `launchctl` for state; a `CrashTracker` turns successive snapshots into deduplicated crash events; an `AutoRestarter` reacts to crash *transitions* with exponential backoff; a Network.framework HTTP server **bound to 127.0.0.1** exposes JSON routes guarded by a bearer token. All `launchctl` calls and shared mutable state run on a single serial work queue, so the polling timer and HTTP handlers never race. The app installs itself as a LaunchAgent (`com.prebenhafnor.launch-dashboard`, `KeepAlive`) so it survives reboot; it monitors its siblings but **excludes its own label** from the auto-restart loop (launchd's `KeepAlive` recovers it instead).

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSStatusItem/NSPopover), Foundation (Process, PropertyListSerialization), Network.framework (NWListener, loopback-bound), UserNotifications, XCTest. No third-party dependencies. Cloudflared (already installed, tunnel `d21fa304-…`, LaunchAgent label `com.nors.cloudflared`) + Cloudflare Access for optional remote exposure.

---

## File Structure

```
tools/launch-dashboard/
├── Package.swift
├── README.md
├── Sources/
│   └── LaunchDashboard/
│       ├── main.swift                  Entry point, NSApplication wiring
│       ├── AppDelegate.swift           Menu bar lifecycle, ties subsystems together
│       ├── Models/
│       │   ├── ServiceStatus.swift     Codable snapshot of one service
│       │   └── Config.swift            Persisted config (bearer token, port, intervals)
│       ├── Core/
│       │   ├── ProcessRunner.swift     Protocol + real impl for subprocess execution
│       │   ├── PlistScanner.swift      Enumerates ~/Library/LaunchAgents/*.plist
│       │   ├── LaunchctlClient.swift   Wraps launchctl list/print/bootstrap/bootout/kickstart
│       │   ├── ServiceMonitor.swift    Periodic poll, publishes snapshots
│       │   ├── CrashTracker.swift      Transition-based, deduplicated crash detection
│       │   └── AutoRestarter.swift     Tracks crash transitions, schedules restarts with backoff
│       ├── Notifications/
│       │   └── CrashNotifier.swift     UNUserNotificationCenter wrapper
│       ├── HTTP/
│       │   ├── HTTPRequest.swift       Minimal request struct
│       │   ├── HTTPResponse.swift      Minimal response struct
│       │   ├── Router.swift            Path → handler matching
│       │   ├── Auth.swift              Bearer token check (constant-time)
│       │   ├── Routes.swift            Concrete /services/* handlers
│       │   └── HTTPServer.swift        Loopback NWListener, buffered request reads, serial dispatch
│       └── UI/
│           ├── MenuBarController.swift NSStatusItem + NSPopover host
│           └── ServicesView.swift      SwiftUI popover content (legend + error banner)
├── Tests/
│   └── LaunchDashboardTests/
│       ├── ConfigTests.swift
│       ├── PlistScannerTests.swift
│       ├── LaunchctlClientTests.swift
│       ├── ServiceMonitorTests.swift
│       ├── CrashTrackerTests.swift
│       ├── AutoRestarterTests.swift
│       ├── RouterTests.swift
│       ├── AuthTests.swift
│       └── RoutesTests.swift
└── scripts/
    ├── install.sh
    └── com.prebenhafnor.launch-dashboard.plist.template
```

Files that change together live together (HTTP/, Core/, UI/). The `ProcessRunner` protocol lets tests inject fake `launchctl` output without spawning subprocesses.

> **[FIX 1] On `launchctl list` semantics — read before implementing Core/.** The `launchctl list` **Status** column is the *last wait/exit status* of the job, **not** a live health flag: a currently-running daemon (PID present) routinely shows a non-zero Status (e.g. `-9`). Therefore **running-ness is determined solely by PID presence**, and a "crash" is only ever inferred from a **running→stopped transition** observed across two snapshots (see `CrashTracker`, Task 7) — never from the Status column of a single snapshot. Unit-test fixtures below deliberately include a running-with-nonzero-Status row so the tests exercise real-world data.

---

## Task 1: Bootstrap Swift package

**Files:**
- Create: `tools/launch-dashboard/Package.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/main.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/SmokeTests.swift`
- Create: `tools/launch-dashboard/.gitignore`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LaunchDashboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LaunchDashboard"),
        .testTarget(name: "LaunchDashboardTests", dependencies: ["LaunchDashboard"]),
    ]
)
```

- [ ] **Step 2: Create main.swift placeholder**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
print("LaunchDashboard starting")
app.run()
```

- [ ] **Step 3: Create smoke test**

```swift
import XCTest
@testable import LaunchDashboard

final class SmokeTests: XCTestCase {
    func testTrue() { XCTAssertTrue(true) }
}
```

- [ ] **Step 4: Create .gitignore**

```
.build/
.swiftpm/
*.xcodeproj
DerivedData/
```

- [ ] **Step 5: Verify build and test**

Run: `cd tools/launch-dashboard && swift build && swift test`
Expected: Build succeeds, 1 test passes.

- [ ] **Step 6: Commit**

```bash
git add tools/launch-dashboard
git commit -m "feat(launch-dashboard): bootstrap Swift package"
```

---

## Task 2: Config model with persistence

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Models/Config.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/ConfigTests.swift`

> **[FIX 13] Non-destructive load.** A *missing* file → create defaults. A *present but corrupt/unreadable* file → **throw** (do **not** silently mint a new token and overwrite, which would rotate the bearer token and break every existing remote client). **[FIX 6, security]** The file is written with `0600` permissions.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LaunchDashboard

final class ConfigTests: XCTestCase {
    func testLoadMissingFileCreatesDefaultsWithToken() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ld-\(UUID()).json")
        let cfg = try Config.loadOrCreate(at: url)
        XCTAssertEqual(cfg.httpPort, 8765)
        XCTAssertEqual(cfg.pollIntervalSeconds, 5)
        XCTAssertTrue(cfg.autoRestartEnabled)
        XCTAssertEqual(cfg.bearerToken.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // [FIX 6] file must be 0600
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    func testLoadExistingFileRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ld-\(UUID()).json")
        let original = try Config.loadOrCreate(at: url)
        let again = try Config.loadOrCreate(at: url)
        XCTAssertEqual(original.bearerToken, again.bearerToken)
    }

    func testCorruptFileThrowsAndDoesNotRotateToken() throws {
        // [FIX 13] a corrupt file must NOT be silently replaced with a fresh token
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ld-\(UUID()).json")
        try "}{ not json".data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try Config.loadOrCreate(at: url))
        // original bytes are untouched
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "}{ not json")
    }
}
```

- [ ] **Step 2: Run tests and verify they fail to compile**

Run: `swift test --filter ConfigTests`
Expected: Compile error — `Config` not defined.

- [ ] **Step 3: Implement Config**

```swift
import Foundation
import Security

struct Config: Codable {
    var bearerToken: String
    var httpPort: UInt16
    var pollIntervalSeconds: Int
    var autoRestartEnabled: Bool

    static func loadOrCreate(at url: URL) throws -> Config {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        // [FIX 13] Distinguish "missing" (create) from "corrupt/unreadable" (throw).
        if fm.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)              // throws on unreadable
            return try JSONDecoder().decode(Config.self, from: data)  // throws on corrupt — no rotation
        }
        let fresh = Config(
            bearerToken: Self.makeToken(),
            httpPort: 8765,
            pollIntervalSeconds: 5,
            autoRestartEnabled: true
        )
        let data = try JSONEncoder().encode(fresh)
        try data.write(to: url, options: .atomic)
        // [FIX 6] secret at rest is owner-only.
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return fresh
    }

    /// Internal (not private) so AppDelegate can mint an ephemeral token if config is unreadable.
    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // Fail closed: a security daemon that cannot generate randomness must not come up
        // with a guessable (zeroed) token. fatalError keeps the signature non-throwing.
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            fatalError("CSPRNG unavailable; refusing to mint a predictable token")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        return support.appendingPathComponent("LaunchDashboard/config.json")
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run: `swift test --filter ConfigTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Models/Config.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/ConfigTests.swift
git commit -m "feat(launch-dashboard): persistent 0600 config with non-destructive load"
```

---

## Task 3: PlistScanner

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Core/PlistScanner.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/PlistScannerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import LaunchDashboard

final class PlistScannerTests: XCTestCase {
    func testScansLabelsFromDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-scan-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist = dir.appendingPathComponent("com.example.foo.plist")
        let body: [String: Any] = [
            "Label": "com.example.foo",
            "ProgramArguments": ["/bin/echo", "hi"],
            "StandardErrorPath": "/tmp/foo.err"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: body,
                                                      format: .xml, options: 0)
        try data.write(to: plist)

        let scanner = PlistScanner(directory: dir)
        let entries = try scanner.scan()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].label, "com.example.foo")
        XCTAssertEqual(entries[0].plistPath, plist.path)
        XCTAssertEqual(entries[0].stderrPath, "/tmp/foo.err")
    }

    func testIgnoresNonPlistFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-scan-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "junk".write(to: dir.appendingPathComponent("README.txt"),
                         atomically: true, encoding: .utf8)
        let entries = try PlistScanner(directory: dir).scan()
        XCTAssertEqual(entries.count, 0)
    }
}
```

- [ ] **Step 2: Verify tests fail to compile**

Run: `swift test --filter PlistScannerTests`
Expected: Compile error — `PlistScanner` not defined.

- [ ] **Step 3: Implement PlistScanner**

```swift
import Foundation

struct PlistEntry: Equatable {
    let label: String
    let plistPath: String
    let stderrPath: String?
    let stdoutPath: String?
}

struct PlistScanner {
    let directory: URL

    static var userLaunchAgents: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    func scan() throws -> [PlistEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        var out: [PlistEntry] = []
        for name in names where name.hasSuffix(".plist") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let obj = try? PropertyListSerialization.propertyList(
                    from: data, format: nil) as? [String: Any],
                  let label = obj["Label"] as? String
            else { continue }
            out.append(PlistEntry(
                label: label,
                plistPath: url.path,
                stderrPath: obj["StandardErrorPath"] as? String,
                stdoutPath: obj["StandardOutPath"] as? String
            ))
        }
        return out.sorted { $0.label < $1.label }
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `swift test --filter PlistScannerTests`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Core/PlistScanner.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/PlistScannerTests.swift
git commit -m "feat(launch-dashboard): scan LaunchAgents plists"
```

---

## Task 4: ProcessRunner abstraction + LaunchctlClient

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Core/ProcessRunner.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Core/LaunchctlClient.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Models/ServiceStatus.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/LaunchctlClientTests.swift`

- [ ] **Step 1: Define the ServiceStatus model**

```swift
import Foundation

enum ServiceState: String, Codable {
    case running
    case loadedNotRunning
    case notLoaded
    case unknown
}

struct ServiceStatus: Codable, Identifiable, Equatable {
    var id: String { label }
    let label: String
    let state: ServiceState
    let pid: Int?
    /// NOTE: this is launchctl's *last* wait/exit status. It is stale for running jobs and
    /// is only meaningful at a running→stopped transition. Do not treat it as a health flag.
    let lastExitCode: Int?
    let plistPath: String?
}
```

- [ ] **Step 2: Define ProcessRunner protocol + real implementation**

```swift
import Foundation

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

protocol ProcessRunner {
    func run(_ launchPath: String, _ args: [String]) throws -> ProcessResult
}

struct RealProcessRunner: ProcessRunner {
    func run(_ launchPath: String, _ args: [String]) throws -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        try p.run()
        // Read before waitUntilExit to avoid deadlock on pipes that fill their buffer.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return ProcessResult(stdout: out, stderr: err, exitCode: p.terminationStatus)
    }
}
```

- [ ] **Step 3: Write LaunchctlClient tests**

> The `list` fixture below includes `com.example.delta` — **running (PID present) with a non-zero Status `-9`** — to lock in [FIX 1]: a non-zero Status on a live PID must still parse as running, and downstream code must not treat it as a crash.

```swift
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
        // [FIX 1] running process with non-zero Status: PID still parsed, marked running downstream.
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
```

- [ ] **Step 4: Verify tests fail to compile**

Run: `swift test --filter LaunchctlClientTests`
Expected: Compile error — `LaunchctlClient` not defined.

- [ ] **Step 5: Implement LaunchctlClient**

```swift
import Foundation

struct LoadedEntry {
    let pid: Int?
    let lastExitCode: Int?
}

struct LaunchctlClient {
    let runner: ProcessRunner
    let uid: uid_t

    static func makeReal() -> LaunchctlClient {
        LaunchctlClient(runner: RealProcessRunner(), uid: getuid())
    }

    func listLoaded() throws -> [String: LoadedEntry] {
        let result = try runner.run("/bin/launchctl", ["list"])
        var out: [String: LoadedEntry] = [:]
        for line in result.stdout.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t", maxSplits: 2,
                                   omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let pid = Int(parts[0]) // "-" → nil
            let exit = Int(parts[1])
            let label = String(parts[2])
            out[label] = LoadedEntry(pid: pid, lastExitCode: exit)
        }
        return out
    }

    func kickstart(label: String, restart: Bool) throws {
        var args = ["kickstart"]
        if restart { args.append("-k") }
        args.append("gui/\(uid)/\(label)")
        let r = try runner.run("/bin/launchctl", args)
        if r.exitCode != 0 { throw LaunchctlError.commandFailed(r.stderr) }
    }

    func bootstrap(plistPath: String) throws {
        let r = try runner.run("/bin/launchctl",
                               ["bootstrap", "gui/\(uid)", plistPath])
        if r.exitCode != 0 { throw LaunchctlError.commandFailed(r.stderr) }
    }

    func bootout(label: String) throws {
        let r = try runner.run("/bin/launchctl",
                               ["bootout", "gui/\(uid)/\(label)"])
        if r.exitCode != 0 { throw LaunchctlError.commandFailed(r.stderr) }
    }
}

enum LaunchctlError: Error {
    case commandFailed(String)
}
```

- [ ] **Step 6: Verify tests pass**

Run: `swift test --filter LaunchctlClientTests`
Expected: 4 tests pass.

- [ ] **Step 7: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Core/ProcessRunner.swift \
        tools/launch-dashboard/Sources/LaunchDashboard/Core/LaunchctlClient.swift \
        tools/launch-dashboard/Sources/LaunchDashboard/Models/ServiceStatus.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/LaunchctlClientTests.swift
git commit -m "feat(launch-dashboard): launchctl wrapper with mockable process runner"
```

---

## Task 5: ServiceMonitor

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Core/ServiceMonitor.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/ServiceMonitorTests.swift`

> **[FIX 1]** `running` is determined **only** by PID presence. The `delta` row below (running with Status `-9`) must come back `.running`, proving a non-zero Status never demotes a live job.

- [ ] **Step 1: Write the failing tests**

```swift
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
        // [FIX 1] live PID + non-zero Status is still RUNNING, not a crash.
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
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter ServiceMonitorTests`
Expected: Compile error — `ServiceMonitor` not defined.

- [ ] **Step 3: Implement ServiceMonitor**

```swift
import Foundation

final class ServiceMonitor {
    let scanner: PlistScanner
    let client: LaunchctlClient

    init(scanner: PlistScanner, client: LaunchctlClient) {
        self.scanner = scanner
        self.client = client
    }

    func snapshot() throws -> [ServiceStatus] {
        let entries = try scanner.scan()
        let loaded = try client.listLoaded()
        return entries.map { entry in
            if let live = loaded[entry.label] {
                // [FIX 1] running iff a PID exists; Status column never decides this.
                let state: ServiceState = live.pid != nil ? .running : .loadedNotRunning
                return ServiceStatus(
                    label: entry.label, state: state, pid: live.pid,
                    lastExitCode: live.lastExitCode, plistPath: entry.plistPath
                )
            }
            return ServiceStatus(
                label: entry.label, state: .notLoaded, pid: nil,
                lastExitCode: nil, plistPath: entry.plistPath
            )
        }
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `swift test --filter ServiceMonitorTests`
Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Core/ServiceMonitor.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/ServiceMonitorTests.swift
git commit -m "feat(launch-dashboard): join plist scan with launchctl state into snapshot"
```

---

## Task 6: AutoRestarter with exponential backoff

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Core/AutoRestarter.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/AutoRestarterTests.swift`

> **[FIX 12] Self-exclusion.** `AutoRestarter` takes an optional `ownLabel` and never restarts it — the dashboard's own recovery is delegated to launchd `KeepAlive`, preventing it from `kickstart -k`-ing itself.
> **[FIX 10] Thread safety.** All `observe(_:)` calls happen on the single serial work queue (Task 11), so the mutable `tracks` dictionary is never touched concurrently. This is a documented invariant, not an internal lock.

- [ ] **Step 1: Write the failing tests**

```swift
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
        // [FIX 12] the dashboard never auto-restarts itself.
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

    func testSecondCrashRestartsAfterBackoffWindow() {
        var time: TimeInterval = 0
        var kicks: [String] = []
        let restarter = AutoRestarter(now: { time }, restart: { kicks.append($0) })
        let running = ServiceStatus(label: "a", state: .running, pid: 1, lastExitCode: 0, plistPath: nil)
        let crashed = ServiceStatus(label: "a", state: .loadedNotRunning, pid: nil, lastExitCode: 1, plistPath: nil)
        restarter.observe([running])
        restarter.observe([crashed])      // kick #1 at t=0, backoff -> 2
        time = 3                          // past the 2s window
        restarter.observe([running])
        restarter.observe([crashed])      // kick #2 at t=3 (gate 3 >= 2)
        XCTAssertEqual(kicks, ["a", "a"])
    }

    func testSlowRecoveryDoesNotPrematurelyResetBackoff() {
        // Regression: a service that recovers slowly must NOT have its backoff reset on the
        // first running poll. With the old (lastRestartAt-keyed) reset this produced 3 kicks.
        var time: TimeInterval = 0
        var kicks: [String] = []
        let restarter = AutoRestarter(now: { time }, restart: { kicks.append($0) })
        let running = ServiceStatus(label: "a", state: .running, pid: 1, lastExitCode: 0, plistPath: nil)
        let crashed = ServiceStatus(label: "a", state: .loadedNotRunning, pid: nil, lastExitCode: 1, plistPath: nil)
        restarter.observe([running])
        restarter.observe([crashed])      // kick #1 at t=0, backoff -> 2
        time = 70                         // stayed crashed a long time, only now recovers
        restarter.observe([running])      // runningSince = 70; must NOT reset backoff (still 2)
        time = 70.5
        restarter.observe([crashed])      // kick #2; backoff -> 4
        time = 71
        restarter.observe([running])
        time = 73                         // 2.5s since kick #2: < 4 (fixed) but >= 2 (buggy)
        restarter.observe([crashed])      // must be SKIPPED with the fix
        XCTAssertEqual(kicks, ["a", "a"])
    }
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter AutoRestarterTests`
Expected: Compile error.

- [ ] **Step 3: Implement AutoRestarter**

```swift
import Foundation

final class AutoRestarter {
    private struct Track {
        var lastRunning: Bool
        var lastRestartAt: TimeInterval
        var backoffSeconds: TimeInterval
        var runningSince: TimeInterval   // when it most recently transitioned into running
    }
    private var tracks: [String: Track] = [:]
    private let now: () -> TimeInterval
    private let restart: (String) -> Void
    private let ownLabel: String?
    private let maxBackoff: TimeInterval = 300

    init(now: @escaping () -> TimeInterval,
         restart: @escaping (String) -> Void,
         ownLabel: String? = nil) {
        self.now = now
        self.restart = restart
        self.ownLabel = ownLabel
    }

    /// Precondition: called only on the serial work queue (see AppDelegate). [FIX 10]
    func observe(_ statuses: [ServiceStatus]) {
        for s in statuses where s.label != ownLabel {   // [FIX 12]
            var t = tracks[s.label] ?? Track(lastRunning: false,
                                             lastRestartAt: -.infinity,
                                             backoffSeconds: 1,
                                             runningSince: -.infinity)
            let isRunning = (s.state == .running)
            // Crash = running→stopped transition with a non-zero exit recorded at that moment.
            let crashed = t.lastRunning && !isRunning && (s.lastExitCode ?? 0) != 0
            if crashed, now() - t.lastRestartAt >= t.backoffSeconds {
                restart(s.label)
                t.lastRestartAt = now()
                t.backoffSeconds = min(t.backoffSeconds * 2, maxBackoff)
            }
            // Record when the service most recently became running.
            if isRunning && !t.lastRunning {
                t.runningSince = now()
            }
            // Reset backoff only after it has been stably running for a while —
            // keyed off when it became running, NOT off lastRestartAt (else a slow
            // recovery would reset backoff on its first running poll).
            if isRunning, now() - t.runningSince > 60 {
                t.backoffSeconds = 1
            }
            t.lastRunning = isRunning
            tracks[s.label] = t
        }
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `swift test --filter AutoRestarterTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Core/AutoRestarter.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/AutoRestarterTests.swift
git commit -m "feat(launch-dashboard): auto-restart crashed services with backoff, self-excluded"
```

---

## Task 7: CrashTracker + CrashNotifier

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Core/CrashTracker.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/CrashTrackerTests.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Notifications/CrashNotifier.swift`

> **[FIX 1 + FIX 4] This task replaces the old "recompute `failed` from the Status column every poll and notify" logic.** `CrashTracker` consumes successive snapshots and:
> - emits a crash **event** exactly once per crash, on the running→stopped transition (deduplicated by a "currently crashed" set);
> - exposes the **currently-crashed set** for the badge and red dots (so the badge reflects real crashes, not stale exit codes);
> - re-arms after recovery, so a *new* crash of the same service notifies again;
> - **does not** emit for services already stopped at first sight (no startup storm).
>
> This is unit-tested (the old approach was untestable and falsely green).

- [ ] **Step 1: Write the failing CrashTracker tests**

```swift
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
        // same crashed state again → no duplicate event ([FIX 4])
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
        // first sighting is stopped+nonzero — no prior "running", so no transition.
        XCTAssertTrue(t.update([status("a", .loadedNotRunning, exit: 1)]).isEmpty)
        XCTAssertTrue(t.crashed.isEmpty)
    }
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter CrashTrackerTests`
Expected: Compile error — `CrashTracker` not defined.

- [ ] **Step 3: Implement CrashTracker**

```swift
import Foundation

final class CrashTracker {
    struct Event: Equatable { let label: String; let exitCode: Int? }

    private var running: [String: Bool] = [:]
    private(set) var crashed: Set<String> = []

    /// Precondition: called only on the serial work queue (see AppDelegate). [FIX 10]
    /// Returns labels that *newly* crashed this tick (running→stopped, non-zero exit).
    func update(_ statuses: [ServiceStatus]) -> [Event] {
        var events: [Event] = []
        for s in statuses {
            let isRunning = (s.state == .running)
            // First sighting: seed prior state with the current one so there is no phantom transition.
            let wasRunning = running[s.label] ?? isRunning
            let crashedNow = wasRunning && !isRunning && (s.lastExitCode ?? 0) != 0
            if crashedNow, !crashed.contains(s.label) {
                crashed.insert(s.label)
                events.append(Event(label: s.label, exitCode: s.lastExitCode))
            }
            if isRunning { crashed.remove(s.label) }   // recovery re-arms
            running[s.label] = isRunning
        }
        return events
    }
}
```

- [ ] **Step 4: Verify CrashTracker tests pass**

Run: `swift test --filter CrashTrackerTests`
Expected: 4 tests pass.

- [ ] **Step 5: Implement CrashNotifier**

> **[FIX 7] Authorization gating.** `requestAuthorization` now reports the grant result via completion so the caller can withhold `notifyCrash` until the user has answered the prompt (early crashes are no longer silently dropped — they wait for authorization, then fire on the next transition).

```swift
import Foundation
import UserNotifications

final class CrashNotifier {
    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]) { granted, _ in completion(granted) }
    }

    func notifyCrash(label: String, exitCode: Int?) {
        let content = UNMutableNotificationContent()
        content.title = "LaunchAgent crashed"
        content.body = "\(label) exited with code \(exitCode.map(String.init) ?? "?")"
        content.sound = .default
        // Stable identifier per label: a still-crashed service won't pile up duplicates even
        // if a future caller re-sends. Dedup is primarily enforced by CrashTracker. [FIX 4]
        let req = UNNotificationRequest(identifier: "crash-\(label)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
```

- [ ] **Step 6: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Core/CrashTracker.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/CrashTrackerTests.swift \
        tools/launch-dashboard/Sources/LaunchDashboard/Notifications/CrashNotifier.swift
git commit -m "feat(launch-dashboard): deduplicated transition-based crash detection + notifier"
```

---

## Task 8: HTTP request/response, router, auth

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/HTTPRequest.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/HTTPResponse.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Router.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Auth.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/RouterTests.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/AuthTests.swift`

- [ ] **Step 1: Define HTTPRequest and HTTPResponse**

```swift
// HTTPRequest.swift
import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}
```

```swift
// HTTPResponse.swift
import Foundation

struct HTTPResponse {
    let status: Int
    let headers: [String: String]
    let body: Data

    static func json(_ status: Int, _ object: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
        return HTTPResponse(status: status,
                            headers: ["Content-Type": "application/json"],
                            body: data)
    }

    static func text(_ status: Int, _ string: String) -> HTTPResponse {
        HTTPResponse(status: status,
                     headers: ["Content-Type": "text/plain; charset=utf-8"],
                     body: Data(string.utf8))
    }
}
```

- [ ] **Step 2: Write Router tests**

```swift
import XCTest
@testable import LaunchDashboard

final class RouterTests: XCTestCase {
    func testMatchesExactPath() {
        let router = Router()
        router.add("GET", "/services") { _, _ in .text(200, "list") }
        let req = HTTPRequest(method: "GET", path: "/services",
                              headers: [:], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        XCTAssertEqual(String(data: resp.body, encoding: .utf8), "list")
    }

    func testCapturesPathParam() {
        let router = Router()
        router.add("POST", "/services/:label/start") { _, params in
            .text(200, params["label"] ?? "")
        }
        let req = HTTPRequest(method: "POST", path: "/services/com.example.foo/start",
                              headers: [:], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(String(data: resp.body, encoding: .utf8), "com.example.foo")
    }

    func testReturns404OnMiss() {
        let router = Router()
        let req = HTTPRequest(method: "GET", path: "/nope", headers: [:], body: Data())
        XCTAssertEqual(router.handle(req).status, 404)
    }
}
```

- [ ] **Step 3: Implement Router**

```swift
import Foundation

final class Router {
    typealias Handler = (HTTPRequest, [String: String]) -> HTTPResponse
    private struct Route {
        let method: String
        let segments: [String]
        let handler: Handler
    }
    private var routes: [Route] = []

    func add(_ method: String, _ pattern: String, _ handler: @escaping Handler) {
        let segs = pattern.split(separator: "/").map(String.init)
        routes.append(Route(method: method, segments: segs, handler: handler))
    }

    func handle(_ req: HTTPRequest) -> HTTPResponse {
        let reqSegs = req.path.split(separator: "/").map(String.init)
        for r in routes where r.method == req.method && r.segments.count == reqSegs.count {
            var params: [String: String] = [:]
            var ok = true
            for (a, b) in zip(r.segments, reqSegs) {
                if a.hasPrefix(":") {
                    params[String(a.dropFirst())] = b
                } else if a != b {
                    ok = false; break
                }
            }
            if ok { return r.handler(req, params) }
        }
        return .text(404, "not found")
    }
}
```

- [ ] **Step 4: Write Auth tests**

```swift
import XCTest
@testable import LaunchDashboard

final class AuthTests: XCTestCase {
    func testAcceptsValidBearer() {
        let req = HTTPRequest(method: "GET", path: "/x",
                              headers: ["Authorization": "Bearer abc123"], body: Data())
        XCTAssertTrue(Auth.allows(req, expected: "abc123"))
    }
    func testRejectsMissingHeader() {
        let req = HTTPRequest(method: "GET", path: "/x", headers: [:], body: Data())
        XCTAssertFalse(Auth.allows(req, expected: "abc123"))
    }
    func testRejectsWrongToken() {
        let req = HTTPRequest(method: "GET", path: "/x",
                              headers: ["Authorization": "Bearer wrong"], body: Data())
        XCTAssertFalse(Auth.allows(req, expected: "abc123"))
    }
}
```

- [ ] **Step 5: Implement Auth**

```swift
import Foundation

enum Auth {
    static func allows(_ req: HTTPRequest, expected: String) -> Bool {
        guard let header = req.headers["Authorization"] ?? req.headers["authorization"]
        else { return false }
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return constantTimeEquals(String(parts[1]), expected)
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        if ab.count != bb.count { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }
}
```

- [ ] **Step 6: Verify all tests pass**

Run: `swift test --filter "RouterTests|AuthTests"`
Expected: 6 tests pass.

- [ ] **Step 7: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/HTTP \
        tools/launch-dashboard/Tests/LaunchDashboardTests/RouterTests.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/AuthTests.swift
git commit -m "feat(launch-dashboard): HTTP router and bearer-token auth"
```

---

## Task 9: HTTP service routes

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Routes.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/RoutesTests.swift`

> **[FIX 8] `/start` no longer 500s on a not-loaded service** — it bootstraps from the plist first if the label isn't in the domain, then kickstarts.
> **[FIX 11] `/logs` path confinement** — the file is served only if its resolved path sits under an allowlist of standard log locations (`~/Library/Logs`, `/tmp`, `/var/log`); otherwise `403`. This blocks a malicious plist from pointing `StandardErrorPath` at `~/.ssh/id_ed25519` and exfiltrating it.

- [ ] **Step 1: Write Routes tests**

```swift
import XCTest
@testable import LaunchDashboard

final class RoutesTests: XCTestCase {
    func testListServicesReturnsSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-routes-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body: [String: Any] = ["Label": "com.example.foo",
                                   "ProgramArguments": ["/bin/true"]]
        let data = try PropertyListSerialization.data(fromPropertyList: body,
                                                      format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("com.example.foo.plist"))

        let fake = FakeRunner()
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor,
                        client: monitor.client, token: "tok")

        let req = HTTPRequest(method: "GET", path: "/services",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        let obj = try JSONSerialization.jsonObject(with: resp.body) as? [[String: Any]]
        XCTAssertEqual(obj?.first?["label"] as? String, "com.example.foo")
    }

    func testRestartTriggersKickstartK() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-routes-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fake = FakeRunner()
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor,
                        client: monitor.client, token: "tok")

        let req = HTTPRequest(method: "POST",
                              path: "/services/com.example.foo/restart",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        XCTAssertEqual(fake.calls.last?.1,
                       ["kickstart", "-k", "gui/501/com.example.foo"])
    }

    func testStartBootstrapsWhenNotLoaded() throws {
        // [FIX 8] not in `launchctl list` → bootstrap from plist, then kickstart (no 500).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-routes-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body: [String: Any] = ["Label": "com.example.foo", "ProgramArguments": ["/bin/true"]]
        let data = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        let plistURL = dir.appendingPathComponent("com.example.foo.plist")
        try data.write(to: plistURL)

        let fake = FakeRunner()   // empty `launchctl list` → service not loaded
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor, client: monitor.client, token: "tok")

        let req = HTTPRequest(method: "POST", path: "/services/com.example.foo/start",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        let cmds = fake.calls.map(\.1)
        XCTAssertTrue(cmds.contains(["bootstrap", "gui/501", plistURL.path]))
        XCTAssertTrue(cmds.contains(["kickstart", "gui/501/com.example.foo"]))
    }

    func testLogsRejectsPathOutsideAllowlist() throws {
        // [FIX 11] a plist pointing StandardErrorPath at a secret is refused with 403.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-routes-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let secret = dir.appendingPathComponent("id_ed25519")
        try "PRIVATE KEY".write(to: secret, atomically: true, encoding: .utf8)
        let body: [String: Any] = ["Label": "com.evil.foo",
                                   "ProgramArguments": ["/bin/true"],
                                   "StandardErrorPath": secret.path]   // not under allowlist
        let data = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
        try data.write(to: dir.appendingPathComponent("com.evil.foo.plist"))

        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: FakeRunner(), uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor, client: monitor.client, token: "tok")

        let req = HTTPRequest(method: "GET", path: "/services/com.evil.foo/logs",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        XCTAssertEqual(router.handle(req).status, 403)
    }

    func testUnauthorizedReturns401() {
        let dir = FileManager.default.temporaryDirectory
        let fake = FakeRunner()
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor,
                        client: monitor.client, token: "tok")
        let req = HTTPRequest(method: "GET", path: "/services",
                              headers: [:], body: Data())
        XCTAssertEqual(router.handle(req).status, 401)
    }
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter RoutesTests`
Expected: Compile error — `Routes` not defined.

- [ ] **Step 3: Implement Routes**

```swift
import Foundation

enum Routes {
    static func register(router: Router,
                         monitor: ServiceMonitor,
                         client: LaunchctlClient,
                         token: String) {
        let guarded: (@escaping (HTTPRequest, [String: String]) -> HTTPResponse)
                  -> (HTTPRequest, [String: String]) -> HTTPResponse = { handler in
            return { req, params in
                guard Auth.allows(req, expected: token) else {
                    return .text(401, "unauthorized")
                }
                return handler(req, params)
            }
        }

        router.add("GET", "/services", guarded { _, _ in
            do {
                let snap = try monitor.snapshot()
                let arr = try JSONSerialization.jsonObject(
                    with: try JSONEncoder().encode(snap)) as? [Any] ?? []
                return .json(200, arr)
            } catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        // [FIX 8] Ensure the job is in the domain before kickstart; bootstrap from plist if not.
        router.add("POST", "/services/:label/start", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do {
                let loaded = try client.listLoaded()
                if loaded[label] == nil {
                    guard let entry = try monitor.scanner.scan().first(where: { $0.label == label })
                    else { return .text(404, "no plist for label") }
                    try client.bootstrap(plistPath: entry.plistPath)
                }
                try client.kickstart(label: label, restart: false)
                return .text(200, "ok")
            } catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        router.add("POST", "/services/:label/stop", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do { try client.bootout(label: label); return .text(200, "ok") }
            catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        router.add("POST", "/services/:label/restart", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do { try client.kickstart(label: label, restart: true); return .text(200, "ok") }
            catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        router.add("GET", "/services/:label/logs", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do {
                let entries = try monitor.scanner.scan()
                guard let entry = entries.first(where: { $0.label == label }),
                      let path = entry.stderrPath
                else { return .text(404, "no log") }
                // [FIX 11] confine to standard log locations; read the RESOLVED path to avoid a
                // check-then-read double-resolution (TOCTOU) on a symlinked StandardErrorPath.
                guard let resolved = resolvedAllowedLogPath(path) else { return .text(403, "log path not allowed") }
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: resolved))
                else { return .text(404, "no log") }
                let tail = String(data: data.suffix(16_384), encoding: .utf8) ?? ""
                return .text(200, tail)
            } catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })

        router.add("POST", "/services/:label/load", guarded { _, params in
            guard let label = params["label"] else { return .text(400, "missing label") }
            do {
                let entries = try monitor.scanner.scan()
                guard let entry = entries.first(where: { $0.label == label })
                else { return .text(404, "no plist") }
                try client.bootstrap(plistPath: entry.plistPath)
                return .text(200, "ok")
            } catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })
    }

    /// [FIX 11] Returns the resolved real path IF it is under a known log directory, else nil.
    /// The caller reads the RESOLVED path (not the original), closing the check-then-read
    /// TOCTOU on a symlinked StandardErrorPath.
    static func resolvedAllowedLogPath(_ path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let prefixes = ["\(home)/Library/Logs/", "/tmp/", "/private/tmp/", "/var/log/"]
        return prefixes.contains { resolved.hasPrefix($0) } ? resolved : nil
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run: `swift test --filter RoutesTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Routes.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/RoutesTests.swift
git commit -m "feat(launch-dashboard): /services routes with start-bootstrap and log-path confinement"
```

---

## Task 10: HTTPServer (Network.framework, loopback-only)

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/HTTPServer.swift`
- Create: `tools/launch-dashboard/Tests/LaunchDashboardTests/HTTPServerParseTests.swift`

This is integration code wrapping NWListener — the socket layer is build-verified plus a live loopback smoke test (Task 12); the request **parser** is extracted as a pure `static func parse(_:) -> ParseOutcome` and unit-tested.

> **Implementation deltas (applied during build, vs. the reference code below):**
> - The request parser is a pure, `static`, unit-tested `parse(_ data: Data) -> ParseOutcome` (nested `enum ParseOutcome { complete(HTTPRequest); incomplete; invalid }`), with 6 tests in `HTTPServerParseTests.swift`.
> - `parse` strips any `?query`/`#fragment` from the target before building `path` (flagged by the Task 8 review — otherwise `/services?x=1` would 404).
> - `parse` returns `.invalid` for a present-but-unparseable or negative `Content-Length`.
> - Each connection has a 10s slowloris/idle timeout (`DispatchWorkItem { conn.cancel() }` scheduled on accept, cancelled on every terminal path) so a stalled client can't pin a connection forever.

> **[FIX 2] Loopback binding.** The listener sets `requiredLocalEndpoint = 127.0.0.1:<port>`, so it binds **only** to loopback (not `0.0.0.0`). cloudflared connects to `127.0.0.1` on the same host, so the tunnel still works; the API is unreachable from the LAN.
> **[FIX 9] Buffered, bounded request reads.** The server accumulates bytes across multiple `receive` callbacks until the headers terminator **and** the full `Content-Length` body have arrived, rejecting requests over a hard size cap (`413`) and malformed ones (`400`). It no longer assumes a single packet contains the whole request.
> **[FIX 10] Serial dispatch.** `router.handle` runs on a caller-supplied serial work queue (shared with the poll loop), so HTTP handlers and polling never touch launchctl/shared state concurrently.

- [ ] **Step 1: Implement HTTPServer**

```swift
import Foundation
import Network

final class HTTPServer {
    private let router: Router
    private let port: UInt16
    private let workQueue: DispatchQueue
    private let maxRequestBytes = 256 * 1024
    private var listener: NWListener?

    init(router: Router, port: UInt16, workQueue: DispatchQueue) {
        self.router = router
        self.port = port
        self.workQueue = workQueue
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // [FIX 2] bind to loopback only.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                  port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global())
            self?.receiveLoop(conn, accumulated: Data())
        }
        listener.start(queue: .global())
        self.listener = listener
    }

    // [FIX 9] keep reading until a full request is buffered (or limits are hit).
    private func receiveLoop(_ conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if buffer.count > self.maxRequestBytes {
                self.send(conn, .text(413, "request too large")); return
            }
            switch self.tryParse(buffer) {
            case .complete(let req):
                self.workQueue.async {
                    let resp = self.router.handle(req)
                    self.send(conn, resp)
                }
            case .invalid:
                self.send(conn, .text(400, "bad request"))
            case .incomplete:
                if isComplete || error != nil { conn.cancel() }
                else { self.receiveLoop(conn, accumulated: buffer) }
            }
        }
    }

    private enum ParseState { case complete(HTTPRequest); case incomplete; case invalid }

    private func tryParse(_ data: Data) -> ParseState {
        // Find header/body separator.
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        let headData = data.subdata(in: data.startIndex..<range.lowerBound)
        guard let head = String(data: headData, encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid }
        let bits = requestLine.split(separator: " ")
        guard bits.count >= 2 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let idx = line.firstIndex(of: ":") {
                let k = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }

        let bodyStart = range.upperBound
        let available = data.subdata(in: bodyStart..<data.endIndex)
        let expected = headers.first { $0.key.lowercased() == "content-length" }
            .flatMap { Int($0.value) } ?? 0
        if available.count < expected { return .incomplete }   // wait for the rest of the body
        let body = expected > 0 ? available.prefix(expected) : Data()

        return .complete(HTTPRequest(method: String(bits[0]), path: String(bits[1]),
                                     headers: headers, body: Data(body)))
    }

    private func send(_ conn: NWConnection, _ resp: HTTPResponse) {
        conn.send(content: serialize(resp),
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    private func serialize(_ resp: HTTPResponse) -> Data {
        var head = "HTTP/1.1 \(resp.status) \(reason(resp.status))\r\n"
        var headers = resp.headers
        headers["Content-Length"] = String(resp.body.count)
        headers["Connection"] = "close"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + resp.body
    }

    private func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Manual smoke test of loopback-only binding**

After Task 11 wires the server, confirm [FIX 2] holds: from another host on the LAN (or `curl` to this Mac's LAN IP) the port must be **refused/unreachable**, while `127.0.0.1` works.

```bash
# From this Mac — should connect:
nc -z 127.0.0.1 8765 && echo "loopback: open"
# From this Mac against its own LAN IP — should be refused (proves not bound to 0.0.0.0):
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
if [ -n "$LAN_IP" ]; then
  nc -z -G1 "$LAN_IP" 8765 && echo "LAN: OPEN (BUG)" || echo "LAN: refused (correct)"
else
  echo "no LAN IP found; skipping LAN check"
fi
```

Expected: `loopback: open` and `LAN: refused (correct)`.

- [ ] **Step 4: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/HTTP/HTTPServer.swift
git commit -m "feat(launch-dashboard): loopback NWListener with buffered request parsing"
```

---

## Task 11: Menu bar UI + app wiring

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/UI/MenuBarController.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/UI/ServicesView.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/AppDelegate.swift`
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/main.swift`

UI is verified manually by running the app.

> **Fixes applied here:** **[FIX 4]** badge + notifications driven by `CrashTracker` (dedup, no storm); **[FIX 5]** the bearer token is **never** logged; **[FIX 6]** an unreadable config yields an **ephemeral random** token (not a guessable constant) and the server still starts loopback-only; **[FIX 7]** notifications wait for authorization; **[FIX 10]** a single serial `workQueue` serializes all launchctl/shared-state access; **[FIX 14]** crashed services render **red** with a visible legend and human-readable state labels; **[FIX 6-UX]** UI actions surface failures in an error banner instead of swallowing them with `try?`.

- [ ] **Step 1: Implement ServicesView**

```swift
import SwiftUI

final class ServicesViewModel: ObservableObject {
    @Published var services: [ServiceStatus] = []
    @Published var crashed: Set<String> = []     // [FIX 14] currently-crashed labels → red
    @Published var lastError: String?            // [FIX 6-UX] surfaced action failures
}

struct ServicesView: View {
    @ObservedObject var vm: ServicesViewModel
    let onStart: (String) -> Void
    let onStop: (String) -> Void
    let onRestart: (String) -> Void
    let onLoad: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LaunchAgents (\(vm.services.count))")
                .font(.headline).padding(8)
            Divider()

            if let err = vm.lastError {           // [FIX 6-UX] error banner
                Text(err)
                    .font(.caption).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red)
            }

            ScrollView {
                ForEach(vm.services) { s in
                    HStack {
                        Circle().fill(color(for: s)).frame(width: 8, height: 8)
                        VStack(alignment: .leading) {
                            Text(s.label).font(.system(.body, design: .monospaced))
                            Text(detail(for: s)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu("⋯") {
                            if s.state == .notLoaded { Button("Load") { onLoad(s.label) } }
                            if s.state != .running { Button("Start") { onStart(s.label) } }
                            if s.state == .running { Button("Stop") { onStop(s.label) } }
                            Button("Restart") { onRestart(s.label) }
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 28)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    Divider()
                }
            }

            Divider()
            legend                                 // [FIX 14] visible color key
        }
        .frame(width: 420, height: 480)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(.green, "Running")
            legendDot(.red, "Crashed")
            legendDot(.yellow, "Stopped")
            legendDot(.gray, "Not loaded")
        }
        .font(.caption2).foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 7, height: 7); Text(label) }
    }

    // [FIX 14] crashed → red (overrides state color); colors now match the legend.
    private func color(for s: ServiceStatus) -> Color {
        if vm.crashed.contains(s.label) { return .red }
        switch s.state {
        case .running: return .green
        case .loadedNotRunning: return .yellow
        case .notLoaded: return .gray
        case .unknown: return .orange
        }
    }

    private func humanState(_ s: ServiceStatus) -> String {
        if vm.crashed.contains(s.label) { return "Crashed" }
        switch s.state {
        case .running: return "Running"
        case .loadedNotRunning: return "Stopped"
        case .notLoaded: return "Not loaded"
        case .unknown: return "Unknown"
        }
    }

    private func detail(for s: ServiceStatus) -> String {
        var bits: [String] = [humanState(s)]      // [FIX 14] human label, not raw enum
        if let pid = s.pid { bits.append("pid \(pid)") }
        if let code = s.lastExitCode { bits.append("last exit \(code)") }
        return bits.joined(separator: " · ")
    }
}
```

- [ ] **Step 2: Implement MenuBarController**

```swift
import AppKit
import SwiftUI

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    let vm = ServicesViewModel()

    init(onStart: @escaping (String) -> Void,
         onStop: @escaping (String) -> Void,
         onRestart: @escaping (String) -> Void,
         onLoad: @escaping (String) -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 480)
        popover.contentViewController = NSHostingController(
            rootView: ServicesView(vm: vm,
                                   onStart: onStart, onStop: onStop,
                                   onRestart: onRestart, onLoad: onLoad))
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent",
                                           accessibilityDescription: nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    func updateBadge(failedCount: Int) {
        statusItem.button?.title = failedCount > 0 ? " \(failedCount)" : ""
    }
}
```

- [ ] **Step 3: Implement AppDelegate**

```swift
import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let ownLabel = "com.prebenhafnor.launch-dashboard"

    private var menuBar: MenuBarController!
    private var server: HTTPServer!
    private var timer: Timer?
    private let monitor: ServiceMonitor
    private let client: LaunchctlClient
    private let restarter: AutoRestarter
    private let crashTracker = CrashTracker()
    private let notifier = CrashNotifier()
    private let config: Config
    private let serverEnabled: Bool
    private var notificationsAuthorized = false
    // [FIX 10] one serial queue serializes ALL launchctl + shared-state access.
    private let workQueue = DispatchQueue(label: "com.prebenhafnor.launch-dashboard.work")

    override init() {
        // [FIX 6] Missing config → create. Unreadable/corrupt → ephemeral RANDOM token (never a
        // guessable constant), and we still bind loopback-only so the blast radius is local.
        let loaded = try? Config.loadOrCreate(at: Config.defaultURL)
        if loaded == nil {
            NSLog("LaunchDashboard: config unreadable; using an ephemeral in-memory token for this run")
        }
        self.config = loaded ?? Config(bearerToken: Config.makeToken(), httpPort: 8765,
                                       pollIntervalSeconds: 5, autoRestartEnabled: false)
        self.serverEnabled = true
        let client = LaunchctlClient.makeReal()
        self.client = client
        self.monitor = ServiceMonitor(
            scanner: PlistScanner(directory: PlistScanner.userLaunchAgents),
            client: client
        )
        self.restarter = AutoRestarter(
            now: { Date().timeIntervalSince1970 },
            restart: { label in try? client.kickstart(label: label, restart: true) },
            ownLabel: AppDelegate.ownLabel     // [FIX 12]
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The action closure receives the non-optional `self`, so `$0.foo()` returns Void
        // (avoids the `Void?` of optional-chained `self?.foo()` and the wrong-scope `$0` label).
        menuBar = MenuBarController(
            onStart:   { [weak self] label in self?.run { try $0.startService(label) } },
            onStop:    { [weak self] label in self?.run { try $0.client.bootout(label: label) } },
            onRestart: { [weak self] label in self?.run { try $0.client.kickstart(label: label, restart: true) } },
            onLoad:    { [weak self] label in self?.run { try $0.loadService(label) } }
        )

        // [FIX 7] only notify once the user has granted authorization.
        notifier.requestAuthorization { [weak self] granted in
            self?.workQueue.async { self?.notificationsAuthorized = granted }
        }

        let router = Router()
        Routes.register(router: router, monitor: monitor,
                        client: client, token: config.bearerToken)
        server = HTTPServer(router: router, port: config.httpPort, workQueue: workQueue)
        do { try server.start() }
        catch { NSLog("HTTPServer failed to start: \(error)") }
        // [FIX 5] NEVER log the bearer token. It lives only in the 0600 config.json.
        NSLog("LaunchDashboard listening on 127.0.0.1:\(config.httpPort) (token in config.json)")

        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.pollIntervalSeconds),
                                     repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    // [FIX 6-UX] run a mutating action on the work queue, surface failures in the UI, refresh now.
    // Passing `self` into the action keeps the closure's trailing call non-optional (returns Void).
    private func run(_ action: @escaping (AppDelegate) throws -> Void) {
        workQueue.async { [weak self] in
            guard let self else { return }
            var message: String?
            do { try action(self) } catch { message = "\(error)" }
            DispatchQueue.main.async { self.menuBar.vm.lastError = message }
            self.pollOnQueue()
        }
    }

    private func startService(_ label: String) throws {
        let loaded = try client.listLoaded()
        if loaded[label] == nil {
            if let e = try monitor.scanner.scan().first(where: { $0.label == label }) {
                try client.bootstrap(plistPath: e.plistPath)
            }
        }
        try client.kickstart(label: label, restart: false)
    }

    private func loadService(_ label: String) throws {
        guard let e = try monitor.scanner.scan().first(where: { $0.label == label })
        else { throw LaunchctlError.commandFailed("no plist for \(label)") }
        try client.bootstrap(plistPath: e.plistPath)
    }

    @objc private func poll() {
        workQueue.async { [weak self] in self?.pollOnQueue() }
    }

    // [FIX 10] runs on workQueue: snapshot, crash-tracking, and auto-restart are serialized.
    private func pollOnQueue() {
        do {
            let snap = try monitor.snapshot()
            let events = crashTracker.update(snap)        // [FIX 1 + 4] dedup transitions
            if config.autoRestartEnabled { restarter.observe(snap) }
            let crashedSet = crashTracker.crashed
            DispatchQueue.main.async {
                self.menuBar.vm.services = snap
                self.menuBar.vm.crashed = crashedSet
                self.menuBar.updateBadge(failedCount: crashedSet.count)
            }
            if notificationsAuthorized {                  // [FIX 7]
                for e in events { notifier.notifyCrash(label: e.label, exitCode: e.exitCode) }
            }
        } catch {
            NSLog("poll failed: \(error)")
        }
    }
}
```

- [ ] **Step 4: Update main.swift to use AppDelegate**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 5: Build and run manually**

Run: `swift run`
Expected: A menu bar icon appears; clicking it opens a popover listing your LaunchAgents with status dots, a **legend**, and human-readable state. Crashed services show **red**. The token is **not** printed — read it from config.json (next step).

- [ ] **Step 6: Verify HTTP API (token from config, not logs)**

```bash
TOKEN=$(jq -r .bearerToken "$HOME/Library/Application Support/LaunchDashboard/config.json")
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/services | head -c 500
```

Expected: JSON array of services. An unauthenticated request returns `401`:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8765/services   # → 401
```

- [ ] **Step 7: Stop the swift run process (Ctrl+C) and commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/UI \
        tools/launch-dashboard/Sources/LaunchDashboard/AppDelegate.swift \
        tools/launch-dashboard/Sources/LaunchDashboard/main.swift
git commit -m "feat(launch-dashboard): menu bar UI (legend, error banner), serialized poll/HTTP, no token logging"
```

---

## Task 12: Install script + self LaunchAgent (standalone, opt-in)

**Files:**
- Create: `tools/launch-dashboard/scripts/install.sh`
- Create: `tools/launch-dashboard/scripts/com.prebenhafnor.launch-dashboard.plist.template`
- Create: `tools/launch-dashboard/scripts/Info.plist`

> **Implementation delta (applied during build, vs. the bare-binary reference below):** to make crash notifications work, the installer assembles a minimal **`~/Applications/LaunchDashboard.app`** bundle (`Contents/MacOS/LaunchDashboard` + `Contents/Info.plist` with `CFBundleIdentifier = com.prebenhafnor.launch-dashboard`, `LSUIElement = true`) and the LaunchAgent's `ProgramArguments` points at the bundle's executable. `UNUserNotificationCenter` requires a bundle identifier; a bare SwiftPM binary has none (so the AppDelegate guard disables notifications). With the bundle, `Bundle.main.bundleIdentifier` is non-nil and notifications fire. AppDelegate logs `notifications enabled (bundle …)` on launch to confirm. The reference `install.sh` below (bare binary → `~/.local/bin`) is superseded by the bundle-assembling version.

> **[FIX 7-install] Honest install integration.** The top-level `~/.dotfiles/install.sh` is **deliberately NOT modified**. It sources `setupfiles/*.sh` and runs on every full setup (multiple times); injecting a `swift build -c release` there would add a slow compile to every run for an optional tool. launch-dashboard is therefore a **standalone, opt-in installer** invoked explicitly. The earlier "Modify: install.sh" promise was removed because no step ever implemented it (the orchestrator never referenced the tool). This is documented in the README.

- [ ] **Step 1: Create the LaunchAgent plist template**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.prebenhafnor.launch-dashboard</string>
	<key>ProgramArguments</key>
	<array>
		<string>__BIN_PATH__</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>__LOG_DIR__/launch-dashboard.log</string>
	<key>StandardErrorPath</key>
	<string>__LOG_DIR__/launch-dashboard.err</string>
</dict>
</plist>
```

- [ ] **Step 2: Create install.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Runs from anywhere: resolve to the tool root regardless of caller's CWD.
cd "$(dirname "$0")/.."

BIN_DIR="$HOME/.local/bin"
LOG_DIR="$HOME/Library/Logs/LaunchDashboard"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENT_DIR/com.prebenhafnor.launch-dashboard.plist"
BIN_PATH="$BIN_DIR/launch-dashboard"

mkdir -p "$BIN_DIR" "$LOG_DIR" "$LAUNCH_AGENT_DIR"

echo "Building release binary..."
swift build -c release

cp -f .build/release/LaunchDashboard "$BIN_PATH"
chmod +x "$BIN_PATH"

echo "Writing LaunchAgent plist..."
sed -e "s|__BIN_PATH__|$BIN_PATH|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    scripts/com.prebenhafnor.launch-dashboard.plist.template > "$PLIST_PATH"

UID_NUM=$(id -u)
launchctl bootout "gui/$UID_NUM/com.prebenhafnor.launch-dashboard" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST_PATH"

echo "Installed. Tail logs with: tail -f $LOG_DIR/launch-dashboard.log"
echo "Bearer token (do NOT share):"
echo "  jq -r .bearerToken \"\$HOME/Library/Application Support/LaunchDashboard/config.json\""
```

- [ ] **Step 3: Make install.sh executable and run it**

```bash
chmod +x tools/launch-dashboard/scripts/install.sh
tools/launch-dashboard/scripts/install.sh
```

Expected: "Building release binary..." then a successful compile and "Installed. ..."

- [ ] **Step 4: Verify the app is loaded and running**

```bash
launchctl print "gui/$(id -u)/com.prebenhafnor.launch-dashboard" | grep -E "state|pid"
```

Expected: `state = running` with a PID.

- [ ] **Step 5: Verify menu bar icon appears and HTTP API responds (token from config)**

```bash
TOKEN=$(jq -r .bearerToken "$HOME/Library/Application Support/LaunchDashboard/config.json")
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/services | jq '. | length'
```

Expected: a number (count of LaunchAgents in `~/Library/LaunchAgents/`).

- [ ] **Step 6: Commit**

```bash
git add tools/launch-dashboard/scripts
git commit -m "feat(launch-dashboard): standalone install script and self-managed LaunchAgent"
```

---

## Task 13: Cloudflared integration (behind Access) + README

**Files:**
- Create: `tools/launch-dashboard/README.md`
- Modify: `.config/cloudflared/config.yml` (manually, documented in README)

> **[FIX 3] Remote exposure is opt-in AND gated by Cloudflare Access.** The default posture is **loopback-only** (no public hostname). Exposing the control plane to the internet behind only a bearer token is rejected. If remote access is desired, it must sit behind a Cloudflare Access (Zero Trust) policy on the hostname — the bearer token remains as app-layer defense-in-depth, not the sole control. **[FIX 15]** Publishing the hostname requires **both** an ingress rule **and** a DNS route (`cloudflared tunnel route dns`); the existing tunnel is `d21fa304-…` with LaunchAgent label `com.nors.cloudflared`.

- [ ] **Step 1: Write README.md**

````markdown
# launch-dashboard

Native macOS menu bar app that monitors `~/Library/LaunchAgents/`, auto-restarts
crashed services with exponential backoff, sends crash notifications, and exposes
an authenticated **loopback-only** HTTP API for local control.

> Not part of the standard `~/.dotfiles/install.sh` run — it's an opt-in tool with
> its own installer (`./scripts/install.sh`).

## Install

```bash
cd tools/launch-dashboard
./scripts/install.sh
```

This builds a release binary, copies it to `~/.local/bin/launch-dashboard`, and
installs a `KeepAlive` LaunchAgent so it survives reboot.

First-run config lives at
`~/Library/Application Support/LaunchDashboard/config.json` (mode `0600`) and
includes an auto-generated 256-bit bearer token. Read it with:

```bash
jq -r .bearerToken "$HOME/Library/Application Support/LaunchDashboard/config.json"
```

The token is **never** written to logs.

## HTTP API

Bound to `127.0.0.1:8765` only — **not reachable from the LAN**. All routes require
`Authorization: Bearer <token>`.

| Method | Path                          | Effect                                                   |
|--------|-------------------------------|----------------------------------------------------------|
| GET    | `/services`                   | JSON snapshot of all services                            |
| POST   | `/services/:label/start`      | bootstrap (if needed) then `launchctl kickstart`         |
| POST   | `/services/:label/stop`       | `launchctl bootout`                                      |
| POST   | `/services/:label/restart`    | `launchctl kickstart -k`                                 |
| POST   | `/services/:label/load`       | `launchctl bootstrap <plist>`                            |
| GET    | `/services/:label/logs`       | Tail of `StandardErrorPath` (16 KB), confined to `~/Library/Logs`, `/tmp`, `/var/log` |

```bash
TOKEN=$(jq -r .bearerToken "$HOME/Library/Application Support/LaunchDashboard/config.json")
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/services | jq '. | length'
```

## Remote access (optional, MUST be behind Cloudflare Access)

The API controls arbitrary LaunchAgents, so it must never be exposed to the public
internet behind only the bearer token. To reach it remotely, put it behind a
Cloudflare Access policy:

1. Add an ingress rule to `~/.dotfiles/.config/cloudflared/config.yml` **above** the
   catch-all:

   ```yaml
   ingress:
     - hostname: launchpad.prebenhafnor.com
       service: http://127.0.0.1:8765
     # ...existing rules...
     - service: http_status:404
   ```

2. Create the DNS route for the hostname (one-time):

   ```bash
   cloudflared tunnel route dns d21fa304-74b3-41b3-a907-c75e6317cb72 launchpad.prebenhafnor.com
   ```

3. In the Cloudflare Zero Trust dashboard, add an **Access application** for
   `launchpad.prebenhafnor.com` with a policy restricted to your identity
   (email/SSO). Without this, do not publish the hostname.

4. Restart the tunnel:

   ```bash
   launchctl kickstart -k "gui/$(id -u)/com.nors.cloudflared"
   ```

The bearer token still guards every request as a second layer.

## Development

```bash
swift test                  # run unit tests
swift run                   # run interactively in foreground
swift build -c release      # build the release binary
```
````

- [ ] **Step 2: (Optional) Manually add cloudflared route behind Access**

Only if remote access is wanted. Follow README steps 1–4. Do **not** publish the
hostname without the Access policy in place. Do not commit secrets.

- [ ] **Step 3: Verify loopback-only by default**

```bash
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || echo 0.0.0.0)
nc -z -G1 "$LAN_IP" 8765 && echo "LAN: OPEN (BUG)" || echo "LAN: refused (correct)"
```

Expected: `LAN: refused (correct)` — confirms [FIX 2].

- [ ] **Step 4: (If remote enabled) Verify Access challenge + token**

```bash
# Unauthenticated through the tunnel should be intercepted by Cloudflare Access
# (redirect/challenge), NOT reach the app with a 200:
curl -sS -o /dev/null -w "%{http_code}\n" https://launchpad.prebenhafnor.com/services
```

Expected: a `302`/`403` from Access (not `200`). After authenticating through Access,
requests still require the bearer token (`401` without it).

- [ ] **Step 5: Commit README**

```bash
git add tools/launch-dashboard/README.md
git commit -m "docs(launch-dashboard): README with loopback default and Access-gated remote setup"
```

---

## Self-Review

**Spec coverage:**
- Native macOS app ✓ (SwiftUI + AppKit menu bar in Task 11)
- Watches all `~/Library/LaunchAgents/` ✓ (PlistScanner, Task 3)
- Status/PID/exit code per service ✓ (ServiceStatus + LaunchctlClient, Tasks 4–5)
- Start/stop/restart/load buttons ✓ (UI Task 11 + HTTP routes Task 9)
- Auto-restart with backoff ✓ (Task 6, self-excluded)
- macOS notifications on crash ✓ (Task 7, deduplicated)
- HTTP API on loopback ✓ (Tasks 8–10, 127.0.0.1-bound)
- Bearer-token auth ✓ (Task 8)
- Self-managed LaunchAgent ✓ (Task 12, standalone installer)
- Cloudflared exposure ✓ (Task 13, opt-in behind Access)

**Review objections addressed (15 accepted):**
- [FIX 1] Crash detection no longer trusts the stale `launchctl list` Status column — running = PID present; crash = transition. Test fixtures include a running-with-non-zero-Status row (Tasks 4–5, 7).
- [FIX 2] HTTPServer binds loopback-only via `requiredLocalEndpoint` (Task 10); LAN-refusal smoke test (Tasks 10, 13).
- [FIX 3] Remote exposure is opt-in and gated by Cloudflare Access, not a bare token (Task 13).
- [FIX 4] CrashTracker deduplicates — one notification per crash, badge reflects currently-crashed set (Tasks 7, 11).
- [FIX 5] Bearer token is never logged (Task 11).
- [FIX 6] Token stored `0600`; unreadable config → ephemeral random token, not a constant (Tasks 2, 11).
- [FIX 7] Notifications wait for authorization; install path reads token from config.json consistently (Tasks 7, 11, 12).
- [FIX 8] `/start` bootstraps before kickstart (Task 9).
- [FIX 9] HTTP parser buffers across reads, honors Content-Length, caps size (Task 10).
- [FIX 10] Single serial work queue serializes poll + HTTP handlers + UI actions (Tasks 6, 7, 10, 11).
- [FIX 11] `/logs` path confined to an allowlist (Task 9).
- [FIX 12] AutoRestarter excludes the app's own label (Task 6).
- [FIX 13] Config load is non-destructive on corrupt files (Task 2).
- [FIX 14] Crashed → red dot + visible legend + human-readable state (Task 11).
- [FIX 7-install] Top-level `install.sh` is honestly left unmodified; tool is opt-in (Task 12).
- [FIX 15] cloudflared DNS route step documented (Task 13).

**Placeholder scan:** No `TBD`/`TODO`/"implement later" entries; every step has actual code or an exact command.

**Type consistency:** `ServiceStatus`, `ServiceState`, `PlistEntry`, `LoadedEntry`, `HTTPRequest`, `HTTPResponse`, `Router`, `ProcessRunner`, `Config`, `LaunchctlClient`, `ServiceMonitor`, `CrashTracker`, `AutoRestarter` — each defined once and referenced consistently. New/changed signatures verified across tasks: `AutoRestarter(now:restart:ownLabel:)` (Task 6 def, Task 11 call), `CrashNotifier.requestAuthorization(_:)` completion (Task 7 def, Task 11 call), `HTTPServer(router:port:workQueue:)` (Task 10 def, Task 11 call), `Routes.register(router:monitor:client:token:)` (Task 9 def, Task 11 call), `CrashTracker.update(_:) -> [Event]` + `.crashed` (Task 7 def, Task 11 call).
