# Launch Dashboard: Inspect URLs + Tunnel Routes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two features to the LaunchDashboard menu-bar app: (1) click a service row to open its inspect URL in the browser, and (2) a separate window to view and toggle cloudflared tunnel ingress routes.

**Architecture:** Feature 1 reads a per-service `inspectTargets` map from `config.json` and opens URLs via `NSWorkspace`. Feature 2 uses a pure line-based parser/toggler over `~/.cloudflared/config.yml` (comment-out = off), writes through the dotfiles symlink atomically, and reloads the tunnel via `launchctl kickstart`. No new third-party dependencies.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Foundation, XCTest. SwiftPM package at `tools/launch-dashboard/`.

**Spec:** `docs/superpowers/specs/2026-06-07-launch-dashboard-inspect-and-tunnel-routes-design.md`

**Conventions:**
- All `swift` commands run against the package: prefix with `(cd tools/launch-dashboard && …)`.
- Commit messages use `feat(launch-dashboard): …` and end with the trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/LaunchDashboard/Models/Config.swift` | + `InspectTarget` struct, + optional `inspectTargets`/`cloudflaredConfigPath`/`cloudflaredLabel` fields, URL helpers |
| `Sources/LaunchDashboard/Models/IngressRule.swift` (new) | value type for one ingress route |
| `Sources/LaunchDashboard/Core/IngressConfigParser.swift` (new) | pure `parse`/`toggle` over config.yml text |
| `Sources/LaunchDashboard/Core/CloudflaredController.swift` (new) | IO: read/parse, symlink-aware atomic write, tunnel reload |
| `Sources/LaunchDashboard/UI/ServicesView.swift` | clickable rows + open-URL menu items + footer button |
| `Sources/LaunchDashboard/UI/MenuBarController.swift` | thread new closures through |
| `Sources/LaunchDashboard/UI/TunnelRoutesView.swift` (new) | routes window view + view model |
| `Sources/LaunchDashboard/UI/TunnelRoutesWindowController.swift` (new) | hosts the view in a single-instance NSWindow |
| `Sources/LaunchDashboard/AppDelegate.swift` | wire open-URL + open-window actions, pass `inspectTargets` to VM |
| `Tests/LaunchDashboardTests/ConfigTests.swift` | + `inspectTargets` decoding + `InspectTarget` URL helpers |
| `Tests/LaunchDashboardTests/IngressConfigParserTests.swift` (new) | parse + toggle round-trip tests |
| `Tests/LaunchDashboardTests/CloudflaredControllerTests.swift` (new) | symlink write + reload (fake runner) |

---

## Task 1: Config — InspectTarget + new optional fields

**Files:**
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/Models/Config.swift`
- Test: `tools/launch-dashboard/Tests/LaunchDashboardTests/ConfigTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `ConfigTests.swift` (inside the class):

```swift
    func testDecodesInspectTargets() throws {
        let json = """
        {"bearerToken":"x","httpPort":8765,"pollIntervalSeconds":5,"autoRestartEnabled":true,
         "inspectTargets":{"com.nors.ai-daemon":{"public":"https://daemon.prebenhafnor.com","local":"http://localhost:8787"}}}
        """
        let cfg = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        let t = cfg.inspectTargets?["com.nors.ai-daemon"]
        XCTAssertEqual(t?.publicURL, URL(string: "https://daemon.prebenhafnor.com"))
        XCTAssertEqual(t?.localURL, URL(string: "http://localhost:8787"))
        XCTAssertEqual(t?.preferredURL, URL(string: "https://daemon.prebenhafnor.com"))
    }

    func testConfigWithoutInspectTargetsStillDecodes() throws {
        let json = """
        {"bearerToken":"x","httpPort":8765,"pollIntervalSeconds":5,"autoRestartEnabled":true}
        """
        let cfg = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertNil(cfg.inspectTargets)
        XCTAssertNil(cfg.cloudflaredConfigPath)
        XCTAssertNil(cfg.cloudflaredLabel)
    }

    func testPreferredURLFallsBackToLocal() {
        let t = InspectTarget(public: nil, local: "http://localhost:9000")
        XCTAssertEqual(t.preferredURL, URL(string: "http://localhost:9000"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `(cd tools/launch-dashboard && swift test --filter ConfigTests)`
Expected: FAIL — `InspectTarget` and `inspectTargets` are undefined (compile error).

- [ ] **Step 3: Add `InspectTarget` and the new fields**

In `Config.swift`, add this struct above `struct Config`:

```swift
struct InspectTarget: Codable, Equatable {
    var `public`: String?
    var local: String?

    var publicURL: URL? { `public`.flatMap { URL(string: $0) } }
    var localURL: URL? { local.flatMap { URL(string: $0) } }
    /// Prefer the public (tunnel) URL; fall back to local.
    var preferredURL: URL? { publicURL ?? localURL }
}
```

In `struct Config`, add after `priorityLabels`:

```swift
    /// Per-service inspect URLs (label → {public, local}). Optional so existing config.json decodes.
    var inspectTargets: [String: InspectTarget]?
    /// Path to the cloudflared config.yml. nil → ~/.cloudflared/config.yml.
    var cloudflaredConfigPath: String?
    /// LaunchAgent label for the tunnel, used for reload. nil → com.prebenhafnor.cloudflared.
    var cloudflaredLabel: String?
```

Update the `Config(...)` literal inside `loadOrCreate` (the `fresh` value) to add the new fields:

```swift
        let fresh = Config(
            bearerToken: Self.makeToken(),
            httpPort: 8765,
            pollIntervalSeconds: 5,
            autoRestartEnabled: true,
            priorityLabels: nil,
            inspectTargets: nil,
            cloudflaredConfigPath: nil,
            cloudflaredLabel: nil
        )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `(cd tools/launch-dashboard && swift test --filter ConfigTests)`
Expected: PASS (all ConfigTests).

Note: this will surface a compile error at the other `Config(...)` literal in `AppDelegate.swift` (the unreadable-config fallback). Fix it now by adding the three new arguments `inspectTargets: nil, cloudflaredConfigPath: nil, cloudflaredLabel: nil` to that literal so the whole package compiles.

- [ ] **Step 5: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Models/Config.swift \
        tools/launch-dashboard/Sources/LaunchDashboard/AppDelegate.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/ConfigTests.swift
git commit -m "$(printf 'feat(launch-dashboard): add inspectTargets + cloudflared config knobs\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 2: IngressRule model + parser (`parse`)

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Models/IngressRule.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Core/IngressConfigParser.swift`
- Test: `tools/launch-dashboard/Tests/LaunchDashboardTests/IngressConfigParserTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IngressConfigParserTests.swift`:

```swift
import XCTest
@testable import LaunchDashboard

final class IngressConfigParserTests: XCTestCase {
    // Mirrors the real config.yml shape: active host rules, one disabled rule, catch-all.
    let sample = """
    tunnel: d21fa304
    ingress:
      # nors ai-daemon dashboard (always-on)
      - hostname: daemon.prebenhafnor.com
        service: http://localhost:8787
      - hostname: local3000.prebenhafnor.com
        service: http://localhost:3000
      # - hostname: local8001.prebenhafnor.com
        # service: http://localhost:8001
      - service: http_status:404
    """

    func testParseFindsHostRulesWithEnabledState() {
        let rules = IngressConfigParser.parse(sample)
        let hosts = rules.filter { $0.hostname != nil }
        XCTAssertEqual(hosts.map { $0.hostname }, [
            "daemon.prebenhafnor.com", "local3000.prebenhafnor.com", "local8001.prebenhafnor.com"
        ])
        XCTAssertEqual(rules.first { $0.hostname == "daemon.prebenhafnor.com" }?.enabled, true)
        XCTAssertEqual(rules.first { $0.hostname == "daemon.prebenhafnor.com" }?.service, "http://localhost:8787")
        XCTAssertEqual(rules.first { $0.hostname == "local8001.prebenhafnor.com" }?.enabled, false)
    }

    func testParseMarksCatchAll() {
        let rules = IngressConfigParser.parse(sample)
        let catchAll = rules.first { $0.isCatchAll }
        XCTAssertNotNil(catchAll)
        XCTAssertNil(catchAll?.hostname)
        XCTAssertEqual(catchAll?.service, "http_status:404")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `(cd tools/launch-dashboard && swift test --filter IngressConfigParserTests)`
Expected: FAIL — `IngressRule` / `IngressConfigParser` undefined.

- [ ] **Step 3: Create `IngressRule.swift`**

```swift
import Foundation

/// One cloudflared ingress route parsed from config.yml.
struct IngressRule: Identifiable, Equatable {
    let hostname: String?          // nil for the catch-all (service-only) rule
    let service: String
    let enabled: Bool              // false = commented out in config.yml
    let isCatchAll: Bool
    let lineRange: ClosedRange<Int>  // 0-based line indices this rule occupies

    var id: String { hostname ?? "__catchall_\(lineRange.lowerBound)" }
}
```

- [ ] **Step 4: Create `IngressConfigParser.swift` with `parse` (toggle added in Task 3)**

```swift
import Foundation

/// Pure, IO-free parsing/editing of a cloudflared config.yml `ingress:` section.
/// "Off" is represented by commenting a rule's lines; "on" by uncommenting them.
enum IngressConfigParser {

    private struct AnalyzedLine {
        let indent: String     // leading whitespace
        let commented: Bool
        let content: String    // trimmed text after optional leading "# "
    }

    private static func analyze(_ raw: String) -> AnalyzedLine {
        let ws = raw.prefix { $0 == " " || $0 == "\t" }
        var rest = String(raw.dropFirst(ws.count))
        var commented = false
        if rest.first == "#" {
            commented = true
            rest.removeFirst()
            if rest.first == " " { rest.removeFirst() }
        }
        return AnalyzedLine(indent: String(ws), commented: commented,
                            content: rest.trimmingCharacters(in: .whitespaces))
    }

    static func parse(_ text: String) -> [IngressRule] {
        let lines = text.components(separatedBy: "\n")
        var rules: [IngressRule] = []
        var inIngress = false
        var i = 0
        while i < lines.count {
            let ln = analyze(lines[i])
            if !ln.commented && ln.content == "ingress:" { inIngress = true; i += 1; continue }
            guard inIngress else { i += 1; continue }

            if ln.content.hasPrefix("- service:") {
                let svc = ln.content.dropFirst("- service:".count).trimmingCharacters(in: .whitespaces)
                rules.append(IngressRule(hostname: nil, service: svc,
                                         enabled: !ln.commented,
                                         isCatchAll: svc.hasPrefix("http_status"),
                                         lineRange: i...i))
                i += 1; continue
            }

            if ln.content.hasPrefix("- hostname:") {
                let host = ln.content.dropFirst("- hostname:".count).trimmingCharacters(in: .whitespaces)
                var j = i + 1
                var svc = ""
                var svcCommented = ln.commented
                while j < lines.count {
                    let nx = analyze(lines[j])
                    if nx.content.hasPrefix("service:") {
                        svc = nx.content.dropFirst("service:".count).trimmingCharacters(in: .whitespaces)
                        svcCommented = nx.commented
                        break
                    }
                    if nx.content.hasPrefix("- ") { break }  // next rule began; malformed pair
                    j += 1
                }
                let end = min(j, lines.count - 1)
                rules.append(IngressRule(hostname: host, service: svc,
                                         enabled: !ln.commented && !svcCommented,
                                         isCatchAll: false,
                                         lineRange: i...end))
                i = j + 1; continue
            }
            i += 1
        }
        return rules
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `(cd tools/launch-dashboard && swift test --filter IngressConfigParserTests)`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Models/IngressRule.swift \
        tools/launch-dashboard/Sources/LaunchDashboard/Core/IngressConfigParser.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/IngressConfigParserTests.swift
git commit -m "$(printf 'feat(launch-dashboard): parse cloudflared ingress rules\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 3: Parser — `toggle` (comment/uncomment, round-trip safe)

**Files:**
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/Core/IngressConfigParser.swift`
- Test: `tools/launch-dashboard/Tests/LaunchDashboardTests/IngressConfigParserTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `IngressConfigParserTests.swift` (inside the class):

```swift
    func testToggleDisablesAnActiveRule() {
        let out = IngressConfigParser.toggle(sample, hostname: "local3000.prebenhafnor.com")
        let rule = IngressConfigParser.parse(out).first { $0.hostname == "local3000.prebenhafnor.com" }
        XCTAssertEqual(rule?.enabled, false)
        // Untouched rules keep their state.
        XCTAssertEqual(IngressConfigParser.parse(out).first { $0.hostname == "daemon.prebenhafnor.com" }?.enabled, true)
    }

    func testToggleEnablesADisabledRule() {
        let out = IngressConfigParser.toggle(sample, hostname: "local8001.prebenhafnor.com")
        let rule = IngressConfigParser.parse(out).first { $0.hostname == "local8001.prebenhafnor.com" }
        XCTAssertEqual(rule?.enabled, true)
    }

    func testToggleRoundTripIsIdentity() {
        let off = IngressConfigParser.toggle(sample, hostname: "local3000.prebenhafnor.com")
        let backOn = IngressConfigParser.toggle(off, hostname: "local3000.prebenhafnor.com")
        XCTAssertEqual(backOn, sample)  // byte-identical after off→on
    }

    func testToggleNeverTouchesCatchAll() {
        let out = IngressConfigParser.toggle(sample, hostname: "http_status:404")
        XCTAssertEqual(out, sample)  // no host rule matches; no-op
        XCTAssertEqual(IngressConfigParser.parse(out).first { $0.isCatchAll }?.enabled, true)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `(cd tools/launch-dashboard && swift test --filter IngressConfigParserTests)`
Expected: FAIL — `toggle` is undefined.

- [ ] **Step 3: Add `toggle` and the comment helpers**

Add these to the `IngressConfigParser` enum:

```swift
    /// Flip the enabled state of the host rule matching `hostname`. Returns the new file text.
    /// No-op if the hostname isn't a (non-catch-all) host rule.
    static func toggle(_ text: String, hostname: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let rule = parse(text).first(where: { $0.hostname == hostname }), !rule.isCatchAll
        else { return text }
        let shouldComment = rule.enabled  // enabled → comment out; disabled → uncomment
        for idx in rule.lineRange {
            lines[idx] = shouldComment ? commentLine(lines[idx]) : uncommentLine(lines[idx])
        }
        return lines.joined(separator: "\n")
    }

    private static func commentLine(_ raw: String) -> String {
        let ws = raw.prefix { $0 == " " || $0 == "\t" }
        let rest = raw.dropFirst(ws.count)
        if rest.first == "#" { return raw }  // already commented
        return "\(ws)# \(rest)"
    }

    private static func uncommentLine(_ raw: String) -> String {
        let ws = raw.prefix { $0 == " " || $0 == "\t" }
        var rest = String(raw.dropFirst(ws.count))
        guard rest.first == "#" else { return raw }
        rest.removeFirst()
        if rest.first == " " { rest.removeFirst() }
        return "\(ws)\(rest)"
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `(cd tools/launch-dashboard && swift test --filter IngressConfigParserTests)`
Expected: PASS (all 6 parser tests).

- [ ] **Step 5: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Core/IngressConfigParser.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/IngressConfigParserTests.swift
git commit -m "$(printf 'feat(launch-dashboard): toggle ingress rules via comment round-trip\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 4: CloudflaredController (symlink-aware write + reload)

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/Core/CloudflaredController.swift`
- Test: `tools/launch-dashboard/Tests/LaunchDashboardTests/CloudflaredControllerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `CloudflaredControllerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `(cd tools/launch-dashboard && swift test --filter CloudflaredControllerTests)`
Expected: FAIL — `CloudflaredController` undefined.

- [ ] **Step 3: Create `CloudflaredController.swift`**

```swift
import Foundation

/// IO wrapper around a cloudflared config.yml: reads/parses ingress rules, toggles a rule
/// (writing through any symlink to the real file), and reloads the tunnel LaunchAgent.
struct CloudflaredController {
    let configPath: URL          // may be a symlink (e.g. ~/.cloudflared/config.yml → dotfiles)
    let runner: ProcessRunner
    let uid: uid_t
    let cloudflaredLabel: String

    static func makeDefault(config: Config) -> CloudflaredController {
        let raw = config.cloudflaredConfigPath ?? "~/.cloudflared/config.yml"
        let path = NSString(string: raw).expandingTildeInPath
        return CloudflaredController(
            configPath: URL(fileURLWithPath: path),
            runner: RealProcessRunner(),
            uid: getuid(),
            cloudflaredLabel: config.cloudflaredLabel ?? "com.prebenhafnor.cloudflared"
        )
    }

    func rules() throws -> [IngressRule] {
        let text = try String(contentsOf: configPath, encoding: .utf8)
        return IngressConfigParser.parse(text)
    }

    /// Bring `hostname` to the desired enabled state. No-op (no write, no reload) if already there.
    func setEnabled(hostname: String, enabled: Bool) throws {
        let text = try String(contentsOf: configPath, encoding: .utf8)
        guard let rule = IngressConfigParser.parse(text).first(where: { $0.hostname == hostname }),
              !rule.isCatchAll, rule.enabled != enabled
        else { return }
        let newText = IngressConfigParser.toggle(text, hostname: hostname)
        try writeThroughSymlink(newText)
        try LaunchctlClient(runner: runner, uid: uid)
            .kickstart(label: cloudflaredLabel, restart: true)
    }

    /// Atomic write that follows a symlink to its real target (so we never replace the symlink
    /// itself), preserving the target's POSIX permissions.
    private func writeThroughSymlink(_ text: String) throws {
        let target = configPath.resolvingSymlinksInPath()
        let fm = FileManager.default
        let perms = ((try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
                     as? NSNumber)?.intValue ?? 0o644
        let tmp = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).tmp-\(uid)")
        try Data(text.utf8).write(to: tmp, options: .atomic)
        try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: tmp.path)
        _ = try fm.replaceItemAt(target, withItemAt: tmp)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `(cd tools/launch-dashboard && swift test --filter CloudflaredControllerTests)`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/Core/CloudflaredController.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/CloudflaredControllerTests.swift
git commit -m "$(printf 'feat(launch-dashboard): symlink-aware cloudflared config writer + reload\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 5: ServicesView — clickable rows + open-URL menu items

**Files:**
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/UI/ServicesView.swift`

This task is UI; it is verified by a successful build plus the manual check in Task 9 (no unit test — the URL-selection logic it relies on is `InspectTarget.preferredURL`, already tested in Task 1).

- [ ] **Step 1: Add the inspect state + new closures to the view model and view**

In `ServicesView.swift`, add to `ServicesViewModel`:

```swift
    @Published var inspectTargets: [String: InspectTarget] = [:]   // label → URLs
```

Change `struct ServicesView`'s stored closures to add two new ones (place after `onLoad`):

```swift
    let onOpenURL: (URL) -> Void
    let onOpenTunnelRoutes: () -> Void
```

- [ ] **Step 2: Make the row label clickable and add menu items**

Replace the `row(_:)` function body's `VStack` (the label block) and `Menu` so a row with an inspect target opens its URL. Replace the whole `row(_:)` function with:

```swift
    @ViewBuilder
    private func row(_ s: ServiceStatus) -> some View {
        let target = vm.inspectTargets[s.label]
        HStack {
            Circle().fill(color(for: s)).frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                if let url = target?.preferredURL {
                    Button {
                        onOpenURL(url)
                    } label: {
                        HStack(spacing: 4) {
                            Text(s.label).font(.system(.body, design: .monospaced))
                            Image(systemName: "globe").font(.caption2)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(s.label).font(.system(.body, design: .monospaced))
                }
                Text(detail(for: s)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu("⋯") {
                if let url = target?.publicURL { Button("Open \(url.host ?? url.absoluteString)") { onOpenURL(url) } }
                if let url = target?.localURL { Button("Open \(url.host ?? "local"):\(url.port.map(String.init) ?? "")") { onOpenURL(url) } }
                if target?.publicURL != nil || target?.localURL != nil { Divider() }
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
```

- [ ] **Step 3: Build to verify it compiles**

Run: `(cd tools/launch-dashboard && swift build)`
Expected: FAIL — `MenuBarController` still calls `ServicesView(...)` without the two new closures. That is fixed in Task 6. (If you want a green build at this exact step, do Task 6 before building; the commit below bundles both is acceptable, but this plan commits Task 5 and Task 6 separately — build at the end of Task 6.)

- [ ] **Step 4: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/UI/ServicesView.swift
git commit -m "$(printf 'feat(launch-dashboard): clickable service rows open inspect URLs\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 6: ServicesView footer button + MenuBarController plumbing

**Files:**
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/UI/ServicesView.swift`
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/UI/MenuBarController.swift`

- [ ] **Step 1: Add the "Tunnel routes…" footer button**

In `ServicesView.swift`, replace the `legend` computed property with a footer that keeps the legend and adds the button:

```swift
    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(.green, "Running")
            legendDot(.red, "Crashed")
            legendDot(.yellow, "Stopped")
            legendDot(.gray, "Not loaded")
            Spacer()
            Button("Tunnel routes…") { onOpenTunnelRoutes() }
                .font(.caption2)
        }
        .font(.caption2).foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
```

- [ ] **Step 2: Thread the closures through `MenuBarController`**

In `MenuBarController.swift`, extend `init` to accept and forward the two new closures:

```swift
    init(onStart: @escaping (String) -> Void,
         onStop: @escaping (String) -> Void,
         onRestart: @escaping (String) -> Void,
         onLoad: @escaping (String) -> Void,
         onOpenURL: @escaping (URL) -> Void,
         onOpenTunnelRoutes: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 480)
        popover.contentViewController = NSHostingController(
            rootView: ServicesView(vm: vm,
                                   onStart: onStart, onStop: onStop,
                                   onRestart: onRestart, onLoad: onLoad,
                                   onOpenURL: onOpenURL,
                                   onOpenTunnelRoutes: onOpenTunnelRoutes))
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent",
                                           accessibilityDescription: nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
    }
```

- [ ] **Step 3: Build**

Run: `(cd tools/launch-dashboard && swift build)`
Expected: FAIL — `AppDelegate` calls `MenuBarController(...)` without the two new closures (fixed in Task 8). Proceed; full build is green at the end of Task 8.

- [ ] **Step 4: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/UI/ServicesView.swift \
        tools/launch-dashboard/Sources/LaunchDashboard/UI/MenuBarController.swift
git commit -m "$(printf 'feat(launch-dashboard): tunnel-routes footer button + menubar plumbing\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 7: TunnelRoutesView + window controller

**Files:**
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/UI/TunnelRoutesView.swift`
- Create: `tools/launch-dashboard/Sources/LaunchDashboard/UI/TunnelRoutesWindowController.swift`

- [ ] **Step 1: Create `TunnelRoutesView.swift` (view + view model)**

```swift
import SwiftUI

final class TunnelRoutesViewModel: ObservableObject {
    @Published var rules: [IngressRule] = []
    @Published var status: String = ""
    private let controller: CloudflaredController
    private let queue = DispatchQueue(label: "com.prebenhafnor.launch-dashboard.cloudflared")

    init(controller: CloudflaredController) { self.controller = controller }

    func reload() {
        queue.async {
            do {
                let r = try self.controller.rules()
                DispatchQueue.main.async { self.rules = r; self.status = "Loaded \(r.count) route(s)" }
            } catch {
                DispatchQueue.main.async { self.status = "Error: \(error.localizedDescription)" }
            }
        }
    }

    func setEnabled(_ rule: IngressRule, _ enabled: Bool) {
        guard let host = rule.hostname else { return }
        queue.async {
            do {
                try self.controller.setEnabled(hostname: host, enabled: enabled)
                let r = try self.controller.rules()
                DispatchQueue.main.async {
                    self.rules = r
                    self.status = "\(enabled ? "Enabled" : "Disabled") \(host) · tunnel reloaded"
                }
            } catch {
                DispatchQueue.main.async { self.status = "Error: \(error.localizedDescription)" }
            }
        }
    }
}

struct TunnelRoutesView: View {
    @ObservedObject var vm: TunnelRoutesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cloudflared Tunnel Routes").font(.headline).padding(8)
            Divider()
            ScrollView {
                ForEach(vm.rules) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.hostname ?? "(catch-all)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(rule.enabled ? .primary : .secondary)
                            Text(rule.service).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if rule.isCatchAll {
                            Text("always on").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Toggle("", isOn: Binding(
                                get: { rule.enabled },
                                set: { vm.setEnabled(rule, $0) }
                            )).labelsHidden()
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    Divider()
                }
            }
            Divider()
            HStack {
                Button("Reload") { vm.reload() }
                Spacer()
                Text(vm.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(8)
        }
        .frame(width: 460, height: 420)
    }
}
```

- [ ] **Step 2: Create `TunnelRoutesWindowController.swift` (single-instance window)**

```swift
import AppKit
import SwiftUI

/// Owns a single Tunnel Routes window; re-shows the same window if already open.
final class TunnelRoutesWindowController {
    private var window: NSWindow?
    private let controller: CloudflaredController

    init(controller: CloudflaredController) { self.controller = controller }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let vm = TunnelRoutesViewModel(controller: controller)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        w.title = "Tunnel Routes"
        w.contentViewController = NSHostingController(rootView: TunnelRoutesView(vm: vm))
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        vm.reload()
    }
}
```

- [ ] **Step 3: Build**

Run: `(cd tools/launch-dashboard && swift build)`
Expected: still FAIL at `AppDelegate` (the `MenuBarController(...)` call), fixed in Task 8. The two new files themselves must compile (no errors referencing them).

- [ ] **Step 4: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/UI/TunnelRoutesView.swift \
        tools/launch-dashboard/Sources/LaunchDashboard/UI/TunnelRoutesWindowController.swift
git commit -m "$(printf 'feat(launch-dashboard): tunnel routes window with per-route toggles\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 8: AppDelegate wiring (green build)

**Files:**
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/AppDelegate.swift`

- [ ] **Step 1: Add the window controller property and inspect-targets pass-through**

In `AppDelegate`, add a stored property near the other lets:

```swift
    private var tunnelRoutesWC: TunnelRoutesWindowController!
```

In `applicationDidFinishLaunching(_:)`, replace the `menuBar = MenuBarController(...)` construction with one that wires the two new closures, and create the window controller. Put this where the old `menuBar = MenuBarController(...)` call is:

```swift
        tunnelRoutesWC = TunnelRoutesWindowController(
            controller: CloudflaredController.makeDefault(config: config))

        menuBar = MenuBarController(
            onStart:   { [weak self] label in self?.run { try $0.startService(label) } },
            onStop:    { [weak self] label in self?.run { try $0.client.bootout(label: label) } },
            onRestart: { [weak self] label in self?.run { try $0.client.kickstart(label: label, restart: true) } },
            onLoad:    { [weak self] label in self?.run { try $0.loadService(label) } },
            onOpenURL: { url in NSWorkspace.shared.open(url) },
            onOpenTunnelRoutes: { [weak self] in self?.tunnelRoutesWC.show() }
        )
        menuBar.vm.inspectTargets = config.inspectTargets ?? [:]
```

(`applicationDidFinishLaunching` runs on the main thread, so setting `menuBar.vm.inspectTargets` here is safe.)

- [ ] **Step 2: Build the whole package**

Run: `(cd tools/launch-dashboard && swift build)`
Expected: PASS (build succeeds, no errors).

- [ ] **Step 3: Run the full test suite**

Run: `(cd tools/launch-dashboard && swift test)`
Expected: PASS (all existing tests plus the new Config / parser / controller tests).

- [ ] **Step 4: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/AppDelegate.swift
git commit -m "$(printf 'feat(launch-dashboard): wire inspect URLs + tunnel routes window\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 9: Install, seed live config, docs, manual verification

**Files:**
- Modify: `tools/launch-dashboard/README.md`
- Runtime: `~/Library/Application Support/LaunchDashboard/config.json` (not in git)

- [ ] **Step 1: Seed the live config with the ai-daemon inspect target**

```bash
CONFIG="$HOME/Library/Application Support/LaunchDashboard/config.json"
jq '.inspectTargets = {"com.nors.ai-daemon": {"public":"https://daemon.prebenhafnor.com","local":"http://localhost:8787"}}' \
  "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG" && chmod 600 "$CONFIG"
jq '.inspectTargets' "$CONFIG"
```
Expected: prints the ai-daemon object.

- [ ] **Step 2: Build + install the app and reload the LaunchAgent**

Run: `(cd tools/launch-dashboard && ./scripts/install.sh)`
Expected: ends with `Installed to …/LaunchDashboard.app`.

- [ ] **Step 3: Manual verification (inspect URL)**

Click the menu-bar gauge icon. In the popover, `com.nors.ai-daemon` should show in accent color with a globe icon. Click it → browser opens `https://daemon.prebenhafnor.com`. Open its `⋯` menu → both "Open daemon.prebenhafnor.com" and "Open localhost:8787" appear.
Expected: confirmed.

- [ ] **Step 4: Manual verification (tunnel routes)**

In the popover footer, click "Tunnel routes…". A window opens listing the ingress hostnames from `~/.cloudflared/config.yml` with toggles; the `http_status:404` row shows "always on" and has no toggle. Toggle one host off → status line reads "Disabled … · tunnel reloaded", and `~/.dotfiles/.config/cloudflared/config.yml` now shows that rule commented out (`git -C ~/.dotfiles diff .config/cloudflared/config.yml`). Toggle it back on → the diff disappears (byte-identical restore).
Expected: confirmed.

- [ ] **Step 5: Update the README**

Add a short section to `tools/launch-dashboard/README.md` documenting both features. Insert after the "Prioritizing the services you care about" section:

```markdown
## Inspecting a service (open its URL)

Give a service a clickable URL by adding it to `inspectTargets` in `config.json`:

\```bash
CONFIG="$HOME/Library/Application Support/LaunchDashboard/config.json"
jq '.inspectTargets = {"com.nors.ai-daemon": {"public":"https://daemon.prebenhafnor.com","local":"http://localhost:8787"}}' \
  "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG" && chmod 600 "$CONFIG"
\```

The row's label turns into a link (globe icon); clicking it opens the **public**
URL. The row's `⋯` menu offers both the public and local URLs.

## Tunnel routes

The popover footer's **"Tunnel routes…"** button opens a window listing the
cloudflared ingress rules from `~/.cloudflared/config.yml`. Each hostname has an
on/off toggle; the catch-all (`http_status:404`) is always on. Toggling a route
comments/uncomments it in the config (written through the dotfiles symlink) and
reloads `com.prebenhafnor.cloudflared`. Changes appear as a git diff in dotfiles —
commit them when you're happy.
```

(Remove the backslashes before the inner code fences — they're only here to nest the block in this plan.)

- [ ] **Step 6: Commit**

```bash
git add tools/launch-dashboard/README.md
git commit -m "$(printf 'docs(launch-dashboard): document inspect URLs + tunnel routes\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Self-Review Notes

- **Spec coverage:** inspectTargets config + click-to-open + public/local menu (Tasks 1, 5, 9); separate routes window + footer entry (Tasks 6, 7, 8); comment-toggle semantics + symlink-aware atomic write + reload (Tasks 3, 4); catch-all read-only (Tasks 2, 7); error handling surfaced in window status (Task 7); tests for parser + config + controller (Tasks 1–4). Out-of-scope items (HTTP endpoints, add/remove routes) intentionally omitted.
- **Type consistency:** `InspectTarget {public, local}` with `publicURL/localURL/preferredURL`; `IngressRule {hostname, service, enabled, isCatchAll, lineRange}`; `IngressConfigParser.parse/toggle`; `CloudflaredController {configPath, runner, uid, cloudflaredLabel}` with `rules()`/`setEnabled(hostname:enabled:)`; `MenuBarController.init` and `ServicesView` both gain `onOpenURL`/`onOpenTunnelRoutes` — used consistently across Tasks 5, 6, 8.
- **Intermediate build states:** Tasks 5–7 intentionally leave the package non-compiling until Task 8 wires the new `MenuBarController` signature; each task still commits a coherent slice. The first fully-green build + full test run is Task 8.
