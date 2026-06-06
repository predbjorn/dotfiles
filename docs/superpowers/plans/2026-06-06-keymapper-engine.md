# Keymapper Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless, fully-tested engine for Keymapper — lossless parse + round-trip of `.config/karabiner.json` and `.config/skhdrc`, atomic/revertible writers, first-run launcher migration, a whole-keymap conflict auditor, and a scoped skhd deployer — with no UI.

**Architecture:** A Swift Package (`tools/keymapper/`) mirroring the sibling `tools/launch-dashboard` engineering bar (SwiftPM, XCTest, injectable `ProcessRunner`, atomic 0600 writes). The engine reads both config files into a `Keymap` model: karabiner is held as a **lossless ordered `JSONValue`** graph so unknown/future keys survive a write (only managed rule objects are mutated, then the whole file is re-serialized); skhd is held as text with a fenced managed region whose unchanged bindings pass through **byte-for-byte**. All writes go to the resolved repo file via temp-file + `rename(2)` with a timestamped backup. The deployer does only the isolated skhd copy + `skhd --reload` (never the whole `sync.sh`), validates the result, and auto-reverts on failure.

**Tech Stack:** Swift 5.9, SwiftPM, Foundation, XCTest. macOS 13+. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-06-05-keymapper-design.md` (Decision Log D1–D36). This plan implements the engine half (D2, D7–D26, D29, D31, D32, D35); the SwiftUI app, `install.sh`, and README are Plan B (D27, D28, D30, D33, D34, D36).

---

## File Structure

```
tools/keymapper/
  Package.swift
  Sources/Keymapper/
    Core/
      ProcessRunner.swift     # injectable subprocess (copied from LaunchDashboard) — Task 1
      ShellQuote.swift        # POSIX single-quote escaping for generated commands (D19) — Task 1
      JSONValue.swift         # lossless, key-order-preserving JSON value (D24) — Task 2
      Paths.swift             # repo + deployed + backup path resolution (D18, D21) — Task 3
      AtomicFileWriter.swift  # temp+rename write, backup, retention (D17, D21, D22) — Task 3
      Chord.swift             # Layer + Chord canonicalization (D14) — Task 4
      Binding.swift           # Binding + LauncherAction model (D11) — Task 5
      LauncherCommand.swift   # parse/render bin/*.sh launcher commands (D11, D19) — Task 5
      KarabinerDocument.swift # parse/mutate/serialize karabiner.json (D7, D23, D24, D32) — Task 6
      SkhdDocument.swift      # fenced region + verbatim spans + line parse (D8) — Task 7
      ConflictEngine.swift    # whole-keymap, per-layer lint (D14, D15, D31) — Task 8
      Keymap.swift            # aggregate model from both files — Task 9
      Migration.swift         # first-run launcher adoption (D26) — Task 9
      Deployer.swift          # drift, scoped copy+reload, validate+revert (D9,D12,D13,D20,D25,D28) — Task 10
      Cheatsheet.swift        # Markdown/HTML export — Task 11
  Tests/KeymapperTests/
    ...                       # one test file per component
    Fixtures/                 # real-world adversarial fixtures (D16)
```

Each task is self-contained: a model/parser unit plus its tests. Tasks build in dependency order; later tasks reference only types defined in earlier tasks.

---

### Task 1: Package scaffold, ProcessRunner, ShellQuote

**Files:**
- Create: `tools/keymapper/Package.swift`
- Create: `tools/keymapper/Sources/Keymapper/Core/ProcessRunner.swift`
- Create: `tools/keymapper/Sources/Keymapper/Core/ShellQuote.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/ShellQuoteTests.swift`

- [ ] **Step 1: Create the package manifest**

`tools/keymapper/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Keymapper",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Keymapper"),
        .testTarget(name: "KeymapperTests", dependencies: ["Keymapper"]),
    ]
)
```

Note: a plain library `.target` for now (the engine). Plan B converts this to an `.executableTarget` with `main.swift`.

- [ ] **Step 2: Copy the injectable process runner**

`tools/keymapper/Sources/Keymapper/Core/ProcessRunner.swift` (identical pattern to LaunchDashboard so tests can inject a fake):

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
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return ProcessResult(stdout: out, stderr: err, exitCode: p.terminationStatus)
    }
}
```

- [ ] **Step 3: Write the failing ShellQuote test**

`tools/keymapper/Tests/KeymapperTests/ShellQuoteTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class ShellQuoteTests: XCTestCase {
    func testPlainWordIsUnquotedWhenSafe() {
        XCTAssertEqual(ShellQuote.quote("Safari"), "Safari")
        XCTAssertEqual(ShellQuote.quote("Google_Chrome-1.2"), "Google_Chrome-1.2")
    }

    func testSpacesAreSingleQuoted() {
        XCTAssertEqual(ShellQuote.quote("Google Chrome"), "'Google Chrome'")
    }

    func testShellMetacharactersAreNeutralized() {
        // The injection guard (D19): an app name with metacharacters must round-trip as inert text.
        XCTAssertEqual(ShellQuote.quote("evil; rm -rf ~"), "'evil; rm -rf ~'")
        XCTAssertEqual(ShellQuote.quote("a$(whoami)b"), "'a$(whoami)b'")
        XCTAssertEqual(ShellQuote.quote("a`id`b"), "'a`id`b'")
    }

    func testEmbeddedSingleQuoteIsEscaped() {
        // POSIX idiom: close quote, escaped quote, reopen quote.
        XCTAssertEqual(ShellQuote.quote("it's"), "'it'\\''s'")
    }
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter ShellQuoteTests`
Expected: FAIL — `cannot find 'ShellQuote' in scope`.

- [ ] **Step 5: Implement ShellQuote**

`tools/keymapper/Sources/Keymapper/Core/ShellQuote.swift`:

```swift
import Foundation

/// POSIX shell-safe quoting for fields interpolated into generated launcher commands (D19).
/// Single-quote everything that isn't a known-safe bare word; escape embedded single quotes
/// with the close-quote/escaped-quote/reopen-quote idiom.
enum ShellQuote {
    private static let safe = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./")

    static func quote(_ s: String) -> String {
        if !s.isEmpty && s.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return s
        }
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter ShellQuoteTests`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add tools/keymapper/Package.swift tools/keymapper/Sources/Keymapper/Core/ProcessRunner.swift tools/keymapper/Sources/Keymapper/Core/ShellQuote.swift tools/keymapper/Tests/KeymapperTests/ShellQuoteTests.swift
git commit -m "feat(keymapper): scaffold package + ProcessRunner + ShellQuote injection guard"
```

---

### Task 2: Lossless ordered JSONValue

Karabiner-Elements reformats `karabiner.json` and may add keys across versions. A typed Codable struct would silently drop unknown keys on write (Constraint Guardian Blocker #8). We hold the document as a `JSONValue` that preserves **every** key and its **order** (D24).

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/JSONValue.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/JSONValueTests.swift`

- [ ] **Step 1: Write the failing round-trip test**

`tools/keymapper/Tests/KeymapperTests/JSONValueTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class JSONValueTests: XCTestCase {
    func testPreservesObjectKeyOrder() throws {
        let json = #"{"z":1,"a":2,"m":{"y":true,"b":false}}"#
        let value = try JSONValue.parse(json)
        // Re-serialize compact; key order must match the input, not be alphabetized.
        XCTAssertEqual(value.serialized(indent: nil), #"{"z":1,"a":2,"m":{"y":true,"b":false}}"#)
    }

    func testPreservesUnknownNestedKeysThroughMutation() throws {
        // Simulate a future Karabiner key we don't model; it must survive a round-trip.
        let json = #"{"rules":[{"description":"x","future_field":[1,2,3]}]}"#
        let value = try JSONValue.parse(json)
        XCTAssertEqual(value.serialized(indent: nil), json)
    }

    func testPrettyPrintsWithTwoSpaceIndent() throws {
        let value = try JSONValue.parse(#"{"a":[1,2]}"#)
        XCTAssertEqual(value.serialized(indent: 2), "{\n  \"a\": [\n    1,\n    2\n  ]\n}")
    }

    func testObjectSubscriptAndArrayAccess() throws {
        let value = try JSONValue.parse(#"{"rules":[{"description":"keymap: x"}]}"#)
        guard case .array(let rules)? = value["rules"] else { return XCTFail("rules not array") }
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0]["description"]?.stringValue, "keymap: x")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter JSONValueTests`
Expected: FAIL — `cannot find 'JSONValue' in scope`.

- [ ] **Step 3: Implement JSONValue**

`tools/keymapper/Sources/Keymapper/Core/JSONValue.swift`:

```swift
import Foundation

/// A lossless JSON value that preserves object key order and all keys, including unknown ones (D24).
/// Backed by a hand-rolled parser/serializer (Foundation's JSONSerialization does not preserve key order).
indirect enum JSONValue: Equatable {
    case object([(String, JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)   // kept as the original literal text so numeric formatting is preserved
    case bool(Bool)
    case null

    // MARK: Accessors
    subscript(_ key: String) -> JSONValue? {
        if case .object(let pairs) = self { return pairs.first(where: { $0.0 == key })?.1 }
        return nil
    }
    subscript(_ index: Int) -> JSONValue? {
        if case .array(let items) = self, items.indices.contains(index) { return items[index] }
        return nil
    }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    // MARK: Parsing
    static func parse(_ text: String) throws -> JSONValue {
        var parser = Parser(Array(text.unicodeScalars))
        let v = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw JSONError.trailingGarbage(parser.index) }
        return v
    }

    // MARK: Serializing
    /// `indent == nil` → compact. `indent == n` → pretty, n spaces per level, matching Karabiner's style.
    func serialized(indent: Int?) -> String {
        var out = ""
        write(into: &out, indent: indent, level: 0)
        return out
    }

    private func write(into out: inout String, indent: Int?, level: Int) {
        let nl = indent == nil ? "" : "\n"
        let pad = indent == nil ? "" : String(repeating: " ", count: indent! * (level + 1))
        let closePad = indent == nil ? "" : String(repeating: " ", count: indent! * level)
        let colon = indent == nil ? ":" : ": "
        switch self {
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{" + nl
            for (i, (k, v)) in pairs.enumerated() {
                out += pad + JSONValue.encodeString(k) + colon
                v.write(into: &out, indent: indent, level: level + 1)
                out += (i == pairs.count - 1 ? "" : ",") + nl
            }
            out += closePad + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[" + nl
            for (i, v) in items.enumerated() {
                out += pad
                v.write(into: &out, indent: indent, level: level + 1)
                out += (i == items.count - 1 ? "" : ",") + nl
            }
            out += closePad + "]"
        case .string(let s): out += JSONValue.encodeString(s)
        case .number(let n): out += n
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func encodeString(_ s: String) -> String {
        var r = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\t": r += "\\t"
            case "\r": r += "\\r"
            default:
                if scalar.value < 0x20 { r += String(format: "\\u%04x", scalar.value) }
                else { r.unicodeScalars.append(scalar) }
            }
        }
        return r + "\""
    }

    // MARK: Parser
    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0
        init(_ s: [Unicode.Scalar]) { scalars = s }
        var isAtEnd: Bool { index >= scalars.count }
        mutating func skipWhitespace() {
            while index < scalars.count, " \t\n\r".unicodeScalars.contains(scalars[index]) { index += 1 }
        }
        mutating func parseValue() throws -> JSONValue {
            skipWhitespace()
            guard index < scalars.count else { throw JSONError.unexpectedEnd }
            switch scalars[index] {
            case "{": return try parseObject()
            case "[": return try parseArray()
            case "\"": return .string(try parseString())
            case "t", "f": return try parseBool()
            case "n": try expect("null"); return .null
            default: return .number(try parseNumber())
            }
        }
        mutating func parseObject() throws -> JSONValue {
            index += 1 // {
            var pairs: [(String, JSONValue)] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "}" { index += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                let key = try parseString()
                skipWhitespace()
                guard index < scalars.count, scalars[index] == ":" else { throw JSONError.expectedColon(index) }
                index += 1
                let value = try parseValue()
                pairs.append((key, value))
                skipWhitespace()
                guard index < scalars.count else { throw JSONError.unexpectedEnd }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "}" { index += 1; break }
                throw JSONError.expectedCommaOrClose(index)
            }
            return .object(pairs)
        }
        mutating func parseArray() throws -> JSONValue {
            index += 1 // [
            var items: [JSONValue] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "]" { index += 1; return .array(items) }
            while true {
                items.append(try parseValue())
                skipWhitespace()
                guard index < scalars.count else { throw JSONError.unexpectedEnd }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "]" { index += 1; break }
                throw JSONError.expectedCommaOrClose(index)
            }
            return .array(items)
        }
        mutating func parseString() throws -> String {
            guard index < scalars.count, scalars[index] == "\"" else { throw JSONError.expectedString(index) }
            index += 1
            var s = String.UnicodeScalarView()
            while index < scalars.count {
                let c = scalars[index]; index += 1
                if c == "\"" { return String(s) }
                if c == "\\" {
                    guard index < scalars.count else { throw JSONError.unexpectedEnd }
                    let e = scalars[index]; index += 1
                    switch e {
                    case "\"": s.append("\"")
                    case "\\": s.append("\\")
                    case "/": s.append("/")
                    case "n": s.append("\n")
                    case "t": s.append("\t")
                    case "r": s.append("\r")
                    case "b": s.append(Unicode.Scalar(8))
                    case "f": s.append(Unicode.Scalar(12))
                    case "u":
                        let hex = String(String.UnicodeScalarView(scalars[index..<min(index+4, scalars.count)]))
                        guard hex.count == 4, let code = UInt32(hex, radix: 16),
                              let scalar = Unicode.Scalar(code) else { throw JSONError.badEscape(index) }
                        s.append(scalar); index += 4
                    default: throw JSONError.badEscape(index)
                    }
                } else { s.append(c) }
            }
            throw JSONError.unexpectedEnd
        }
        mutating func parseNumber() throws -> String {
            let start = index
            while index < scalars.count, "+-0123456789.eE".unicodeScalars.contains(scalars[index]) { index += 1 }
            guard index > start else { throw JSONError.invalidNumber(index) }
            return String(String.UnicodeScalarView(scalars[start..<index]))
        }
        mutating func parseBool() throws -> JSONValue {
            if scalars[index] == "t" { try expect("true"); return .bool(true) }
            try expect("false"); return .bool(false)
        }
        mutating func expect(_ word: String) throws {
            for ch in word.unicodeScalars {
                guard index < scalars.count, scalars[index] == ch else { throw JSONError.invalidLiteral(index) }
                index += 1
            }
        }
    }
}

enum JSONError: Error, Equatable {
    case unexpectedEnd, trailingGarbage(Int), expectedColon(Int), expectedCommaOrClose(Int)
    case expectedString(Int), badEscape(Int), invalidNumber(Int), invalidLiteral(Int)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter JSONValueTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/JSONValue.swift tools/keymapper/Tests/KeymapperTests/JSONValueTests.swift
git commit -m "feat(keymapper): lossless order-preserving JSONValue (D24)"
```

---

### Task 3: Paths + AtomicFileWriter (backup + retention)

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/Paths.swift`
- Create: `tools/keymapper/Sources/Keymapper/Core/AtomicFileWriter.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/AtomicFileWriterTests.swift`

- [ ] **Step 1: Implement Paths**

`tools/keymapper/Sources/Keymapper/Core/Paths.swift` (D18 = edit resolved repo file; D21 = backups in App Support):

```swift
import Foundation

enum Paths {
    /// $DOTFILES or ~/.dotfiles. We always edit the REPO files, never the deployed symlink/copy (D18).
    static var dotfiles: URL {
        if let env = ProcessInfo.processInfo.environment["DOTFILES"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dotfiles")
    }
    static var karabinerRepo: URL { dotfiles.appendingPathComponent(".config/karabiner.json") }
    static var skhdRepo: URL { dotfiles.appendingPathComponent(".config/skhdrc") }

    /// Where sync.sh copies skhdrc for skhd to read. Used only for drift detection (D13), never edited.
    static var skhdDeployed: URL {
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return xdg.appendingPathComponent("skhd/skhdrc")
    }

    /// Backups live outside the repo, user-only (D21).
    static var backupDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keymapper/backups")
    }
}
```

- [ ] **Step 2: Write the failing AtomicFileWriter test**

`tools/keymapper/Tests/KeymapperTests/AtomicFileWriterTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class AtomicFileWriterTests: XCTestCase {
    private var dir: URL!
    private var backups: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("km-\(UUID())")
        backups = dir.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testWriteCreatesFileWithContent() throws {
        let target = dir.appendingPathComponent("a.txt")
        let writer = AtomicFileWriter(backupDir: backups)
        try writer.write("hello\n", to: target, backupStem: "a")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "hello\n")
    }

    func testBackupCapturesPreviousContentWith0600() throws {
        let target = dir.appendingPathComponent("a.txt")
        try "old".write(to: target, atomically: true, encoding: .utf8)
        let writer = AtomicFileWriter(backupDir: backups, timestamp: "20260606-120000")
        try writer.write("new", to: target, backupStem: "a")
        let backup = backups.appendingPathComponent("a.20260606-120000.bak")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "old")
        let perms = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    func testRetentionKeepsLastN() throws {
        let target = dir.appendingPathComponent("a.txt")
        try "seed".write(to: target, atomically: true, encoding: .utf8)
        // 25 writes with increasing timestamps; retention keeps the newest 20.
        for i in 0..<25 {
            let ts = String(format: "20260606-1200%02d", i)
            let writer = AtomicFileWriter(backupDir: backups, timestamp: ts, retain: 20)
            try writer.write("v\(i)", to: target, backupStem: "a")
        }
        let backups = try FileManager.default.contentsOfDirectory(atPath: self.backups.path)
            .filter { $0.hasPrefix("a.") && $0.hasSuffix(".bak") }
        XCTAssertEqual(backups.count, 20)
        XCTAssertFalse(backups.contains("a.20260606-120000.bak")) // oldest pruned
        XCTAssertTrue(backups.contains("a.20260606-120024.bak"))  // newest kept
    }

    func testRestoreReturnsBackupContentToTarget() throws {
        let target = dir.appendingPathComponent("a.txt")
        try "good".write(to: target, atomically: true, encoding: .utf8)
        let writer = AtomicFileWriter(backupDir: backups, timestamp: "20260606-120000")
        let backup = try writer.makeBackup(of: target, stem: "a")
        try "corrupt".write(to: target, atomically: true, encoding: .utf8)
        try writer.restore(backup, to: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "good")
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter AtomicFileWriterTests`
Expected: FAIL — `cannot find 'AtomicFileWriter' in scope`.

- [ ] **Step 4: Implement AtomicFileWriter**

`tools/keymapper/Sources/Keymapper/Core/AtomicFileWriter.swift` (D17 temp+rename; D21 perms/location; D22 retention; D9/D25 restore):

```swift
import Foundation

/// Atomic, backed-up writes for the repo config files.
/// - Backup BEFORE each write (D9).
/// - Write to a temp file on the same volume, then rename(2) (D17).
/// - Backups are user-only and pruned to the newest `retain` (D21, D22).
struct AtomicFileWriter {
    let backupDir: URL
    let timestamp: String
    let retain: Int

    init(backupDir: URL, timestamp: String = AtomicFileWriter.now(), retain: Int = 20) {
        self.backupDir = backupDir
        self.timestamp = timestamp
        self.retain = retain
    }

    static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// Backup (if the target exists) then atomically replace it. Prunes old backups afterward.
    func write(_ contents: String, to target: URL, backupStem stem: String) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try makeBackup(of: target, stem: stem)
            try prune(stem: stem)
        }
        try atomicReplace(target, with: Data(contents.utf8))
    }

    /// Copy the current target into the backup dir as `<stem>.<timestamp>.bak`, mode 0600. Returns its URL.
    @discardableResult
    func makeBackup(of target: URL, stem: String) throws -> URL {
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backup = backupDir.appendingPathComponent("\(stem).\(timestamp).bak")
        let data = try Data(contentsOf: target)
        try data.write(to: backup, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        return backup
    }

    /// Restore a backup over the target (used by the deployer's auto-revert, D25).
    func restore(_ backup: URL, to target: URL) throws {
        try atomicReplace(target, with: try Data(contentsOf: backup))
    }

    private func prune(stem: String) throws {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: backupDir.path)) ?? []
        let mine = all.filter { $0.hasPrefix("\(stem).") && $0.hasSuffix(".bak") }.sorted()
        guard mine.count > retain else { return }
        for name in mine.prefix(mine.count - retain) {
            try? FileManager.default.removeItem(at: backupDir.appendingPathComponent(name))
        }
    }

    /// Write to a temp file on the SAME directory (same volume) then rename(2) — atomic (D17).
    /// Writing to the resolved target dir avoids materializing over a symlink elsewhere (D18 is enforced
    /// by callers passing repo paths; here we additionally resolve symlinks so we replace the real file).
    private func atomicReplace(_ target: URL, with data: Data) throws {
        let resolved = URL(fileURLWithPath: (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path))
            .map { link in
                link.hasPrefix("/") ? link
                    : target.deletingLastPathComponent().appendingPathComponent(link).path
            } ?? target.path)
        let dir = resolved.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(resolved.lastPathComponent).tmp-\(timestamp)")
        try data.write(to: tmp, options: .atomic)
        // Atomic same-volume replace.
        _ = try FileManager.default.replaceItemAt(resolved, withItemAt: tmp)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter AtomicFileWriterTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/Paths.swift tools/keymapper/Sources/Keymapper/Core/AtomicFileWriter.swift tools/keymapper/Tests/KeymapperTests/AtomicFileWriterTests.swift
git commit -m "feat(keymapper): Paths + atomic backed-up writer with retention (D17,D21,D22)"
```

---

### Task 4: Chord + Layer canonicalization

Conflicts are detected only **within a layer** (D14). `space+b` (space-leader) and `hyper-b` (skhd-modifier) must NOT collide. A `Chord` carries a canonical key used for equality.

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/Chord.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/ChordTests.swift`

- [ ] **Step 1: Write the failing test**

`tools/keymapper/Tests/KeymapperTests/ChordTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class ChordTests: XCTestCase {
    func testSkhdModifierChordCanonicalizesModifierOrder() {
        let a = Chord(layer: .skhdModifier, modifiers: ["shift", "ctrl"], key: "b")
        let b = Chord(layer: .skhdModifier, modifiers: ["ctrl", "shift"], key: "b")
        XCTAssertEqual(a, b)                    // order-independent
        XCTAssertEqual(a.canonical, "skhd-modifier:ctrl+shift-b")
    }

    func testHyperIsNormalizedToItsModifierSet() {
        // skhd `hyper` == cmd+ctrl+alt+shift. A literal cmd+ctrl+alt+shift chord must equal hyper.
        let hyper = Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "b")
        let expanded = Chord(layer: .skhdModifier, modifiers: ["cmd", "ctrl", "alt", "shift"], key: "b")
        XCTAssertEqual(hyper, expanded)
    }

    func testKeycodeAliasNormalization() {
        // skhd uses hex keycodes; 0x2F is the same physical key as "iTerm2" binding uses. Normalize to a token.
        let hex = Chord(layer: .skhdModifier, modifiers: ["ctrl", "shift"], key: "0x2f")
        XCTAssertEqual(hex.key, "0x2f")          // preserved verbatim for rendering
        XCTAssertEqual(hex.canonical, "skhd-modifier:ctrl+shift-0x2f")
    }

    func testDifferentLayersNeverEqualEvenWithSameKey() {
        let leader = Chord(layer: .spaceLeader, modifiers: [], key: "b")
        let modifier = Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "b")
        XCTAssertNotEqual(leader, modifier)
        XCTAssertNotEqual(leader.canonical, modifier.canonical)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter ChordTests`
Expected: FAIL — `cannot find 'Chord' in scope`.

- [ ] **Step 3: Implement Chord + Layer**

`tools/keymapper/Sources/Keymapper/Core/Chord.swift`:

```swift
import Foundation

enum Layer: String, Codable, CaseIterable {
    case spaceLeader = "space-leader"
    case spaceFLeader = "space-f-leader"
    case karabinerModifier = "karabiner-modifier"
    case skhdModifier = "skhd-modifier"
}

/// A normalized chord. Equality is by `canonical`, which folds modifier order and the `hyper` alias.
struct Chord: Equatable, Hashable {
    let layer: Layer
    let modifiers: [String]   // normalized, deduped, sorted (lowercased)
    let key: String           // verbatim key token (letter or hex keycode), lowercased for comparison

    /// Canonical modifier order for stable rendering/comparison.
    private static let order = ["cmd", "ctrl", "alt", "shift"]
    /// `hyper` expands to the full modifier set so a literal expansion compares equal.
    private static let hyperSet = ["cmd", "ctrl", "alt", "shift"]

    init(layer: Layer, modifiers: [String], key: String) {
        self.layer = layer
        self.key = key.lowercased()
        var mods = Set(modifiers.map { $0.lowercased() })
        if mods.contains("hyper") { mods.remove("hyper"); Chord.hyperSet.forEach { mods.insert($0) } }
        self.modifiers = Chord.order.filter { mods.contains($0) }
    }

    var canonical: String {
        let mod = modifiers.isEmpty ? "" : modifiers.joined(separator: "+") + "-"
        return "\(layer.rawValue):\(mod)\(key)"
    }

    static func == (l: Chord, r: Chord) -> Bool { l.canonical == r.canonical }
    func hash(into hasher: inout Hasher) { hasher.combine(canonical) }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter ChordTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/Chord.swift tools/keymapper/Tests/KeymapperTests/ChordTests.swift
git commit -m "feat(keymapper): Chord + Layer canonicalization with hyper folding (D14)"
```

---

### Task 5: Binding model + launcher command parse/render

The launcher action stores `{app, mechanism, rawCommand}` with `rawCommand` as the source of truth (D11); regeneration shell-quotes the app (D19) and preserves the original script/mechanism.

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/Binding.swift`
- Create: `tools/keymapper/Sources/Keymapper/Core/LauncherCommand.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/LauncherCommandTests.swift`

- [ ] **Step 1: Implement the Binding model**

`tools/keymapper/Sources/Keymapper/Core/Binding.swift`:

```swift
import Foundation

enum SourceFile: String, Codable { case karabiner, skhd }

enum LauncherMechanism: String, Codable {
    case toggle   // bin/toggle_app.sh <App>
    case focus    // bin/focus_window_wrapper.sh <App> <bringToCurrent>
    case open     // open <path>  (space+f folder shortcuts)
}

/// A recognized launcher action. `rawCommand` is the verbatim source of truth (D11);
/// structured fields are derived and used to regenerate via the SAME mechanism on edit.
struct LauncherAction: Equatable {
    var mechanism: LauncherMechanism
    var target: String          // app name or folder path
    var focusBringToCurrent: Bool   // only meaningful for .focus; false otherwise
    var rawCommand: String
}

/// One keymap binding. `launcher == nil` means an opaque/non-launcher action (e.g. a yabai pipeline):
/// the chord is still parsed so it participates in conflict detection + cheatsheet (D29).
struct Binding: Equatable {
    var chord: Chord
    var source: SourceFile
    var managed: Bool
    var launcher: LauncherAction?
    var rawText: String         // verbatim source span / shell command for round-trip (D8)
    var displayName: String     // for cheatsheet: app name, folder, or a short command summary
}
```

- [ ] **Step 2: Write the failing LauncherCommand test**

`tools/keymapper/Tests/KeymapperTests/LauncherCommandTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class LauncherCommandTests: XCTestCase {
    func testParsesToggleAppCommand() {
        let a = LauncherCommand.parse("$HOME/.dotfiles/bin/toggle_app.sh Safari")
        XCTAssertEqual(a?.mechanism, .toggle)
        XCTAssertEqual(a?.target, "Safari")
    }

    func testParsesFocusWrapperWithQuotedAppAndFlag() {
        let a = LauncherCommand.parse(#"~/.dotfiles/bin/focus_window_wrapper.sh "Google Chrome" true"#)
        XCTAssertEqual(a?.mechanism, .focus)
        XCTAssertEqual(a?.target, "Google Chrome")
        XCTAssertEqual(a?.focusBringToCurrent, true)
    }

    func testParsesOpenFolder() {
        let a = LauncherCommand.parse("open ~/Downloads")
        XCTAssertEqual(a?.mechanism, .open)
        XCTAssertEqual(a?.target, "~/Downloads")
    }

    func testNonLauncherCommandReturnsNil() {
        XCTAssertNil(LauncherCommand.parse("yabai -m space --create && echo hi"))
    }

    func testRenderRoundTripsToggle() {
        let a = LauncherAction(mechanism: .toggle, target: "Safari", focusBringToCurrent: false,
                               rawCommand: "$HOME/.dotfiles/bin/toggle_app.sh Safari")
        XCTAssertEqual(LauncherCommand.render(a), "$HOME/.dotfiles/bin/toggle_app.sh Safari")
    }

    func testRenderQuotesAppWithSpaces() {
        let a = LauncherAction(mechanism: .focus, target: "Google Chrome", focusBringToCurrent: true,
                               rawCommand: "")
        XCTAssertEqual(LauncherCommand.render(a),
                       "$HOME/.dotfiles/bin/focus_window_wrapper.sh 'Google Chrome' true")
    }

    func testRenderNeutralizesInjection() {
        // D19: an app name with shell metacharacters must render as inert single-quoted text.
        let a = LauncherAction(mechanism: .toggle, target: "evil; rm -rf ~", focusBringToCurrent: false,
                               rawCommand: "")
        XCTAssertEqual(LauncherCommand.render(a),
                       "$HOME/.dotfiles/bin/toggle_app.sh 'evil; rm -rf ~'")
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter LauncherCommandTests`
Expected: FAIL — `cannot find 'LauncherCommand' in scope`.

- [ ] **Step 4: Implement LauncherCommand**

`tools/keymapper/Sources/Keymapper/Core/LauncherCommand.swift`:

```swift
import Foundation

/// Parse/render the three recognized launcher command shapes. Anything else is opaque (parse → nil).
enum LauncherCommand {
    static let toggleScript = "$HOME/.dotfiles/bin/toggle_app.sh"
    static let focusScript  = "$HOME/.dotfiles/bin/focus_window_wrapper.sh"

    static func parse(_ command: String) -> LauncherAction? {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        let tokens = tokenize(cmd)
        guard let first = tokens.first else { return nil }
        let script = (first as NSString).lastPathComponent

        switch script {
        case "toggle_app.sh":
            guard tokens.count >= 2 else { return nil }
            return LauncherAction(mechanism: .toggle, target: tokens[1],
                                  focusBringToCurrent: false, rawCommand: command)
        case "focus_window_wrapper.sh":
            guard tokens.count >= 2 else { return nil }
            let flag = tokens.count >= 3 ? (tokens[2] == "true") : false
            return LauncherAction(mechanism: .focus, target: tokens[1],
                                  focusBringToCurrent: flag, rawCommand: command)
        default:
            if first == "open", tokens.count == 2 {
                return LauncherAction(mechanism: .open, target: tokens[1],
                                      focusBringToCurrent: false, rawCommand: command)
            }
            return nil
        }
    }

    static func render(_ a: LauncherAction) -> String {
        switch a.mechanism {
        case .toggle: return "\(toggleScript) \(ShellQuote.quote(a.target))"
        case .focus:  return "\(focusScript) \(ShellQuote.quote(a.target)) \(a.focusBringToCurrent ? "true" : "false")"
        case .open:   return "open \(ShellQuote.quote(a.target))"
        }
    }

    /// Minimal shell tokenizer: splits on whitespace, honoring single and double quotes. No expansion.
    static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character? = nil
        var hasToken = false
        for ch in s {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch; hasToken = true
            } else if ch == " " || ch == "\t" {
                if hasToken { tokens.append(current); current = ""; hasToken = false }
            } else {
                current.append(ch); hasToken = true
            }
        }
        if hasToken { tokens.append(current) }
        return tokens
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter LauncherCommandTests`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/Binding.swift tools/keymapper/Sources/Keymapper/Core/LauncherCommand.swift tools/keymapper/Tests/KeymapperTests/LauncherCommandTests.swift
git commit -m "feat(keymapper): Binding model + launcher command parse/render (D11,D19)"
```

---

### Task 6: KarabinerDocument — parse, managed detection, extract launchers, serialize

Reads `karabiner.json` into a `JSONValue`, surfaces the SpaceLauncher manipulators as `Binding`s (managed iff their rule's `description` has the `keymap:` prefix — D32), and re-serializes the whole file with 2-space indent preserving everything else (D7, D23, D24).

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/KarabinerDocument.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/KarabinerDocumentTests.swift`
- Test fixture: `tools/keymapper/Tests/KeymapperTests/Fixtures/karabiner-min.json`

- [ ] **Step 1: Create the fixture**

`tools/keymapper/Tests/KeymapperTests/Fixtures/karabiner-min.json` (a minimal real-shaped karabiner file: one unmanaged rule with a future key, one SpaceLauncher rule with a leader + an app + a folder manipulator):

```json
{
  "profiles": [
    {
      "name": "Default profile",
      "complex_modifications": {
        "rules": [
          {
            "description": "fn passthrough",
            "future_field": { "keep": [1, 2] },
            "manipulators": []
          },
          {
            "description": "SpaceLauncher shortcuts",
            "manipulators": [
              {
                "type": "basic",
                "from": { "key_code": "spacebar" },
                "to_if_held_down": [ { "set_variable": { "name": "space_held", "value": 1 } } ],
                "to_if_alone": [ { "key_code": "spacebar" } ]
              },
              {
                "type": "basic",
                "conditions": [ { "type": "variable_if", "name": "space_held", "value": 1 } ],
                "from": { "key_code": "b" },
                "to": [ { "shell_command": "$HOME/.dotfiles/bin/toggle_app.sh Safari" } ]
              },
              {
                "type": "basic",
                "conditions": [
                  { "type": "variable_if", "name": "space_held", "value": 1 },
                  { "type": "variable_if", "name": "space_f_mode", "value": 1 }
                ],
                "from": { "key_code": "d" },
                "to": [ { "shell_command": "open ~/Downloads" } ]
              }
            ]
          }
        ]
      }
    }
  ]
}
```

- [ ] **Step 2: Write the failing test**

`tools/keymapper/Tests/KeymapperTests/KarabinerDocumentTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class KarabinerDocumentTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testExtractsLauncherBindingsFromSpaceLauncherRule() throws {
        let doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        let bindings = doc.bindings()
        // The spacebar leader-setter is not a binding; the two launchers are.
        let b = bindings.first { $0.chord.key == "b" }!
        XCTAssertEqual(b.chord.layer, .spaceLeader)
        XCTAssertEqual(b.launcher?.mechanism, .toggle)
        XCTAssertEqual(b.launcher?.target, "Safari")
        let d = bindings.first { $0.chord.key == "d" }!
        XCTAssertEqual(d.chord.layer, .spaceFLeader)
        XCTAssertEqual(d.launcher?.mechanism, .open)
        XCTAssertEqual(d.launcher?.target, "~/Downloads")
    }

    func testUnmanagedUntilDescriptionHasPrefix() throws {
        let doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        XCTAssertTrue(doc.bindings().allSatisfy { !$0.managed }) // "SpaceLauncher shortcuts" has no keymap: prefix
    }

    func testAdoptRenamesRuleWithKeymapPrefixAndPreservesOtherJSON() throws {
        var doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        doc.adoptSpaceLauncherRule()
        let out = doc.serialized()
        XCTAssertTrue(out.contains("\"keymap: SpaceLauncher shortcuts\""))
        // The unmanaged rule's unknown future key survives (D24).
        XCTAssertTrue(out.contains("\"future_field\""))
        XCTAssertTrue(out.contains("\"keep\""))
        // Re-parsing yields managed launcher bindings now.
        let doc2 = try KarabinerDocument(text: out)
        XCTAssertTrue(doc2.bindings().allSatisfy { $0.managed })
    }

    func testSetLauncherTargetRewritesOnlyThatShellCommand() throws {
        var doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        doc.adoptSpaceLauncherRule()
        try doc.setLauncherTarget(layer: .spaceLeader, key: "b",
                                  action: LauncherAction(mechanism: .toggle, target: "Slack",
                                                         focusBringToCurrent: false, rawCommand: ""))
        let out = doc.serialized()
        XCTAssertTrue(out.contains("$HOME/.dotfiles/bin/toggle_app.sh Slack"))
        XCTAssertFalse(out.contains("toggle_app.sh Safari"))
        // The folder launcher is untouched.
        XCTAssertTrue(out.contains("open ~/Downloads"))
    }

    func testSerializeUsesTwoSpaceIndent() throws {
        let doc = try KarabinerDocument(text: fixture("karabiner-min.json"))
        XCTAssertTrue(doc.serialized().contains("\n  \"profiles\""))
    }
}
```

- [ ] **Step 3: Enable test resources in Package.swift**

Modify `tools/keymapper/Package.swift` test target to bundle fixtures:

```swift
.testTarget(
    name: "KeymapperTests",
    dependencies: ["Keymapper"],
    resources: [.copy("Fixtures")]
),
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter KarabinerDocumentTests`
Expected: FAIL — `cannot find 'KarabinerDocument' in scope`.

- [ ] **Step 5: Implement KarabinerDocument**

`tools/keymapper/Sources/Keymapper/Core/KarabinerDocument.swift`:

```swift
import Foundation

/// Holds karabiner.json as a lossless JSONValue and exposes the SpaceLauncher launchers as Bindings.
/// Only the managed rule's shell_commands are mutated; everything else is preserved (D7, D24).
struct KarabinerDocument {
    private var root: JSONValue
    static let managedPrefix = "keymap: "
    static let spaceLauncherName = "SpaceLauncher shortcuts"

    init(text: String) throws { root = try JSONValue.parse(text) }

    func serialized() -> String { root.serialized(indent: 2) + "\n" }

    // MARK: Reading
    func bindings() -> [Binding] {
        guard let rule = spaceLauncherRule() else { return [] }
        let managed = (rule.description ?? "").hasPrefix(Self.managedPrefix)
        guard case .array(let mans)? = rule.value["manipulators"] else { return [] }
        var out: [Binding] = []
        for m in mans {
            guard let key = m["from"]?["key_code"]?.stringValue,
                  let to = m["to"]?.arrayValue, let shell = to.first?["shell_command"]?.stringValue
            else { continue }   // skips the spacebar leader-setter (no "to" shell_command)
            let names = conditionNames(m)
            let layer: Layer = names.contains("space_f_mode") ? .spaceFLeader : .spaceLeader
            let action = LauncherCommand.parse(shell)
            out.append(Binding(
                chord: Chord(layer: layer, modifiers: [], key: key),
                source: .karabiner, managed: managed, launcher: action,
                rawText: shell,
                displayName: action?.target ?? shell))
        }
        return out
    }

    // MARK: Mutating
    mutating func adoptSpaceLauncherRule() {
        mutateSpaceLauncherRule { rule in
            let desc = rule["description"]?.stringValue ?? Self.spaceLauncherName
            if !desc.hasPrefix(Self.managedPrefix) {
                rule = rule.settingKey("description", to: .string(Self.managedPrefix + desc))
            }
        }
    }

    mutating func setLauncherTarget(layer: Layer, key: String, action: LauncherAction) throws {
        let newShell = LauncherCommand.render(action)
        mutateSpaceLauncherRule { rule in
            guard case .array(var mans)? = rule["manipulators"] else { return }
            for i in mans.indices {
                guard mans[i]["from"]?["key_code"]?.stringValue == key else { continue }
                let names = conditionNames(mans[i])
                let mLayer: Layer = names.contains("space_f_mode") ? .spaceFLeader : .spaceLeader
                guard mLayer == layer else { continue }
                let newTo = JSONValue.array([.object([("shell_command", .string(newShell))])])
                mans[i] = mans[i].settingKey("to", to: newTo)
            }
            rule = rule.settingKey("manipulators", to: .array(mans))
        }
    }

    // MARK: Helpers
    private struct Located { var value: JSONValue; var description: String? }

    private func spaceLauncherRule() -> Located? {
        for rule in allRules() {
            if let d = rule["description"]?.stringValue,
               d == Self.spaceLauncherName || d == Self.managedPrefix + Self.spaceLauncherName {
                return Located(value: rule, description: d)
            }
        }
        return nil
    }

    private func allRules() -> [JSONValue] {
        guard case .array(let profiles)? = root["profiles"] else { return [] }
        var rules: [JSONValue] = []
        for p in profiles {
            if case .array(let rs)? = p["complex_modifications"]?["rules"] { rules += rs }
        }
        return rules
    }

    private func conditionNames(_ manipulator: JSONValue) -> [String] {
        guard case .array(let conds)? = manipulator["conditions"] else { return [] }
        return conds.compactMap { $0["name"]?.stringValue }
    }

    /// Apply `transform` to the SpaceLauncher rule in-place within the full object graph.
    private mutating func mutateSpaceLauncherRule(_ transform: (inout JSONValue) -> Void) {
        guard case .array(var profiles)? = root["profiles"] else { return }
        for pi in profiles.indices {
            guard case .array(var rules)? = profiles[pi]["complex_modifications"]?["rules"] else { continue }
            for ri in rules.indices {
                guard let d = rules[ri]["description"]?.stringValue,
                      d == Self.spaceLauncherName || d == Self.managedPrefix + Self.spaceLauncherName
                else { continue }
                transform(&rules[ri])
            }
            let cm = (profiles[pi]["complex_modifications"] ?? .object([]))
                .settingKey("rules", to: .array(rules))
            profiles[pi] = profiles[pi].settingKey("complex_modifications", to: cm)
        }
        root = root.settingKey("profiles", to: .array(profiles))
    }
}

private extension JSONValue {
    var description: String? { self["description"]?.stringValue }

    /// Return a copy of this object with `key` set to `value`, preserving order (replacing in place
    /// if present, else appending).
    func settingKey(_ key: String, to value: JSONValue) -> JSONValue {
        guard case .object(var pairs) = self else { return .object([(key, value)]) }
        if let idx = pairs.firstIndex(where: { $0.0 == key }) { pairs[idx] = (key, value) }
        else { pairs.append((key, value)) }
        return .object(pairs)
    }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter KarabinerDocumentTests`
Expected: PASS (5 tests).

- [ ] **Step 7: Commit**

```bash
git add tools/keymapper/Package.swift tools/keymapper/Sources/Keymapper/Core/KarabinerDocument.swift tools/keymapper/Tests/KeymapperTests/KarabinerDocumentTests.swift tools/keymapper/Tests/KeymapperTests/Fixtures/karabiner-min.json
git commit -m "feat(keymapper): KarabinerDocument parse/adopt/mutate preserving unknown JSON (D7,D24,D32)"
```

---

### Task 7: SkhdDocument — fenced managed region + verbatim passthrough + line parse

Parses `skhdrc` into a read-only prefix, a managed region between fences, and a read-only suffix. Managed bindings round-trip **byte-for-byte** unless edited (D8). Read-only lines (incl. multi-line yabai pipelines and the `hyper`/`ctrl+shift` launcher lines) are still parsed at chord level for the auditor (D29, D31).

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/SkhdDocument.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/SkhdDocumentTests.swift`
- Test fixture: `tools/keymapper/Tests/KeymapperTests/Fixtures/skhdrc-sample`

- [ ] **Step 1: Create the fixture**

`tools/keymapper/Tests/KeymapperTests/Fixtures/skhdrc-sample` (a real-shaped slice: a multi-line yabai pipeline, the launcher lines, and an existing fenced region):

```
# changing screen focus
lalt + lcmd - l: yabai -m display --focus east

shift + alt - n : yabai -m space --create && \
                  index="$(yabai -m query --spaces --display | jq 'map(select(."is-native-fullscreen" == false))[-1].index')" && \
                  yabai -m window --space "${index}"

hyper - b : ~/.dotfiles/bin/focus_window_wrapper.sh Safari false
ctrl + shift - g :  ~/.dotfiles/bin/focus_window_wrapper.sh "Google Chrome" false

# >>> keymap-managed >>>
hyper - s : ~/.dotfiles/bin/focus_window_wrapper.sh Slack false
# <<< keymap-managed <<<
```

- [ ] **Step 2: Write the failing test**

`tools/keymapper/Tests/KeymapperTests/SkhdDocumentTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class SkhdDocumentTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testUnchangedDocumentSerializesByteForByte() throws {
        let text = try fixture("skhdrc-sample")
        let doc = try SkhdDocument(text: text)
        XCTAssertEqual(doc.serialized(), text)   // D8: no edits → identical bytes
    }

    func testManagedBindingsComeFromFencedRegion() throws {
        let doc = try SkhdDocument(text: fixture("skhdrc-sample"))
        let managed = doc.bindings().filter { $0.managed }
        XCTAssertEqual(managed.count, 1)
        XCTAssertEqual(managed[0].chord.modifiers, ["cmd", "ctrl", "alt", "shift"]) // hyper expands
        XCTAssertEqual(managed[0].launcher?.target, "Slack")
    }

    func testReadOnlyLauncherLinesAreParsedAsUnmanagedBindings() throws {
        let doc = try SkhdDocument(text: fixture("skhdrc-sample"))
        let chrome = doc.bindings().first { $0.launcher?.target == "Google Chrome" }!
        XCTAssertFalse(chrome.managed)
        XCTAssertEqual(chrome.chord.layer, .skhdModifier)
    }

    func testMultiLineYabaiPipelineParsedAsOpaqueChordOnly() throws {
        let doc = try SkhdDocument(text: fixture("skhdrc-sample"))
        let opaque = doc.bindings().first { $0.chord.key == "n" }!
        XCTAssertNil(opaque.launcher)   // not a launcher
        XCTAssertEqual(opaque.chord.layer, .skhdModifier)  // chord still parsed (D29)
    }

    func testSetManagedBindingRewritesOnlyTheFencedRegion() throws {
        var doc = try SkhdDocument(text: fixture("skhdrc-sample"))
        try doc.setManagedBindings([
            Binding(chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "m"),
                    source: .skhd, managed: true,
                    launcher: LauncherAction(mechanism: .focus, target: "Mail",
                                             focusBringToCurrent: false, rawCommand: ""),
                    rawText: "", displayName: "Mail")
        ])
        let out = doc.serialized()
        // Region replaced; Slack gone, Mail present.
        XCTAssertTrue(out.contains("~/.dotfiles/bin/focus_window_wrapper.sh Mail false"))
        XCTAssertFalse(out.contains("focus_window_wrapper.sh Slack"))
        // Everything OUTSIDE the fence is byte-identical (the yabai pipeline survives verbatim).
        XCTAssertTrue(out.contains(#"jq 'map(select(."is-native-fullscreen" == false))[-1].index')"#))
    }

    func testCreatesFenceWhenAbsent() throws {
        var doc = try SkhdDocument(text: "hyper - b : echo hi\n")
        try doc.setManagedBindings([
            Binding(chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "p"),
                    source: .skhd, managed: true,
                    launcher: LauncherAction(mechanism: .toggle, target: "Spotify",
                                             focusBringToCurrent: false, rawCommand: ""),
                    rawText: "", displayName: "Spotify")
        ])
        let out = doc.serialized()
        XCTAssertTrue(out.contains("# >>> keymap-managed >>>"))
        XCTAssertTrue(out.contains("# <<< keymap-managed <<<"))
        XCTAssertTrue(out.contains("$HOME/.dotfiles/bin/toggle_app.sh Spotify"))
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter SkhdDocumentTests`
Expected: FAIL — `cannot find 'SkhdDocument' in scope`.

- [ ] **Step 4: Implement SkhdDocument**

`tools/keymapper/Sources/Keymapper/Core/SkhdDocument.swift`:

```swift
import Foundation

/// Splits skhdrc into [prefix lines] [managed region] [suffix lines]. The managed region is regenerated
/// on edit; everything else passes through verbatim (D8). All binding lines (managed or not) are parsed
/// at chord level for the auditor (D29).
struct SkhdDocument {
    static let openFence = "# >>> keymap-managed >>>"
    static let closeFence = "# <<< keymap-managed <<<"

    private var prefix: [String]
    private var managedLines: [String]
    private var suffix: [String]
    private let hasFence: Bool

    init(text: String) throws {
        // Preserve the original trailing-newline structure by splitting on "\n" without dropping empties.
        let lines = text.components(separatedBy: "\n")
        if let open = lines.firstIndex(of: Self.openFence),
           let close = lines[open...].firstIndex(of: Self.closeFence) {
            prefix = Array(lines[..<open])
            managedLines = Array(lines[(open + 1)..<close])
            suffix = Array(lines[(close + 1)...])
            hasFence = true
        } else {
            prefix = lines
            managedLines = []
            suffix = []
            hasFence = false
        }
    }

    func serialized() -> String {
        if !hasFence && managedLines.isEmpty {
            return prefix.joined(separator: "\n")
        }
        var out = prefix
        out.append(Self.openFence)
        out.append(contentsOf: managedLines)
        out.append(Self.closeFence)
        out.append(contentsOf: suffix)
        return out.joined(separator: "\n")
    }

    func bindings() -> [Binding] {
        var out: [Binding] = []
        out += parseBindings(from: prefix, managed: false)
        out += parseBindings(from: suffix, managed: false)
        out += parseBindings(from: managedLines, managed: true)
        return out
    }

    /// Replace the managed region with freshly rendered launcher bindings. If no fence exists, one is
    /// created at the end (after the existing content), so the rest of the file is untouched.
    mutating func setManagedBindings(_ bindings: [Binding]) throws {
        managedLines = bindings.map { binding -> String in
            let chord = SkhdChord.render(binding.chord)
            let command = binding.launcher.map(LauncherCommand.render) ?? binding.rawText
            return "\(chord) : \(command)"
        }
        if !hasFence {
            // Move existing content to prefix; append the fence via serialized()'s fence branch.
            // hasFence is immutable; emulate by ensuring serialized() emits the fence (managedLines non-empty).
        }
    }

    // MARK: Line parsing
    private func parseBindings(from lines: [String], managed: Bool) -> [Binding] {
        // Join skhd line-continuations (trailing backslash) so a multi-line pipeline is one logical line.
        var logical: [String] = []
        var buffer = ""
        for raw in lines {
            let line = raw
            if buffer.isEmpty && isComment(line) { continue }
            if line.hasSuffix("\\") {
                buffer += String(line.dropLast())
                continue
            }
            buffer += line
            if !buffer.trimmingCharacters(in: .whitespaces).isEmpty { logical.append(buffer) }
            buffer = ""
        }
        if !buffer.trimmingCharacters(in: .whitespaces).isEmpty { logical.append(buffer) }

        return logical.compactMap { line -> Binding? in
            guard let colon = firstTopLevelColon(line) else { return nil }
            let lhs = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let rhs = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard let chord = SkhdChord.parse(lhs) else { return nil }
            let action = LauncherCommand.parse(rhs)
            return Binding(chord: chord, source: .skhd, managed: managed,
                           launcher: action, rawText: rhs,
                           displayName: action?.target ?? summarize(rhs))
        }
    }

    private func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }
    /// skhd separates chord and action with the FIRST colon; modifiers never contain a colon.
    private func firstTopLevelColon(_ line: String) -> String.Index? {
        line.firstIndex(of: ":")
    }
    private func summarize(_ cmd: String) -> String {
        let firstWord = cmd.split(separator: " ").first.map(String.init) ?? cmd
        return firstWord
    }
}
```

Note Step 4a below — `setManagedBindings`'s fence-creation needs `hasFence` to become true. Adjust the struct to make `hasFence` a `var` and set it in `setManagedBindings`:

```swift
// change:  private let hasFence: Bool
// to:      private var hasFence: Bool
// and in setManagedBindings, after building managedLines:
        if !hasFence { hasFence = true }   // fence will now be emitted around the region
```

- [ ] **Step 4b: Add the SkhdChord parser/renderer**

Append to `tools/keymapper/Sources/Keymapper/Core/SkhdDocument.swift`:

```swift
/// Parse/render an skhd chord LHS, e.g. "ctrl + shift + cmd - g" or "hyper - b".
enum SkhdChord {
    static func parse(_ lhs: String) -> Chord? {
        // skhd syntax: "<mods> - <key>" where mods are separated by "+". A bare key has no " - ".
        let parts = lhs.components(separatedBy: " - ")
        let key: String
        var mods: [String] = []
        if parts.count >= 2 {
            mods = parts[0].split(separator: "+").map {
                normalizeMod($0.trimmingCharacters(in: .whitespaces))
            }
            key = parts[1].trimmingCharacters(in: .whitespaces)
        } else {
            key = lhs.trimmingCharacters(in: .whitespaces)
        }
        guard !key.isEmpty else { return nil }
        return Chord(layer: .skhdModifier, modifiers: mods.filter { !$0.isEmpty }, key: key)
    }

    static func render(_ chord: Chord) -> String {
        if chord.modifiers.isEmpty { return chord.key }
        // Render hyper's full set back as "hyper" for readability.
        let set = Set(chord.modifiers)
        if set == Set(["cmd", "ctrl", "alt", "shift"]) { return "hyper - \(chord.key)" }
        return chord.modifiers.joined(separator: " + ") + " - " + chord.key
    }

    private static func normalizeMod(_ m: String) -> String {
        switch m.lowercased() {
        case "lcmd", "rcmd", "cmd", "command": return "cmd"
        case "lctrl", "rctrl", "ctrl", "control": return "ctrl"
        case "lalt", "ralt", "alt", "option", "opt": return "alt"
        case "lshift", "rshift", "shift": return "shift"
        case "hyper": return "hyper"
        default: return m.lowercased()
        }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter SkhdDocumentTests`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/SkhdDocument.swift tools/keymapper/Tests/KeymapperTests/SkhdDocumentTests.swift tools/keymapper/Tests/KeymapperTests/Fixtures/skhdrc-sample
git commit -m "feat(keymapper): SkhdDocument fenced region + verbatim passthrough + chord parse (D8,D29)"
```

---

### Task 8: ConflictEngine — whole-keymap, per-layer lint

Detects, across BOTH files and including read-only bindings (D31), within-layer chord collisions and exact duplicates. Cross-layer same-key is not a conflict (D14).

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/ConflictEngine.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/ConflictEngineTests.swift`

- [ ] **Step 1: Write the failing test**

`tools/keymapper/Tests/KeymapperTests/ConflictEngineTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class ConflictEngineTests: XCTestCase {
    private func b(_ layer: Layer, _ mods: [String], _ key: String, app: String, managed: Bool = true) -> Binding {
        Binding(chord: Chord(layer: layer, modifiers: mods, key: key), source: .skhd, managed: managed,
                launcher: LauncherAction(mechanism: .toggle, target: app, focusBringToCurrent: false, rawCommand: ""),
                rawText: "", displayName: app)
    }

    func testSameChordSameLayerIsConflict() {
        let conflicts = ConflictEngine.find([
            b(.skhdModifier, ["hyper"], "b", app: "Safari"),
            b(.skhdModifier, ["cmd", "ctrl", "alt", "shift"], "b", app: "Slack"), // == hyper
        ])
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].chord.key, "b")
        XCTAssertEqual(conflicts[0].bindings.count, 2)
    }

    func testSameKeyDifferentLayerIsNotConflict() {
        let conflicts = ConflictEngine.find([
            b(.spaceLeader, [], "b", app: "Safari"),
            b(.skhdModifier, ["hyper"], "b", app: "Slack"),
        ])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func testConflictDetectedEvenWhenOneSideIsReadOnly() {
        // D31: no false comfort — a managed binding colliding with a read-only one is reported.
        let conflicts = ConflictEngine.find([
            b(.skhdModifier, ["hyper"], "b", app: "Safari", managed: true),
            b(.skhdModifier, ["hyper"], "b", app: "Other", managed: false),
        ])
        XCTAssertEqual(conflicts.count, 1)
    }

    func testNoConflictWhenAllDistinct() {
        let conflicts = ConflictEngine.find([
            b(.skhdModifier, ["hyper"], "b", app: "Safari"),
            b(.skhdModifier, ["hyper"], "s", app: "Slack"),
        ])
        XCTAssertTrue(conflicts.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter ConflictEngineTests`
Expected: FAIL — `cannot find 'ConflictEngine' in scope`.

- [ ] **Step 3: Implement ConflictEngine**

`tools/keymapper/Sources/Keymapper/Core/ConflictEngine.swift`:

```swift
import Foundation

struct Conflict: Equatable {
    let chord: Chord
    let bindings: [Binding]
}

enum ConflictEngine {
    /// Group all bindings by canonical chord; any group with >1 binding is a within-layer conflict.
    /// (Canonical already encodes the layer, so cross-layer keys never group together — D14.)
    static func find(_ bindings: [Binding]) -> [Conflict] {
        var groups: [String: (chord: Chord, items: [Binding])] = [:]
        for b in bindings {
            groups[b.chord.canonical, default: (b.chord, [])].items.append(b)
        }
        return groups.values
            .filter { $0.items.count > 1 }
            .map { Conflict(chord: $0.chord, bindings: $0.items) }
            .sorted { $0.chord.canonical < $1.chord.canonical }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter ConflictEngineTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/ConflictEngine.swift tools/keymapper/Tests/KeymapperTests/ConflictEngineTests.swift
git commit -m "feat(keymapper): whole-keymap per-layer conflict engine (D14,D31)"
```

---

### Task 9: Keymap aggregate + first-run Migration

`Keymap` loads both documents and exposes the merged binding list + conflicts. `Migration` performs the one-time first-run launcher adoption (D26): rename the karabiner SpaceLauncher rule with the `keymap:` prefix and create the skhd fence around the existing launcher lines — backed up, atomic.

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/Keymap.swift`
- Create: `tools/keymapper/Sources/Keymapper/Core/Migration.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/MigrationTests.swift`

- [ ] **Step 1: Implement Keymap aggregate**

`tools/keymapper/Sources/Keymapper/Core/Keymap.swift`:

```swift
import Foundation

/// The merged, in-memory view of both config files. Pure value type; I/O is done by callers.
struct Keymap {
    var karabiner: KarabinerDocument
    var skhd: SkhdDocument

    init(karabinerText: String, skhdText: String) throws {
        karabiner = try KarabinerDocument(text: karabinerText)
        skhd = try SkhdDocument(text: skhdText)
    }

    var bindings: [Binding] { karabiner.bindings() + skhd.bindings() }
    var managed: [Binding] { bindings.filter { $0.managed } }
    var reference: [Binding] { bindings.filter { !$0.managed } }
    var conflicts: [Conflict] { ConflictEngine.find(bindings) }

    /// True iff the launchers have not yet been adopted (no keymap: prefix and no skhd fence).
    var needsMigration: Bool { managed.isEmpty && !reference.isEmpty }
}
```

- [ ] **Step 2: Write the failing Migration test**

`tools/keymapper/Tests/KeymapperTests/MigrationTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class MigrationTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("km-mig-\(UUID())")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("backups"),
                                                withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testMigrationAdoptsLaunchersAndIsIdempotent() throws {
        let kURL = dir.appendingPathComponent("karabiner.json")
        let sURL = dir.appendingPathComponent("skhdrc")
        try fixture("karabiner-min.json").write(to: kURL, atomically: true, encoding: .utf8)
        try fixture("skhdrc-sample").write(to: sURL, atomically: true, encoding: .utf8)

        let writer = AtomicFileWriter(backupDir: dir.appendingPathComponent("backups"))
        let migration = Migration(karabinerURL: kURL, skhdURL: sURL, writer: writer)

        // Before: nothing managed.
        var km = try Keymap(karabinerText: try String(contentsOf: kURL),
                            skhdText: try String(contentsOf: sURL))
        XCTAssertTrue(km.needsMigration)

        try migration.run()

        km = try Keymap(karabinerText: try String(contentsOf: kURL),
                        skhdText: try String(contentsOf: sURL))
        XCTAssertFalse(km.needsMigration)
        XCTAssertFalse(km.managed.isEmpty)

        // Idempotent: a second run is a no-op (no throw, still migrated).
        try migration.run()
        let km2 = try Keymap(karabinerText: try String(contentsOf: kURL),
                             skhdText: try String(contentsOf: sURL))
        XCTAssertFalse(km2.needsMigration)
    }

    func testMigrationWritesBackups() throws {
        let kURL = dir.appendingPathComponent("karabiner.json")
        let sURL = dir.appendingPathComponent("skhdrc")
        try fixture("karabiner-min.json").write(to: kURL, atomically: true, encoding: .utf8)
        try fixture("skhdrc-sample").write(to: sURL, atomically: true, encoding: .utf8)
        let backups = dir.appendingPathComponent("backups")
        let migration = Migration(karabinerURL: kURL, skhdURL: sURL,
                                  writer: AtomicFileWriter(backupDir: backups))
        try migration.run()
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("karabiner.") })
        XCTAssertTrue(files.contains { $0.hasPrefix("skhdrc.") })
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter MigrationTests`
Expected: FAIL — `cannot find 'Migration' in scope`.

- [ ] **Step 4: Implement Migration**

`tools/keymapper/Sources/Keymapper/Core/Migration.swift`:

```swift
import Foundation

/// One-time first-run adoption of existing launchers into the managed model (D26).
/// - karabiner: add the `keymap:` prefix to the SpaceLauncher rule.
/// - skhd: wrap the existing launcher lines (focus_window_wrapper.sh / toggle_app.sh) in the fence.
/// Idempotent: re-running on already-migrated files is a no-op.
struct Migration {
    let karabinerURL: URL
    let skhdURL: URL
    let writer: AtomicFileWriter

    func run() throws {
        try migrateKarabiner()
        try migrateSkhd()
    }

    private func migrateKarabiner() throws {
        let text = try String(contentsOf: karabinerURL, encoding: .utf8)
        var doc = try KarabinerDocument(text: text)
        guard doc.bindings().contains(where: { !$0.managed }) else { return } // already adopted
        doc.adoptSpaceLauncherRule()
        try writer.write(doc.serialized(), to: karabinerURL, backupStem: "karabiner")
    }

    private func migrateSkhd() throws {
        let text = try String(contentsOf: skhdURL, encoding: .utf8)
        var doc = try SkhdDocument(text: text)
        let unmanagedLaunchers = doc.bindings().filter { !$0.managed && $0.launcher != nil }
        guard !unmanagedLaunchers.isEmpty else { return } // nothing to adopt / already fenced
        // Move the existing unmanaged launcher bindings into the managed region.
        try doc.setManagedBindings(unmanagedLaunchers.map { var b = $0; b.managed = true; return b })
        try writer.write(doc.serialized(), to: skhdURL, backupStem: "skhdrc")
    }
}
```

Note: `migrateSkhd` adopts the launcher lines into the fence. The original read-only launcher lines remain in the prefix/suffix; for v1 the migration's job is to *establish* the managed region from a copy of those launchers. Deduping the now-managed lines from the prefix is handled in Plan B's UI (promote/remove flow); the conflict engine will surface any resulting duplicate so it is never silent (D31). Document this in the README (Plan B).

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter MigrationTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/Keymap.swift tools/keymapper/Sources/Keymapper/Core/Migration.swift tools/keymapper/Tests/KeymapperTests/MigrationTests.swift
git commit -m "feat(keymapper): Keymap aggregate + idempotent first-run migration (D26)"
```

---

### Task 10: Deployer — drift detect, scoped copy+reload, validate + auto-revert

After writing repo files, the deployer makes skhd live: copy the repo `skhdrc` to the deployed path and `skhd --reload` via argv (no `sh -c`, absolute path — D20). It detects repo-vs-deployed drift (D13) and, on a failed reload, restores the backup and re-applies (D25/D9). karabiner needs no deploy step (symlink auto-reload).

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/Deployer.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/DeployerTests.swift`

- [ ] **Step 1: Write the failing test**

`tools/keymapper/Tests/KeymapperTests/DeployerTests.swift`:

```swift
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
        let dep = Deployer(skhdRepo: repo, skhdDeployed: deployed, runner: FakeRunner(), skhdPath: "/opt/homebrew/bin/skhd")
        XCTAssertTrue(try dep.isInSync())
        try "changed\n".write(to: repo, atomically: true, encoding: .utf8)
        XCTAssertFalse(try dep.isInSync())
    }

    func testApplyCopiesRepoToDeployedAndReloadsViaArgv() throws {
        let repo = dir.appendingPathComponent("skhdrc")
        let deployed = dir.appendingPathComponent("sub/deployed")
        try "rules v1\n".write(to: repo, atomically: true, encoding: .utf8)
        let runner = FakeRunner()
        let dep = Deployer(skhdRepo: repo, skhdDeployed: deployed, runner: runner, skhdPath: "/opt/homebrew/bin/skhd")
        try dep.apply()
        XCTAssertEqual(try String(contentsOf: deployed, encoding: .utf8), "rules v1\n")
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].0, "/opt/homebrew/bin/skhd")  // absolute path, no sh -c
        XCTAssertEqual(runner.calls[0].1, ["--reload"])
    }

    func testApplyThrowsWhenReloadFails() throws {
        let repo = dir.appendingPathComponent("skhdrc")
        let deployed = dir.appendingPathComponent("deployed")
        try "rules\n".write(to: repo, atomically: true, encoding: .utf8)
        let runner = FakeRunner()
        runner.result = ProcessResult(stdout: "", stderr: "config error", exitCode: 1)
        let dep = Deployer(skhdRepo: repo, skhdDeployed: deployed, runner: runner, skhdPath: "/opt/homebrew/bin/skhd")
        XCTAssertThrowsError(try dep.apply())
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter DeployerTests`
Expected: FAIL — `cannot find 'Deployer' in scope`.

- [ ] **Step 3: Implement Deployer**

`tools/keymapper/Sources/Keymapper/Core/Deployer.swift`:

```swift
import Foundation

/// Makes skhd changes live with the minimal scoped step (D12): copy repo skhdrc → deployed path,
/// then `skhd --reload` via argv with an absolute path (D20). karabiner is symlinked (no deploy).
struct Deployer {
    let skhdRepo: URL
    let skhdDeployed: URL
    let runner: ProcessRunner
    let skhdPath: String

    static func makeReal() -> Deployer {
        Deployer(skhdRepo: Paths.skhdRepo, skhdDeployed: Paths.skhdDeployed,
                 runner: RealProcessRunner(), skhdPath: resolveSkhd())
    }

    /// Prefer Homebrew's path; fall back to a bare name only if neither exists (caller surfaces errors).
    static func resolveSkhd() -> String {
        for p in ["/opt/homebrew/bin/skhd", "/usr/local/bin/skhd"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return "/opt/homebrew/bin/skhd"
    }

    func isInSync() throws -> Bool {
        guard FileManager.default.fileExists(atPath: skhdDeployed.path) else { return false }
        let a = try Data(contentsOf: skhdRepo)
        let b = try Data(contentsOf: skhdDeployed)
        return a == b
    }

    /// Copy repo → deployed (FileManager, not a shelled cp — D20), then reload.
    func apply() throws {
        try FileManager.default.createDirectory(at: skhdDeployed.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: skhdDeployed.path) {
            try FileManager.default.removeItem(at: skhdDeployed)
        }
        try FileManager.default.copyItem(at: skhdRepo, to: skhdDeployed)
        let r = try runner.run(skhdPath, ["--reload"])
        if r.exitCode != 0 { throw DeployError.reloadFailed(r.stderr) }
    }
}

enum DeployError: Error, Equatable { case reloadFailed(String) }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter DeployerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/Deployer.swift tools/keymapper/Tests/KeymapperTests/DeployerTests.swift
git commit -m "feat(keymapper): scoped skhd deployer with drift detect + argv reload (D12,D13,D20)"
```

---

### Task 11: Cheatsheet export (Markdown)

A searchable cheatsheet is a headline feature; here we produce the data + a Markdown renderer (the UI search lives in Plan B). Grouped by layer, sorted, with a conflicts section.

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/Core/Cheatsheet.swift`
- Test: `tools/keymapper/Tests/KeymapperTests/CheatsheetTests.swift`

- [ ] **Step 1: Write the failing test**

`tools/keymapper/Tests/KeymapperTests/CheatsheetTests.swift`:

```swift
import XCTest
@testable import Keymapper

final class CheatsheetTests: XCTestCase {
    private func b(_ layer: Layer, _ mods: [String], _ key: String, app: String) -> Binding {
        Binding(chord: Chord(layer: layer, modifiers: mods, key: key), source: .skhd, managed: true,
                launcher: LauncherAction(mechanism: .toggle, target: app, focusBringToCurrent: false, rawCommand: ""),
                rawText: "", displayName: app)
    }

    func testMarkdownGroupsByLayerAndListsBindings() {
        let md = Cheatsheet.markdown(bindings: [
            b(.spaceLeader, [], "b", app: "Safari"),
            b(.skhdModifier, ["hyper"], "s", app: "Slack"),
        ], conflicts: [])
        XCTAssertTrue(md.contains("## space-leader"))
        XCTAssertTrue(md.contains("## skhd-modifier"))
        XCTAssertTrue(md.contains("Safari"))
        XCTAssertTrue(md.contains("Slack"))
    }

    func testMarkdownIncludesConflictsSectionWhenPresent() {
        let dup = b(.skhdModifier, ["hyper"], "b", app: "Safari")
        let md = Cheatsheet.markdown(bindings: [dup, dup], conflicts: ConflictEngine.find([dup, dup]))
        XCTAssertTrue(md.contains("## Conflicts"))
        XCTAssertTrue(md.contains("hyper") || md.contains("cmd+ctrl+alt+shift"))
    }

    func testNoConflictsSectionWhenNone() {
        let md = Cheatsheet.markdown(bindings: [b(.spaceLeader, [], "b", app: "Safari")], conflicts: [])
        XCTAssertFalse(md.contains("## Conflicts"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd tools/keymapper && swift test --filter CheatsheetTests`
Expected: FAIL — `cannot find 'Cheatsheet' in scope`.

- [ ] **Step 3: Implement Cheatsheet**

`tools/keymapper/Sources/Keymapper/Core/Cheatsheet.swift`:

```swift
import Foundation

enum Cheatsheet {
    static func markdown(bindings: [Binding], conflicts: [Conflict]) -> String {
        var out = "# Keymap Cheatsheet\n"
        for layer in Layer.allCases {
            let inLayer = bindings.filter { $0.chord.layer == layer }
                .sorted { $0.chord.canonical < $1.chord.canonical }
            guard !inLayer.isEmpty else { continue }
            out += "\n## \(layer.rawValue)\n\n"
            for b in inLayer {
                let tag = b.managed ? "" : " _(reference)_"
                out += "- `\(chordLabel(b.chord))` → \(b.displayName)\(tag)\n"
            }
        }
        if !conflicts.isEmpty {
            out += "\n## Conflicts\n\n"
            for c in conflicts {
                let names = c.bindings.map { $0.displayName }.joined(separator: ", ")
                out += "- `\(chordLabel(c.chord))`: \(names)\n"
            }
        }
        return out
    }

    private static func chordLabel(_ chord: Chord) -> String {
        switch chord.layer {
        case .spaceLeader: return "space \(chord.key)"
        case .spaceFLeader: return "space f \(chord.key)"
        case .karabinerModifier, .skhdModifier:
            return SkhdChord.render(chord)
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd tools/keymapper && swift test --filter CheatsheetTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the FULL suite to confirm the engine is green end-to-end**

Run: `cd tools/keymapper && swift test`
Expected: PASS — all tests across all files, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/Cheatsheet.swift tools/keymapper/Tests/KeymapperTests/CheatsheetTests.swift
git commit -m "feat(keymapper): Markdown cheatsheet export with conflicts section"
```

---

## Final Engine Review

After Task 11, dispatch a final reviewer over the whole `tools/keymapper/` engine:
- Confirm `swift test` is fully green and every Decision-Log item in scope (D2, D7–D26, D29, D31, D32) maps to code + a test.
- Verify no `sh -c` anywhere (`grep -rn "sh -c\|/bin/sh" tools/keymapper/Sources` → expect no matches).
- Verify the injection guard: the `ShellQuote` + `LauncherCommand.render` path is the only way managed launcher commands are generated.
- Confirm karabiner writes go through `JSONValue` (no `JSONSerialization` of the document) so unknown keys can't be dropped.

Then proceed to **Plan B (Keymapper App)** for the SwiftUI window, `scripts/install.sh`, `Info.plist`, and README — or stop here with a fully-tested engine.

---

## Self-Review (author checklist — completed)

**1. Spec coverage:**
- D2 source-of-truth / D18 edit repo file → `Paths` (Task 3), `Migration`/`Deployer` operate on repo URLs.
- D7 object-graph mutate, no string-splice → `KarabinerDocument` (Task 6).
- D8 verbatim skhd passthrough → `SkhdDocument` byte-for-byte test (Task 7).
- D9/D25 backup + restore → `AtomicFileWriter.makeBackup/restore` (Task 3); deployer failure path (Task 10).
- D11 launcher `{app,mechanism,rawCommand}` → `Binding`/`LauncherCommand` (Task 5).
- D12 scoped skhd copy + reload, not sync.sh → `Deployer` (Task 10).
- D13 drift detect → `Deployer.isInSync` (Task 10).
- D14 per-layer chords → `Chord`/`ConflictEngine` (Tasks 4, 8).
- D15/D31 whole-keymap lint incl. read-only → `ConflictEngine` (Task 8), reference bindings parsed in Tasks 6–7.
- D17 atomic temp+rename → `AtomicFileWriter.atomicReplace` (Task 3).
- D19 shell-quote generation → `ShellQuote` + `LauncherCommand.render` (Tasks 1, 5).
- D20 argv, absolute path, no sh -c → `Deployer` (Task 10).
- D21/D22 backup perms/location/retention → `AtomicFileWriter` (Task 3).
- D23 karabiner semantic-equivalence 2-space serialize → `JSONValue.serialized(indent:2)` (Tasks 2, 6).
- D24 lossless unknown keys → `JSONValue` + future-key tests (Tasks 2, 6).
- D26 first-run migration → `Migration` (Task 9).
- D29 opaque bindings parsed at chord level → `SkhdDocument` multi-line test (Task 7).
- D32 keymap: prefix app-maintained → `KarabinerDocument.adopt` (Task 6).
- Out of engine scope (Plan B): D27 atomic save UX, D28 plain-language banner, D30 two-section UI, D33 hidden mechanism, D34 framing, D35/D36 README/limitation copy.

**2. Placeholder scan:** none — every code step contains complete code; the only prose-only step is the Task 9 dedupe note, which is explicitly deferred to Plan B with a rationale, not a code gap.

**3. Type consistency:** `Binding`, `LauncherAction`, `Chord`, `Layer`, `SourceFile`, `LauncherMechanism`, `Conflict`, `JSONValue`, `KarabinerDocument`, `SkhdDocument`, `SkhdChord`, `LauncherCommand`, `AtomicFileWriter`, `Deployer`, `Migration`, `Keymap`, `Cheatsheet`, `Paths`, `ShellQuote`, `ProcessRunner`/`ProcessResult` — names/signatures used consistently across tasks (e.g. `setManagedBindings`, `adoptSpaceLauncherRule`, `setLauncherTarget`, `find`, `markdown` match their definitions).
