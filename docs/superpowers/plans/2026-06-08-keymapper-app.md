# Keymapper App (Plan B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the SwiftUI windowed app for Keymapper on top of the already-complete headless engine (Plan A), giving the user a structured editor for managed launcher bindings + a read-only auditor for the full keymap.

**Architecture:** `KeymapperApp` is a new SwiftPM executable target in the existing `tools/keymapper/` package. It imports the `Keymapper` library (the Plan A engine) and adds only UI. `KeymapperViewModel` lives in the library (so it is testable). The UI (`Sources/KeymapperApp/`) is a thin AppKit+SwiftUI layer: `NSApplication` → `AppDelegate` opens one `NSWindow` hosting `ContentView`. Save = one atomic write + deploy (D27). Migration = auto-adopt on first run (D26). Conflict detection, drift detection, and cheatsheet export all come free from the engine.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit + SwiftUI, Combine (for ObservableObject), Foundation. macOS 13+. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-06-05-keymapper-design.md` (Decision Log D1–D36). This plan implements the UI half (D3, D13, D15, D26–D30, D33–D36) and the two engine additions required by the UI (Binding.sourceLine for open-at-line, and the Deploying protocol for testable injection). Engine (D2, D7–D25, D31–D32) is already done in Plan A; those files must not be broken.

---

## File Structure

```
tools/keymapper/
  Package.swift                  (modify: add KeymapperApp executable target)
  Info.plist                     (create: .app bundle metadata)
  README.md                      (create: honest framing, D34)
  scripts/
    install.sh                   (create: swift build → .app → ~/Applications/)

  Sources/
    Keymapper/Core/
      Binding.swift              (modify: add sourceLine: Int?, explicit init)
      SkhdDocument.swift         (modify: populate sourceLine in parseBindings)
      Deployer.swift             (modify: add Deploying protocol, extension Deployer: Deploying)
      KeymapperViewModel.swift   (create: ObservableObject load/save/migrate/drift — TESTABLE)

    KeymapperApp/
      main.swift                 (create: NSApplication entry point)
      AppDelegate.swift          (create: window creation, vm.loadReportingError())
      UI/
        ContentView.swift        (create: toolbar + banners + scroll view with two sections)
        ManagedSection.swift     (create: editable managed binding list + BindingEditSheet)
        ReferenceSection.swift   (create: read-only reference list + EditorLauncher)
        CheatsheetPanel.swift    (create: markdown export sheet)

  Tests/
    KeymapperTests/
      KeymapperViewModelTests.swift  (create: load/migrate/save/drift tests with MockDeployer)
```

---

### Task 1: Engine additions — Binding.sourceLine, Deploying protocol, SkhdDocument line tracking

**Context:** Three small changes to the existing engine to enable Plan B:
1. `Binding` gains `sourceLine: Int?` (1-based skhd line number for "open-at-line", D29). Karabiner bindings always have nil.
2. `SkhdDocument.parseBindings` gains a `startLineOffset` parameter and populates `sourceLine` on each parsed binding.
3. `Deployer` gains a `Deploying` protocol so `KeymapperViewModel` can inject a mock deployer in tests.

**Files:**
- Modify: `tools/keymapper/Sources/Keymapper/Core/Binding.swift`
- Modify: `tools/keymapper/Sources/Keymapper/Core/SkhdDocument.swift`
- Modify: `tools/keymapper/Sources/Keymapper/Core/Deployer.swift`
- Modify: `tools/keymapper/Tests/KeymapperTests/SkhdDocumentTests.swift` (add one test)

- [ ] **Step 1: Add `sourceLine` to Binding with an explicit init that defaults it to nil**

Replace ALL of `tools/keymapper/Sources/Keymapper/Core/Binding.swift` with:

```swift
import Foundation

enum SourceFile: String, Codable { case karabiner, skhd }

enum LauncherMechanism: String, Codable {
    case toggle   // bin/toggle_app.sh <App>
    case focus    // bin/focus_window_wrapper.sh <App> <bringToCurrent>
    case open     // open <path>  (space+f folder shortcuts)
}

/// A recognized launcher action. `rawCommand` is the verbatim source of truth (D11).
struct LauncherAction: Equatable {
    var mechanism: LauncherMechanism
    var target: String
    var focusBringToCurrent: Bool
    var rawCommand: String
}

/// One keymap binding. `launcher == nil` means an opaque action (e.g. yabai pipeline):
/// the chord is still parsed for conflict detection + cheatsheet (D29).
struct Binding: Equatable {
    var chord: Chord
    var source: SourceFile
    var managed: Bool
    var launcher: LauncherAction?
    var rawText: String
    var displayName: String
    var sourceLine: Int?   // 1-based line number in skhdrc (nil for karabiner bindings, D29)

    init(chord: Chord, source: SourceFile, managed: Bool, launcher: LauncherAction?,
         rawText: String, displayName: String, sourceLine: Int? = nil) {
        self.chord = chord
        self.source = source
        self.managed = managed
        self.launcher = launcher
        self.rawText = rawText
        self.displayName = displayName
        self.sourceLine = sourceLine
    }
}
```

**Important:** `sourceLine` defaults to `nil`. All existing call sites (`Binding(chord:source:managed:launcher:rawText:displayName:)`) continue to compile without change because the new parameter has a default.

- [ ] **Step 2: Update SkhdDocument to track line numbers**

Replace ALL of `tools/keymapper/Sources/Keymapper/Core/SkhdDocument.swift` with:

```swift
import Foundation

/// Splits skhdrc into [prefix lines] [managed region] [suffix lines]. The managed region is regenerated
/// on edit; everything else passes through verbatim (D8). All binding lines (managed or not) are parsed
/// at chord level for the auditor (D29). Line numbers (1-based) are stored on each Binding for D29
/// open-at-line support.
struct SkhdDocument {
    static let openFence = "# >>> keymap-managed >>>"
    static let closeFence = "# <<< keymap-managed <<<"

    private var prefix: [String]
    private var managedLines: [String]
    private var suffix: [String]
    private var hasFence: Bool

    init(text: String) throws {
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
        // Compute 0-based line offsets for each section so sourceLine is accurate.
        let prefixOffset = 0                                          // prefix starts at line 1 (offset 0)
        let managedOffset = prefix.count + 1                          // +1 for the open-fence line
        let suffixOffset = prefix.count + 1 + managedLines.count + 1 // +1 for close-fence line

        var out: [Binding] = []
        out += parseBindings(from: prefix, managed: false, startLineOffset: prefixOffset)
        out += parseBindings(from: managedLines, managed: true, startLineOffset: managedOffset)
        out += parseBindings(from: suffix, managed: false, startLineOffset: suffixOffset)
        return out
    }

    /// Replace the managed region with freshly rendered bindings. If no fence exists, one is created.
    mutating func setManagedBindings(_ bindings: [Binding]) throws {
        managedLines = bindings.map { binding -> String in
            let chord = SkhdChord.render(binding.chord)
            let command = binding.launcher.map(LauncherCommand.render) ?? binding.rawText
            return "\(chord) : \(command)"
        }
        hasFence = true
    }

    // MARK: Line parsing

    /// Parse an array of raw lines into Bindings. `startLineOffset` is the 0-based index of
    /// `lines[0]` within the full file (so sourceLine = startLineOffset + localIndex + 1, 1-based).
    private func parseBindings(from lines: [String], managed: Bool, startLineOffset: Int) -> [Binding] {
        // Join skhd line-continuations (trailing backslash); track the first physical line of each logical line.
        var logical: [(text: String, firstLine: Int)] = []
        var buffer = ""
        var bufferLine = 0
        var inBuffer = false

        for (localIndex, raw) in lines.enumerated() {
            let lineNumber = startLineOffset + localIndex + 1  // 1-based
            if !inBuffer && isComment(raw) { continue }
            if !inBuffer { bufferLine = lineNumber; inBuffer = true }
            if raw.hasSuffix("\\") {
                buffer += String(raw.dropLast())
                continue
            }
            buffer += raw
            if !buffer.trimmingCharacters(in: .whitespaces).isEmpty {
                logical.append((buffer, bufferLine))
            }
            buffer = ""
            inBuffer = false
        }
        if !buffer.trimmingCharacters(in: .whitespaces).isEmpty {
            logical.append((buffer, bufferLine))
        }

        return logical.compactMap { (line, lineNum) -> Binding? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let lhs = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let rhs = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard let chord = SkhdChord.parse(lhs) else { return nil }
            let action = LauncherCommand.parse(rhs)
            return Binding(chord: chord, source: .skhd, managed: managed,
                           launcher: action, rawText: rhs,
                           displayName: action?.target ?? summarize(rhs),
                           sourceLine: lineNum)
        }
    }

    private func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }
    private func summarize(_ cmd: String) -> String {
        cmd.split(separator: " ").first.map(String.init) ?? cmd
    }
}

/// Parse/render an skhd chord LHS, e.g. "ctrl + shift + cmd - g" or "hyper - b".
enum SkhdChord {
    static func parse(_ lhs: String) -> Chord? {
        let parts = lhs.components(separatedBy: " - ")
        let key: String
        var mods: [String] = []
        if parts.count >= 2 {
            mods = parts[0].split(separator: "+").map { normalizeMod($0.trimmingCharacters(in: .whitespaces)) }
            key = parts[1].trimmingCharacters(in: .whitespaces)
        } else {
            key = lhs.trimmingCharacters(in: .whitespaces)
        }
        guard !key.isEmpty else { return nil }
        return Chord(layer: .skhdModifier, modifiers: mods.filter { !$0.isEmpty }, key: key)
    }

    static func render(_ chord: Chord) -> String {
        if chord.modifiers.isEmpty { return chord.key }
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

- [ ] **Step 3: Add Deploying protocol to Deployer.swift**

Open `tools/keymapper/Sources/Keymapper/Core/Deployer.swift`. Add these lines at the TOP, before `struct Deployer`:

```swift
/// Protocol so KeymapperViewModel can inject a mock deployer in tests (same pattern as ProcessRunner).
protocol Deploying {
    func isInSync() throws -> Bool
    func apply() throws
}
```

Then at the BOTTOM of the file, after the `DeployError` enum, add:

```swift
extension Deployer: Deploying {}
```

- [ ] **Step 4: Write a failing line-number test in SkhdDocumentTests**

Add this test to `tools/keymapper/Tests/KeymapperTests/SkhdDocumentTests.swift`:

```swift
func testParsedBindingsHaveCorrectLineNumbers() throws {
    // Lines:
    // 1: lalt + lcmd - l: yabai -m display --focus east
    // 2: # >>> keymap-managed >>>
    // 3: hyper - s : ~/.dotfiles/bin/focus_window_wrapper.sh Slack false
    // 4: # <<< keymap-managed <<<
    let text = """
        lalt + lcmd - l: yabai -m display --focus east
        # >>> keymap-managed >>>
        hyper - s : ~/.dotfiles/bin/focus_window_wrapper.sh Slack false
        # <<< keymap-managed <<<
        """
    let doc = try SkhdDocument(text: text)
    let bs = doc.bindings()

    let lalt = bs.first { $0.chord.key == "l" }
    XCTAssertNotNil(lalt)
    XCTAssertEqual(lalt?.sourceLine, 1)

    let slack = bs.first { $0.chord.key == "s" }
    XCTAssertNotNil(slack)
    XCTAssertEqual(slack?.sourceLine, 3)
}
```

- [ ] **Step 5: Run the full test suite to confirm all 62 tests pass**

```bash
cd tools/keymapper && swift test
```

Expected output:
```
Executed 62 tests, with 0 failures (0 unexpected) in ...
```

(62 = 61 original + 1 new line-number test.)

- [ ] **Step 6: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/Core/Binding.swift \
        tools/keymapper/Sources/Keymapper/Core/SkhdDocument.swift \
        tools/keymapper/Sources/Keymapper/Core/Deployer.swift \
        tools/keymapper/Tests/KeymapperTests/SkhdDocumentTests.swift
git commit -m "feat(keymapper): Binding.sourceLine, Deploying protocol, skhd line tracking (D29)"
```

---

### Task 2: KeymapperViewModel + SaveError + tests

**Context:** The ViewModel is the heart of the app: it loads both config files, tracks edits, and atomically saves + deploys. It lives in the `Keymapper` library (not the app target) so it can be fully unit-tested. It uses `Deploying` (injectable) for testability.

**Files:**
- Create: `tools/keymapper/Sources/Keymapper/KeymapperViewModel.swift`
- Create: `tools/keymapper/Tests/KeymapperTests/KeymapperViewModelTests.swift`

- [ ] **Step 1: Write the failing tests first**

Create `tools/keymapper/Tests/KeymapperTests/KeymapperViewModelTests.swift`:

```swift
import XCTest
@testable import Keymapper

// MARK: - Mock

struct MockDeployer: Deploying {
    var syncResult: Bool = true
    var applyError: Error? = nil
    func isInSync() throws -> Bool { syncResult }
    func apply() throws { if let e = applyError { throw e } }
}

// MARK: - Tests

final class KeymapperViewModelTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("kmvm-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Helpers

    private var karURL: URL  { dir.appendingPathComponent("karabiner.json") }
    private var skhdURL: URL { dir.appendingPathComponent("skhdrc") }
    private var backupDir: URL { dir.appendingPathComponent("backups") }

    /// Minimal karabiner.json with one SpaceLauncher binding. `managed` adds the keymap: prefix.
    private func writeKar(managed: Bool = false) throws {
        let prefix = managed ? "keymap: " : ""
        let text = """
        {
          "profiles": [{
            "name": "Default profile",
            "complex_modifications": {
              "rules": [{
                "description": "\(prefix)SpaceLauncher shortcuts",
                "manipulators": [{
                  "type": "basic",
                  "from": {"key_code": "b"},
                  "to": [{"shell_command": "$HOME/.dotfiles/bin/toggle_app.sh Safari"}]
                }]
              }]
            }
          }]
        }
        """
        try text.write(to: karURL, atomically: true, encoding: .utf8)
    }

    /// Minimal skhdrc with one binding. `managed` wraps it in the fence.
    private func writeSkhd(managed: Bool = false) throws {
        let text: String
        if managed {
            text = """
            # >>> keymap-managed >>>
            hyper - s : ~/.dotfiles/bin/focus_window_wrapper.sh Slack false
            # <<< keymap-managed <<<
            """
        } else {
            text = "hyper - s : ~/.dotfiles/bin/focus_window_wrapper.sh Slack false\n"
        }
        try text.write(to: skhdURL, atomically: true, encoding: .utf8)
    }

    private func makeVM(deployer: (any Deploying)? = nil) -> KeymapperViewModel {
        KeymapperViewModel(
            karabinerURL: karURL,
            skhdURL: skhdURL,
            deployer: deployer ?? MockDeployer(),
            writer: AtomicFileWriter(backupDir: backupDir)
        )
    }

    // MARK: Tests

    func testLoadPopulatesEditedManagedAndClearsDirty() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM()
        try vm.load()
        XCTAssertNotNil(vm.keymap)
        XCTAssertEqual(vm.editedManaged.count, 2)   // 1 karabiner + 1 skhd managed binding
        XCTAssertFalse(vm.isDirty)
        XCTAssertFalse(vm.needsMigration)
    }

    func testLoadSetsNeedsMigrationWhenUnmanaged() throws {
        try writeKar(managed: false)
        try writeSkhd(managed: false)
        let vm = makeVM()
        try vm.load()
        XCTAssertTrue(vm.needsMigration)
    }

    func testMigrateConvertsUnmanagedToManaged() throws {
        try writeKar(managed: false)
        try writeSkhd(managed: false)
        let vm = makeVM()
        try vm.load()
        XCTAssertTrue(vm.needsMigration)
        try vm.migrate()
        XCTAssertFalse(vm.needsMigration)
        XCTAssertFalse(vm.editedManaged.isEmpty)
        // Written skhdrc must contain the fence.
        let written = try String(contentsOf: skhdURL, encoding: .utf8)
        XCTAssertTrue(written.contains("# >>> keymap-managed >>>"))
    }

    func testAddBindingSetsDirtyAndAppendsToEditedManaged() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM()
        try vm.load()
        let before = vm.editedManaged.count
        vm.addBinding(Binding(
            chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "m"),
            source: .skhd, managed: true,
            launcher: LauncherAction(mechanism: .toggle, target: "Mail",
                                     focusBringToCurrent: false, rawCommand: ""),
            rawText: "", displayName: "Mail"
        ))
        XCTAssertTrue(vm.isDirty)
        XCTAssertEqual(vm.editedManaged.count, before + 1)
    }

    func testRemoveBindingSetsDirty() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM()
        try vm.load()
        let before = vm.editedManaged.count
        vm.removeBinding(at: IndexSet(integer: 0))
        XCTAssertTrue(vm.isDirty)
        XCTAssertEqual(vm.editedManaged.count, before - 1)
    }

    func testSaveClearsDirtyAndWritesNewBinding() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM(deployer: MockDeployer())
        try vm.load()
        vm.addBinding(Binding(
            chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "p"),
            source: .skhd, managed: true,
            launcher: LauncherAction(mechanism: .toggle, target: "Spotify",
                                     focusBringToCurrent: false, rawCommand: ""),
            rawText: "", displayName: "Spotify"
        ))
        try vm.save()
        XCTAssertFalse(vm.isDirty)
        XCTAssertFalse(vm.skhdInSync)  // MockDeployer.syncResult defaults to true but we
                                        // re-check after save; sync set based on deployer
        let written = try String(contentsOf: skhdURL, encoding: .utf8)
        XCTAssertTrue(written.contains("toggle_app.sh Spotify"))
    }

    func testSaveThrowsConcurrentEditWhenFileChangedExternally() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM()
        try vm.load()
        vm.addBinding(Binding(
            chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: "q"),
            source: .skhd, managed: true,
            launcher: LauncherAction(mechanism: .toggle, target: "Test",
                                     focusBringToCurrent: false, rawCommand: ""),
            rawText: "", displayName: "Test"
        ))
        // External modification — simulates Karabiner GUI or another process writing the file.
        try "# externally modified\n".write(to: skhdURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try vm.save()) { error in
            XCTAssertEqual(error as? SaveError, .concurrentEdit)
        }
    }

    func testMakeItLiveCallsDeployAndSetsSyncTrue() throws {
        try writeKar(managed: true)
        try writeSkhd(managed: true)
        let vm = makeVM(deployer: MockDeployer(syncResult: false))
        try vm.load()
        XCTAssertFalse(vm.skhdInSync)
        try vm.makeItLive()
        XCTAssertTrue(vm.skhdInSync)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd tools/keymapper && swift test --filter KeymapperViewModelTests
```

Expected: FAIL — `cannot find 'KeymapperViewModel' in scope`.

- [ ] **Step 3: Implement KeymapperViewModel**

Create `tools/keymapper/Sources/Keymapper/KeymapperViewModel.swift`:

```swift
import Foundation
import Combine

/// The observable model for the Keymapper UI. Loads both config files, tracks in-flight edits,
/// and saves atomically (D27). Lives in the library target so it is testable without SwiftUI.
final class KeymapperViewModel: ObservableObject {
    @Published private(set) var keymap: Keymap?
    @Published private(set) var editedManaged: [Binding] = []   // working copy for pending edits
    @Published private(set) var isDirty: Bool = false
    @Published private(set) var skhdInSync: Bool = true
    @Published var loadError: String?    // set by loadReportingError(); cleared by view
    @Published var saveError: String?    // set by saveReportingError(); cleared by view
    @Published private(set) var needsMigration: Bool = false

    /// Hashes of each file as read at load time; used to detect concurrent external edits (D10).
    private var karabinerHash: Int = 0
    private var skhdHash: Int = 0

    let karabinerURL: URL
    let skhdURL: URL
    let deployer: any Deploying
    let writer: AtomicFileWriter

    init(
        karabinerURL: URL = Paths.karabinerRepo,
        skhdURL: URL = Paths.skhdRepo,
        deployer: any Deploying = Deployer.makeReal(),
        writer: AtomicFileWriter = AtomicFileWriter(backupDir: Paths.backupDir)
    ) {
        self.karabinerURL = karabinerURL
        self.skhdURL = skhdURL
        self.deployer = deployer
        self.writer = writer
    }

    // MARK: Load

    /// Load (or re-load) both config files. Resets all edit state.
    func load() throws {
        let karText = try String(contentsOf: karabinerURL, encoding: .utf8)
        let skhdText = try String(contentsOf: skhdURL, encoding: .utf8)
        karabinerHash = karText.hashValue
        skhdHash = skhdText.hashValue
        let km = try Keymap(karabinerText: karText, skhdText: skhdText)
        keymap = km
        editedManaged = km.managed
        isDirty = false
        needsMigration = km.needsMigration
        skhdInSync = (try? deployer.isInSync()) ?? true
    }

    /// Convenience wrapper used by AppDelegate so the caller doesn't need a try/catch.
    func loadReportingError() {
        do { try load() } catch { loadError = error.localizedDescription }
    }

    // MARK: Edit

    func updateBinding(_ binding: Binding) {
        guard let idx = editedManaged.firstIndex(where: {
            $0.chord == binding.chord && $0.source == binding.source
        }) else { return }
        editedManaged[idx] = binding
        isDirty = true
    }

    func addBinding(_ binding: Binding) {
        editedManaged.append(binding)
        isDirty = true
    }

    func removeBinding(at offsets: IndexSet) {
        editedManaged.remove(atOffsets: offsets)
        isDirty = true
    }

    // MARK: Save (D27 — one atomic write + deploy)

    /// Atomic save: re-read to detect concurrent edits (D10), write both files (D17, D21),
    /// validate (D25), then deploy skhd (D12). Throws on any failure; backups are preserved.
    func save() throws {
        guard var km = keymap else { return }

        // D10: re-read immediately before writing to detect concurrent external edits.
        let freshKar = try String(contentsOf: karabinerURL, encoding: .utf8)
        let freshSkhd = try String(contentsOf: skhdURL, encoding: .utf8)
        guard freshKar.hashValue == karabinerHash,
              freshSkhd.hashValue == skhdHash else {
            try load()   // reload before throwing so UI shows the current state
            throw SaveError.concurrentEdit
        }

        // Re-parse from the freshly-read text (avoids writing a stale base, D10).
        km = try Keymap(karabinerText: freshKar, skhdText: freshSkhd)

        // Apply karabiner edits: update each managed space-leader launcher's shell_command.
        for b in editedManaged where b.source == .karabiner {
            guard let action = b.launcher else { continue }
            try km.karabiner.setLauncherTarget(layer: b.chord.layer, key: b.chord.key, action: action)
        }

        // Apply skhd edits: regenerate the entire managed region (D8 verbatim passthrough outside).
        let skhdBindings = editedManaged.filter { $0.source == .skhd }
        try km.skhd.setManagedBindings(skhdBindings)

        // Serialize.
        let karText = km.karabiner.serialized()
        let skhdText = km.skhd.serialized()

        // Atomic write with backup (D17, D21). Backup is taken BEFORE each write.
        try writer.write(karText, to: karabinerURL, backupStem: "karabiner")
        try writer.write(skhdText, to: skhdURL, backupStem: "skhdrc")

        // D25: post-write semantic validation — re-parse and verify managed count.
        let writtenKar = try String(contentsOf: karabinerURL, encoding: .utf8)
        let writtenSkhd = try String(contentsOf: skhdURL, encoding: .utf8)
        let validated = try Keymap(karabinerText: writtenKar, skhdText: writtenSkhd)
        guard validated.managed.count == editedManaged.count else {
            // Backups are already on disk; caller surfaces the error so the user can restore manually.
            throw SaveError.validationFailed
        }

        // Deploy skhd (D12): copy repo skhdrc → deployed path, then skhd --reload.
        try deployer.apply()

        // Update in-memory state.
        keymap = validated
        editedManaged = validated.managed
        isDirty = false
        skhdInSync = true
        karabinerHash = writtenKar.hashValue
        skhdHash = writtenSkhd.hashValue
    }

    /// Convenience wrapper for the Save button action in SwiftUI.
    func saveReportingError() {
        do { try save() } catch { saveError = error.localizedDescription }
    }

    // MARK: Migration (D26)

    /// First-run: auto-adopt all existing launcher bindings into the managed model.
    func migrate() throws {
        let m = Migration(karabinerURL: karabinerURL, skhdURL: skhdURL, writer: writer)
        try m.run()
        try load()
    }

    // MARK: Drift (D13, D28)

    /// "Make it live" — re-deploy repo skhdrc when it diverged from the deployed copy.
    func makeItLive() throws {
        try deployer.apply()
        skhdInSync = true
    }
}

// MARK: - Errors

enum SaveError: Error, LocalizedError, Equatable {
    case concurrentEdit
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .concurrentEdit:
            return "The config file was modified externally — reloaded the latest version. Please review and save again."
        case .validationFailed:
            return "Write validation failed. Your backup was preserved in ~/Library/Application Support/Keymapper/backups/."
        }
    }
}
```

- [ ] **Step 4: Fix the `testSaveClearsDirtyAndWritesNewBinding` expectation**

The test asserts `XCTAssertFalse(vm.skhdInSync)` but after a successful save, `skhdInSync` is set to `true` (because `deployer.apply()` succeeded). Fix the assertion in the test file:

```swift
// Replace:
XCTAssertFalse(vm.skhdInSync)  // MockDeployer.syncResult defaults to true but ...
// With:
XCTAssertTrue(vm.skhdInSync)   // deployer.apply() succeeded; skhdInSync reset to true
```

The comment about `MockDeployer.syncResult` was wrong — after `save()`, `skhdInSync = true` is set unconditionally on success. The `syncResult` on `MockDeployer` only affects `isInSync()` (called during `load()`).

- [ ] **Step 5: Run the full test suite**

```bash
cd tools/keymapper && swift test
```

Expected:
```
Executed 69 tests, with 0 failures (0 unexpected) in ...
```

(62 from Task 1 + 7 new ViewModel tests.)

- [ ] **Step 6: Commit**

```bash
git add tools/keymapper/Sources/Keymapper/KeymapperViewModel.swift \
        tools/keymapper/Tests/KeymapperTests/KeymapperViewModelTests.swift
git commit -m "feat(keymapper): KeymapperViewModel with load/save/migrate/drift + tests (D10,D25,D26,D27,D28)"
```

---

### Task 3: Package.swift + App scaffold (Info.plist, main.swift, AppDelegate, bare ContentView)

**Context:** Convert the package to have both a library target (the engine + ViewModel) and a new `KeymapperApp` executable target (the UI shell). Verify it builds before wiring up any real UI.

**Files:**
- Modify: `tools/keymapper/Package.swift`
- Create: `tools/keymapper/Info.plist`
- Create: `tools/keymapper/Sources/KeymapperApp/main.swift`
- Create: `tools/keymapper/Sources/KeymapperApp/AppDelegate.swift`
- Create: `tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift`

- [ ] **Step 1: Add `KeymapperApp` executable target to Package.swift**

Replace ALL of `tools/keymapper/Package.swift` with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Keymapper",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "Keymapper"
        ),
        .executableTarget(
            name: "KeymapperApp",
            dependencies: ["Keymapper"]
        ),
        .testTarget(
            name: "KeymapperTests",
            dependencies: ["Keymapper"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Create Info.plist**

Create `tools/keymapper/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.predbjorn.keymapper</string>
    <key>CFBundleExecutable</key>
    <string>Keymapper</string>
    <key>CFBundleName</key>
    <string>Keymapper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Create main.swift**

Create `tools/keymapper/Sources/KeymapperApp/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Create AppDelegate.swift**

Create `tools/keymapper/Sources/KeymapperApp/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import Keymapper

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    let vm = KeymapperViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = ContentView(vm: vm)
        let hosting = NSHostingController(rootView: content)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keymapper"
        window.contentViewController = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Load on launch — errors are surfaced in the UI.
        vm.loadReportingError()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```

- [ ] **Step 5: Create a bare ContentView**

Create `tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift`:

```swift
import SwiftUI
import Keymapper

struct ContentView: View {
    @ObservedObject var vm: KeymapperViewModel

    var body: some View {
        VStack {
            Text("Keymapper — loading…")
                .font(.headline)
                .padding()
        }
        .frame(width: 820, height: 620)
    }
}
```

- [ ] **Step 6: Build to verify the scaffold compiles**

```bash
cd tools/keymapper && swift build 2>&1 | grep -E "(error:|warning:|Build complete)"
```

Expected:
```
Build complete!
```

(Some deprecation warnings are acceptable; zero errors required.)

- [ ] **Step 7: Run tests to confirm nothing broke**

```bash
cd tools/keymapper && swift test
```

Expected: same 69 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add tools/keymapper/Package.swift \
        tools/keymapper/Info.plist \
        tools/keymapper/Sources/KeymapperApp/main.swift \
        tools/keymapper/Sources/KeymapperApp/AppDelegate.swift \
        tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift
git commit -m "feat(keymapper): app scaffold — KeymapperApp target, AppDelegate, bare ContentView"
```

---

### Task 4: ContentView — full layout (toolbar, error banner, drift banner, migration sheet)

**Context:** Wire up the real ContentView with a toolbar (Save, Cheatsheet), an inline error banner, a "Make it live" drift banner, and a migration sheet that fires on first run. The two sections (Managed, Reference) are placeholders here — they are wired in Tasks 5 and 6.

**Files:**
- Modify: `tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift`

- [ ] **Step 1: Replace ContentView with the full layout**

Replace ALL of `tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift` with:

```swift
import SwiftUI
import Keymapper

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var vm: KeymapperViewModel
    @State private var showCheatsheet = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let err = vm.loadError {
                InlineBanner(text: err, style: .error) { vm.loadError = nil }
            }
            if let err = vm.saveError {
                InlineBanner(text: err, style: .error) { vm.saveError = nil }
            }
            if !vm.skhdInSync {
                DriftBanner { try? vm.makeItLive() }
            }
            Divider()
            scrollBody
        }
        .frame(minWidth: 680, idealWidth: 820, minHeight: 480, idealHeight: 620)
        // First-run migration sheet (D26). Sheet cannot be dismissed; user must migrate.
        .sheet(isPresented: Binding(get: { vm.needsMigration }, set: { _ in })) {
            MigrationSheet {
                do { try vm.migrate() } catch { vm.saveError = error.localizedDescription }
            }
        }
        // Cheatsheet export sheet (D15).
        .sheet(isPresented: $showCheatsheet) {
            CheatsheetPanel(vm: vm)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Keymapper").font(.headline)
            Spacer()
            // Conflict badge (D15, D31): shown only when conflicts exist.
            let conflicts = vm.keymap?.conflicts ?? []
            if !conflicts.isEmpty {
                Label("\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline.weight(.semibold))
            }
            Button("Cheatsheet", systemImage: "doc.text") {
                showCheatsheet = true
            }
            .buttonStyle(.bordered)
            Button("Save") {
                vm.saveReportingError()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.isDirty)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Scroll body

    private var scrollBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                // Managed section (Task 5) — placeholder until Task 5 lands.
                Section(header: SectionHeader(title: "Managed", count: vm.editedManaged.count)) {
                    Text("(Managed bindings — Task 5)")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                // Reference section (Task 6) — placeholder until Task 6 lands.
                let ref = vm.keymap?.reference ?? []
                Section(header: SectionHeader(title: "Reference (read-only)", count: ref.count)) {
                    Text("(Reference bindings — Task 6)")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text("\(title)  (\(count))").font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thickMaterial)
    }
}

// MARK: - Inline Banner

enum BannerStyle { case error, info }

struct InlineBanner: View {
    let text: String
    let style: BannerStyle
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: style == .error ? "xmark.octagon.fill" : "info.circle.fill")
                .foregroundStyle(style == .error ? Color.red : Color.blue)
            Text(text).font(.callout)
            Spacer()
            Button("Dismiss", action: onDismiss).buttonStyle(.plain).font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(style == .error ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
    }
}

// MARK: - Drift Banner (D28)

struct DriftBanner: View {
    let onMakeItLive: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
            Text("skhdrc repo file is ahead of the deployed copy.")
                .font(.callout)
            Spacer()
            Button("Make it live", action: onMakeItLive)
                .buttonStyle(.bordered)
                .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Migration Sheet (D26)

struct MigrationSheet: View {
    let onMigrate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "wand.and.stars").font(.largeTitle).foregroundStyle(.accent)
                Text("First-run setup").font(.title2.bold())
            }
            Text("""
                Keymapper found existing launcher bindings in your config files.
                Tap "Adopt bindings" to import them into Keymapper's managed regions.
                This is a one-time step. A backup of both files is taken first.
                """)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Spacer()
                Button("Adopt bindings", action: onMigrate)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
```

- [ ] **Step 2: Build and run to verify the window opens**

```bash
cd tools/keymapper && swift build && .build/debug/KeymapperApp
```

Expected: A window opens titled "Keymapper" with the toolbar (Save disabled, no conflicts), the two placeholder sections. If the real `~/.dotfiles/.config/karabiner.json` and `skhdrc` exist, the toolbar populates with the actual conflict count and binding counts.

Quit the app with Cmd+Q.

- [ ] **Step 3: Commit**

```bash
git add tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift
git commit -m "feat(keymapper): ContentView — toolbar, drift banner, migration sheet, section placeholders"
```

---

### Task 5: ManagedSection + BindingEditSheet

**Context:** Replace the placeholder managed section with a real editable list. Each row shows the chord and the target app/folder. Clicking a row opens an edit sheet to change the target. Users can also add new bindings (to the skhd hyper layer) and delete existing ones.

**Files:**
- Create: `tools/keymapper/Sources/KeymapperApp/UI/ManagedSection.swift`
- Modify: `tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift` (replace placeholder)

- [ ] **Step 1: Create ManagedSection.swift**

Create `tools/keymapper/Sources/KeymapperApp/UI/ManagedSection.swift`:

```swift
import SwiftUI
import Keymapper

// MARK: - ManagedSection

/// The editable list of managed launcher bindings (D30). Karabiner and skhd bindings are shown
/// in a unified list — the dual-file mechanism is hidden from the user (D33).
struct ManagedSection: View {
    @ObservedObject var vm: KeymapperViewModel
    @State private var selectedBinding: Binding? = nil    // binding being edited
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if vm.editedManaged.isEmpty {
                emptyState
            } else {
                ForEach(vm.editedManaged.indices, id: \.self) { idx in
                    let b = vm.editedManaged[idx]
                    ManagedRow(binding: b, conflicted: isConflicted(b)) {
                        selectedBinding = b   // open edit sheet
                    }
                    if idx < vm.editedManaged.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            addButton
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        // Edit sheet.
        .sheet(item: $selectedBinding) { binding in
            BindingEditSheet(binding: binding, isNew: false) { updated in
                vm.updateBinding(updated)
                selectedBinding = nil
            } onCancel: {
                selectedBinding = nil
            } onDelete: {
                if let idx = vm.editedManaged.firstIndex(where: {
                    $0.chord == binding.chord && $0.source == binding.source
                }) {
                    vm.removeBinding(at: IndexSet(integer: idx))
                }
                selectedBinding = nil
            }
        }
        // Add sheet.
        .sheet(isPresented: $showAddSheet) {
            BindingEditSheet(
                binding: Binding(
                    chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: ""),
                    source: .skhd, managed: true, launcher: nil, rawText: "", displayName: ""
                ),
                isNew: true
            ) { newBinding in
                vm.addBinding(newBinding)
                showAddSheet = false
            } onCancel: {
                showAddSheet = false
            } onDelete: {
                showAddSheet = false  // no-op for new binding
            }
        }
    }

    private var emptyState: some View {
        Text("No managed bindings yet. Tap + to add one.")
            .foregroundStyle(.secondary)
            .padding()
    }

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Add binding", systemImage: "plus")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func isConflicted(_ binding: Swift.Binding<String>? = nil, _ b: Keymapper.Binding) -> Bool {
        let conflicts = vm.keymap?.conflicts ?? []
        return conflicts.contains { $0.chord == b.chord }
    }
}

// MARK: - ManagedRow

struct ManagedRow: View {
    let binding: Keymapper.Binding
    let conflicted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Conflict indicator (D31).
                if conflicted {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                // Chord badge.
                Text(chordLabel)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                // Arrow.
                Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)
                // Target + mechanism.
                VStack(alignment: .leading, spacing: 2) {
                    Text(binding.displayName).font(.body)
                    Text(mechanismLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                // Source indicator (subtly shown — mechanism is hidden, D33).
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var chordLabel: String {
        switch binding.chord.layer {
        case .spaceLeader: return "space \(binding.chord.key)"
        case .spaceFLeader: return "space f \(binding.chord.key)"
        case .karabinerModifier, .skhdModifier: return SkhdChord.render(binding.chord)
        }
    }

    private var mechanismLabel: String {
        switch binding.launcher?.mechanism {
        case .toggle: return "toggle"
        case .focus: return "focus"
        case .open: return "open folder"
        case nil: return "custom"
        }
    }
}

// MARK: - BindingEditSheet

/// Edit sheet for a single managed binding. Shows chord (read-only) and editable target + mechanism.
/// For new bindings, the chord is also editable.
struct BindingEditSheet: View {
    @State var binding: Keymapper.Binding
    let isNew: Bool
    let onSave: (Keymapper.Binding) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    // Editable fields.
    @State private var targetText: String
    @State private var mechanism: LauncherMechanism
    @State private var keyText: String
    @State private var bringToCurrent: Bool

    init(binding: Keymapper.Binding, isNew: Bool,
         onSave: @escaping (Keymapper.Binding) -> Void,
         onCancel: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.binding = binding
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _targetText = State(initialValue: binding.launcher?.target ?? "")
        _mechanism = State(initialValue: binding.launcher?.mechanism ?? .toggle)
        _keyText = State(initialValue: binding.chord.key)
        _bringToCurrent = State(initialValue: binding.launcher?.focusBringToCurrent ?? false)
    }

    private var isValid: Bool {
        !targetText.trimmingCharacters(in: .whitespaces).isEmpty &&
        (isNew ? !keyText.trimmingCharacters(in: .whitespaces).isEmpty : true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isNew ? "Add Binding" : "Edit Binding")
                .font(.title2.bold())

            if isNew {
                LabeledContent("Layer") {
                    Text("hyper (skhd modifier layer)").foregroundStyle(.secondary)
                }
                LabeledContent("Key") {
                    TextField("e.g. m", text: $keyText)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                LabeledContent("Chord") {
                    Text(chordLabel).font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Mechanism") {
                Picker("", selection: $mechanism) {
                    Text("Toggle app").tag(LauncherMechanism.toggle)
                    Text("Focus app").tag(LauncherMechanism.focus)
                    Text("Open folder").tag(LauncherMechanism.open)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            LabeledContent(mechanism == .open ? "Path" : "App name") {
                TextField(mechanism == .open ? "~/Downloads" : "Safari", text: $targetText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }

            if mechanism == .focus {
                LabeledContent("Bring to current space") {
                    Toggle("", isOn: $bringToCurrent).labelsHidden()
                }
            }

            Divider()

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(buildBinding()) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var chordLabel: String {
        switch binding.chord.layer {
        case .spaceLeader: return "space \(binding.chord.key)"
        case .spaceFLeader: return "space f \(binding.chord.key)"
        case .karabinerModifier, .skhdModifier: return SkhdChord.render(binding.chord)
        }
    }

    private func buildBinding() -> Keymapper.Binding {
        let target = targetText.trimmingCharacters(in: .whitespaces)
        let action = LauncherAction(mechanism: mechanism, target: target,
                                    focusBringToCurrent: bringToCurrent, rawCommand: "")
        let chord = isNew
            ? Chord(layer: .skhdModifier, modifiers: ["hyper"],
                    key: keyText.trimmingCharacters(in: .whitespaces).lowercased())
            : binding.chord
        return Keymapper.Binding(
            chord: chord, source: isNew ? .skhd : binding.source,
            managed: true, launcher: action,
            rawText: LauncherCommand.render(action),
            displayName: target
        )
    }
}

// MARK: - Identifiable for sheet(item:)

extension Keymapper.Binding: Identifiable {
    public var id: String { chord.canonical + source.rawValue }
}
```

**Note on the `isConflicted` helper:** The method signature `isConflicted(_ binding: Swift.Binding<String>? = nil, _ b: Keymapper.Binding)` is wrong because the first parameter collides with SwiftUI's `Binding`. Replace the implementation body of `ManagedSection` with the corrected version below. The internal `isConflicted` method should be:

```swift
private func isConflicted(_ b: Keymapper.Binding) -> Bool {
    let conflicts = vm.keymap?.conflicts ?? []
    return conflicts.contains { $0.chord == b.chord }
}
```

And the `ForEach` loop calls it as `ManagedRow(binding: b, conflicted: isConflicted(b)) { ... }`.

- [ ] **Step 2: Wire ManagedSection into ContentView**

In `tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift`, replace the placeholder section:

Find:
```swift
Section(header: SectionHeader(title: "Managed", count: vm.editedManaged.count)) {
    Text("(Managed bindings — Task 5)")
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
}
```

Replace with:
```swift
Section(header: SectionHeader(title: "Managed", count: vm.editedManaged.count)) {
    ManagedSection(vm: vm)
}
```

Also add `import` at the top if not already present: the file already has `import Keymapper`.

- [ ] **Step 3: Build and run**

```bash
cd tools/keymapper && swift build && .build/debug/KeymapperApp
```

Expected: Window shows managed bindings from `~/.dotfiles/.config/karabiner.json` and `skhdrc`. Clicking a row opens an edit sheet. The "+" button opens an add sheet. Save is enabled when a binding is added or edited.

Quit with Cmd+Q.

- [ ] **Step 4: Commit**

```bash
git add tools/keymapper/Sources/KeymapperApp/UI/ManagedSection.swift \
        tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift
git commit -m "feat(keymapper): ManagedSection + BindingEditSheet — editable managed list (D30,D33)"
```

---

### Task 6: ReferenceSection + EditorLauncher

**Context:** The read-only audit section shows all non-managed bindings (karabiner unmanaged + skhd unmanaged, including multi-line yabai pipelines). Each row shows the chord, action summary, and — for skhd bindings — an "Open in $EDITOR" button that jumps to the correct line (D29). Conflicts are flagged (D31, D36).

**Files:**
- Create: `tools/keymapper/Sources/KeymapperApp/UI/ReferenceSection.swift`
- Modify: `tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift` (replace placeholder)

- [ ] **Step 1: Create ReferenceSection.swift**

Create `tools/keymapper/Sources/KeymapperApp/UI/ReferenceSection.swift`:

```swift
import AppKit
import SwiftUI
import Keymapper

// MARK: - ReferenceSection

/// Read-only audit view for all non-managed bindings (D30, D35, D36).
/// Shows the full keymap including opaque yabai pipelines so the user can audit
/// conflicts and navigate to source lines (D29). Structured editing is not available
/// here — use "Open in $EDITOR" to edit manually.
struct ReferenceSection: View {
    @ObservedObject var vm: KeymapperViewModel

    var referenceBindings: [Keymapper.Binding] { vm.keymap?.reference ?? [] }
    var conflicts: [Conflict] { vm.keymap?.conflicts ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // D36: set audit-only expectation up front.
            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
                Text("Reference bindings are read-only. Use "Open in $EDITOR" to edit them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

            if referenceBindings.isEmpty {
                Text("No unmanaged bindings found.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(referenceBindings.indices, id: \.self) { idx in
                    let b = referenceBindings[idx]
                    ReferenceRow(
                        binding: b,
                        conflicted: isConflicted(b),
                        skhdURL: vm.skhdURL
                    )
                    if idx < referenceBindings.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private func isConflicted(_ b: Keymapper.Binding) -> Bool {
        conflicts.contains { $0.chord == b.chord }
    }
}

// MARK: - ReferenceRow

struct ReferenceRow: View {
    let binding: Keymapper.Binding
    let conflicted: Bool
    let skhdURL: URL

    var body: some View {
        HStack(spacing: 12) {
            // Conflict indicator (D31).
            if conflicted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            // Chord badge.
            Text(chordLabel)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)
            // Action.
            VStack(alignment: .leading, spacing: 2) {
                Text(binding.displayName).font(.body).foregroundStyle(.primary)
                Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Open-in-editor button for skhd bindings (D29).
            if binding.source == .skhd {
                Button {
                    EditorLauncher.open(url: skhdURL, line: binding.sourceLine)
                } label: {
                    Label("Open in $EDITOR", systemImage: "pencil.and.outline")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var chordLabel: String {
        switch binding.chord.layer {
        case .spaceLeader: return "space \(binding.chord.key)"
        case .spaceFLeader: return "space f \(binding.chord.key)"
        case .karabinerModifier, .skhdModifier: return SkhdChord.render(binding.chord)
        }
    }

    private var sourceLabel: String {
        switch binding.source {
        case .karabiner: return "karabiner · read-only"
        case .skhd: return binding.launcher == nil ? "skhd · multi-line (audit only)" : "skhd · read-only"
        }
    }
}

// MARK: - EditorLauncher (D29)

/// Opens a file in the user's preferred editor, jumping to a specific line when possible.
/// Prefers `$VISUAL` (GUI editors) over `$EDITOR` (often terminal-based).
/// Supports line-jumping for VSCode (`code --goto file:line`).
/// Terminal editors (vim, nvim, etc.) fall back to NSWorkspace to avoid a detached terminal.
enum EditorLauncher {
    static func open(url: URL, line: Int?) {
        let env = ProcessInfo.processInfo.environment
        // Try $VISUAL first (GUI editor preferred), then $EDITOR.
        for editorPath in [env["VISUAL"], env["EDITOR"]].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if tryLaunch(editorPath, url: url, line: line) { return }
        }
        // Fall back to the OS default editor for the file type.
        NSWorkspace.shared.open(url)
    }

    /// Returns `true` if the editor was successfully launched.
    @discardableResult
    private static func tryLaunch(_ editor: String, url: URL, line: Int?) -> Bool {
        let name = URL(fileURLWithPath: editor).lastPathComponent
        let args: [String]

        switch name {
        case "code":
            // VSCode: --goto file:line (D29 line-accurate open).
            args = line.map { ["--goto", "\(url.path):\($0)"] } ?? [url.path]
        case "vim", "nvim", "vi", "nano", "emacs", "pico":
            // Terminal editors need a terminal window; skip (NSWorkspace fallback handles it).
            return false
        default:
            // Unknown editor — try opening with the file path only.
            args = [url.path]
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: editor)
        p.arguments = args
        return (try? p.run()) != nil
    }
}
```

- [ ] **Step 2: Wire ReferenceSection into ContentView**

In `tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift`, replace the placeholder reference section:

Find:
```swift
let ref = vm.keymap?.reference ?? []
Section(header: SectionHeader(title: "Reference (read-only)", count: ref.count)) {
    Text("(Reference bindings — Task 6)")
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
}
```

Replace with:
```swift
let ref = vm.keymap?.reference ?? []
Section(header: SectionHeader(title: "Reference (read-only)", count: ref.count)) {
    ReferenceSection(vm: vm)
}
```

- [ ] **Step 3: Build and run**

```bash
cd tools/keymapper && swift build && .build/debug/KeymapperApp
```

Expected: Window shows both Managed and Reference sections populated from the real config files. Reference rows for skhd bindings show "Open in $EDITOR" buttons. Conflicted chords show a red triangle. Multi-line yabai bindings appear as opaque reference entries.

Quit with Cmd+Q.

- [ ] **Step 4: Commit**

```bash
git add tools/keymapper/Sources/KeymapperApp/UI/ReferenceSection.swift \
        tools/keymapper/Sources/KeymapperApp/UI/ContentView.swift
git commit -m "feat(keymapper): ReferenceSection + EditorLauncher — audit view + open-at-line (D29,D30,D35,D36)"
```

---

### Task 7: CheatsheetPanel

**Context:** A sheet that renders the full keymap as Markdown using the engine's `Cheatsheet.markdown()` and lets the user copy it to the clipboard or save it as a file (D15).

**Files:**
- Create: `tools/keymapper/Sources/KeymapperApp/UI/CheatsheetPanel.swift`

- [ ] **Step 1: Create CheatsheetPanel.swift**

Create `tools/keymapper/Sources/KeymapperApp/UI/CheatsheetPanel.swift`:

```swift
import AppKit
import SwiftUI
import Keymapper

struct CheatsheetPanel: View {
    @ObservedObject var vm: KeymapperViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var savePanel = false

    private var markdown: String {
        guard let km = vm.keymap else { return "No keymap loaded." }
        return Cheatsheet.markdown(bindings: km.bindings, conflicts: km.conflicts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar.
            HStack {
                Text("Keymap Cheatsheet").font(.headline)
                Spacer()
                Button(copied ? "Copied!" : "Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.bordered)
                Button("Save…", systemImage: "square.and.arrow.down") {
                    saveMarkdown()
                }
                .buttonStyle(.bordered)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Scrollable markdown preview (plain text, monospaced — sufficient for a cheatsheet).
            ScrollView {
                Text(markdown)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 560, height: 480)
    }

    private func saveMarkdown() {
        let panel = NSSavePanel()
        panel.title = "Save Cheatsheet"
        panel.nameFieldStringValue = "keymap-cheatsheet.md"
        panel.allowedContentTypes = [.text]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
```

- [ ] **Step 2: Build and run; open the Cheatsheet sheet**

```bash
cd tools/keymapper && swift build && .build/debug/KeymapperApp
```

Click "Cheatsheet" in the toolbar. Expected: A sheet opens showing the full keymap in Markdown, grouped by layer. "Copy" copies to clipboard. "Save…" opens a save panel. Conflicts appear at the bottom if any exist.

Quit with Cmd+Q.

- [ ] **Step 3: Commit**

```bash
git add tools/keymapper/Sources/KeymapperApp/UI/CheatsheetPanel.swift
git commit -m "feat(keymapper): CheatsheetPanel — markdown export, copy to clipboard, save to file (D15)"
```

---

### Task 8: install.sh + README.md

**Context:** The install script builds a proper `.app` bundle and copies it to `~/Applications/`. The README documents what the app is honestly — a launcher & single-line editor + full-keymap auditor (D34) — and lists the v1 limitations (D35).

**Files:**
- Create: `tools/keymapper/scripts/install.sh`
- Create: `tools/keymapper/README.md`

- [ ] **Step 1: Create the install script**

Create `tools/keymapper/scripts/install.sh`:

```bash
#!/usr/bin/env bash
# install.sh — build Keymapper.app and install it to ~/Applications/.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
PACKAGE="$DOTFILES/tools/keymapper"
APP_NAME="Keymapper"
DEST="$HOME/Applications/${APP_NAME}.app"

echo "→ Building $APP_NAME (release)…"
cd "$PACKAGE"
swift build --configuration release

BIN=".build/release/KeymapperApp"

if [ ! -f "$BIN" ]; then
  echo "✗ Build failed: $BIN not found." >&2
  exit 1
fi

echo "→ Assembling ${APP_NAME}.app…"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS"
mkdir -p "$DEST/Contents/Resources"

cp "$BIN"               "$DEST/Contents/MacOS/${APP_NAME}"
cp Info.plist           "$DEST/Contents/"
chmod +x               "$DEST/Contents/MacOS/${APP_NAME}"

echo "✓ Installed → $DEST"
echo ""
echo "Run with:  open ~/Applications/${APP_NAME}.app"
echo "Or add an alias:  alias keymapper='open ~/Applications/${APP_NAME}.app'"
```

Make it executable:

```bash
chmod +x tools/keymapper/scripts/install.sh
```

- [ ] **Step 2: Run the install script and verify**

```bash
cd ~/.dotfiles && tools/keymapper/scripts/install.sh
```

Expected output:
```
→ Building Keymapper (release)…
→ Assembling Keymapper.app…
✓ Installed → /Users/<you>/Applications/Keymapper.app
```

Verify the app opens:

```bash
open ~/Applications/Keymapper.app
```

Expected: The window opens. Quit with Cmd+Q.

- [ ] **Step 3: Create README.md**

Create `tools/keymapper/README.md`:

```markdown
# Keymapper

A **launcher & single-line keymap editor + full-keymap auditor** for macOS.

Keymapper gives you a structured editor for the app/folder launchers and single-line hotkeys spread
across `.config/karabiner.json` and `.config/skhdrc`, and a read-only auditor (conflict detection +
cheatsheet) over the *entire* keymap. Your dotfiles remain the single source of truth.

## What it does

- **Managed section** — edit launcher bindings (toggle/focus/open) that live in the SpaceLauncher
  karabiner rule and the `# >>> keymap-managed >>>` skhd fence. Changes are saved atomically to the
  repo files and deployed live (karabiner reloads via symlink; skhd is copied + reloaded).
- **Reference section** — read-only view of every other binding in both files, including multi-line
  yabai pipelines. Shows conflict indicators. "Open in $EDITOR" jumps to the source line.
- **Cheatsheet** — searchable full-keymap Markdown export.
- **Conflict detection** — covers the entire keymap including unmanaged bindings (no false comfort).
- **Drift detection** — shows a "Make it live" banner if the repo skhdrc is ahead of the deployed copy.

## v1 limitations

- **Multi-line yabai pipelines are audit-only.** The reference section shows them and flags conflicts,
  but you cannot structurally edit them here. Use "Open in $EDITOR" and edit the skhd fence or the
  raw lines manually. Structured editing of multi-line pipelines is a planned v2 goal.
- Adding new bindings is limited to the skhd `hyper` modifier layer. SpaceLauncher bindings
  (karabiner) must be edited manually for now.

## Install

```bash
tools/keymapper/scripts/install.sh
# then:
open ~/Applications/Keymapper.app
```

Or add an alias to `zsh/aliases.zsh`:

```zsh
alias keymapper='open ~/Applications/Keymapper.app'
```

## First run

On first launch, Keymapper detects existing launcher bindings and offers to import them into the
managed regions (backed-up migration). After that, the Managed section is populated and editable.

## Backups

Every save creates timestamped backups at:
`~/Library/Application Support/Keymapper/backups/`

The last 20 backups per file are kept. Backups are not committed to git.
```

- [ ] **Step 4: Run the full test suite one last time**

```bash
cd tools/keymapper && swift test
```

Expected: 69 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add tools/keymapper/scripts/install.sh \
        tools/keymapper/README.md
git commit -m "feat(keymapper): install.sh + README (D34, D35 honest framing)"
```

---

## Self-Review

### Spec coverage check

| Spec requirement | Covered by |
|---|---|
| D2 — managed regions only, dotfiles stay source of truth | Task 5 (ManagedSection only edits managed), ViewModel saves to repo files |
| D3 — windowed, no daemon | Task 3 (AppDelegate, regular NSWindow) |
| D7–D25, D31–D32 — engine decisions | Plan A (already done) |
| D26 — first-run auto-adopt | Task 4 (MigrationSheet), Task 2 (vm.migrate()) |
| D27 — save = one atomic write + deploy | Task 2 (vm.save()) |
| D28 — plain-language "Make it live" | Task 4 (DriftBanner) |
| D29 — opaque bindings + open-at-line | Task 1 (sourceLine), Task 6 (ReferenceSection + EditorLauncher) |
| D30 — Managed + Reference sections | Tasks 5, 6, 4 (ContentView layout) |
| D33 — dual mechanism hidden | Task 5 (ManagedSection shows unified list) |
| D34 — honest framing | Task 8 (README) |
| D35 — multi-line audit-only | Task 6 (ReferenceSection read-only for opaque), Task 8 (README limitation) |
| D36 — reference section copy | Task 6 (audit-only caption at top of ReferenceSection) |

### Placeholder scan

✅ No TBD or TODO in any task. All steps have complete code.

### Type consistency

- `KeymapperViewModel` in Tasks 2, 3, 4, 5, 6, 7: consistent property names (`editedManaged`, `isDirty`, `skhdInSync`, `loadError`, `saveError`, `needsMigration`).
- `Keymapper.Binding` vs SwiftUI's `Binding<_>`: Task 5 qualifies all usages.
- `Conflict` type: comes from engine, used in Tasks 4, 5, 6 as `vm.keymap?.conflicts`.
- `SkhdChord.render(_:)` used in Tasks 5 and 6 for chord labels: consistent.
- `Cheatsheet.markdown(bindings:conflicts:)` used in Task 7: matches engine API exactly.
- `Migration(karabinerURL:skhdURL:writer:).run()` called in Task 2: matches actual `Migration.swift`.
