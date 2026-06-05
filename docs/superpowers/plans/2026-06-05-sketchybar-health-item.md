# Sketchybar Health Item for LaunchDashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an ambient sketchybar health glyph that turns green/red based on whether the LaunchDashboard *priority* services are running right now, fed by a new bearer-guarded `GET /summary` endpoint on the existing dashboard app.

**Architecture:** Two halves. (1) Swift: a new `/summary` route in `HTTP/Routes.swift`, computed purely from `ServiceMonitor.snapshot()` filtered to the configured priority labels — so `Routes.register` gains a `priorityLabels: [String]` parameter. (2) Bash: a sketchybar `items/launchdash.sh` (registration + styling) and `plugins/launchdash.sh` (curls `/summary` each tick, recolors the glyph, rebuilds a click-to-open popup listing each priority service). Sketchybar config in this repo is **copied, not symlinked** — deploy via `setupfiles/sync.sh`.

**Tech Stack:** Swift 5.9 (SwiftPM executable, XCTest), AppKit; bash + `jq` + `curl`; sketchybar (Tokyonight palette, JetBrainsMono Nerd Font).

**Spec:** `docs/superpowers/specs/2026-06-05-sketchybar-health-item-design.md`

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Routes.swift` | HTTP route table | Add `priorityLabels` param + `/summary` route |
| `tools/launch-dashboard/Sources/LaunchDashboard/AppDelegate.swift` | App wiring | Pass `Array(priorityLabels)` to `Routes.register` |
| `tools/launch-dashboard/Tests/LaunchDashboardTests/RoutesTests.swift` | Route unit tests | Update 5 call sites + add 3 `/summary` tests |
| `tools/launch-dashboard/README.md` | Docs | Document `/summary` + sketchybar integration |
| `.config/sketchybar/items/launchdash.sh` | Item registration/styling | New file |
| `.config/sketchybar/plugins/launchdash.sh` | Per-tick data + popup | New file |
| `.config/sketchybar/sketchybarrc` | Bar bootstrap | `source` the new item |

**Working directory for all Swift commands:** `tools/launch-dashboard/`.

---

## Task 1: Plumb `priorityLabels` through `Routes.register`

Pure mechanical refactor: add the parameter the `/summary` route will need, and fix every call site so the project still compiles and all tests stay green. No behavior change yet.

**Files:**
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Routes.swift:4-7` (signature)
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/AppDelegate.swift:67-68` (call site)
- Modify: `tools/launch-dashboard/Tests/LaunchDashboardTests/RoutesTests.swift` (5 call sites)

- [ ] **Step 1: Add the parameter to the signature**

In `Routes.swift`, change the `register` signature (lines 4-7) from:

```swift
    static func register(router: Router,
                         monitor: ServiceMonitor,
                         client: LaunchctlClient,
                         token: String) {
```

to:

```swift
    static func register(router: Router,
                         monitor: ServiceMonitor,
                         client: LaunchctlClient,
                         token: String,
                         priorityLabels: [String]) {
```

- [ ] **Step 2: Update the AppDelegate call site**

In `AppDelegate.swift` (lines 67-68), change:

```swift
        Routes.register(router: router, monitor: monitor,
                        client: client, token: config.bearerToken)
```

to:

```swift
        Routes.register(router: router, monitor: monitor,
                        client: client, token: config.bearerToken,
                        priorityLabels: Array(priorityLabels))
```

(`priorityLabels` is the `Set<String>` stored on `AppDelegate`; `Array(...)` converts it.)

- [ ] **Step 3: Update all 5 test call sites**

In `RoutesTests.swift` there are five `Routes.register(...)` calls (lines ~21, ~42, ~69, ~97, ~112). Append `, priorityLabels: []` to each. After editing, every call must read:

```swift
        Routes.register(router: router, monitor: monitor,
                        client: monitor.client, token: "tok", priorityLabels: [])
```

(One call passes `client: monitor.client`; keep whatever each site already used — only add the trailing `priorityLabels: []`.)

- [ ] **Step 4: Build and test to confirm still-green**

Run: `swift build && swift test`
Expected: builds clean; all existing tests PASS (no new tests yet).

- [ ] **Step 5: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Routes.swift \
        tools/launch-dashboard/Sources/LaunchDashboard/AppDelegate.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/RoutesTests.swift
git commit -m "refactor: thread priorityLabels into Routes.register"
```

---

## Task 2: `GET /summary` route (TDD)

A bearer-guarded route returning the priority services' up/down summary, computed from the snapshot filtered to `priorityLabels` (empty ⇒ all services count as priority).

**Files:**
- Test: `tools/launch-dashboard/Tests/LaunchDashboardTests/RoutesTests.swift` (add 3 tests)
- Modify: `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Routes.swift` (add route in `register`)

**Reference — existing helpers you will rely on (do not redefine):**
- `ServiceState` is `enum ServiceState: String, Codable { case running, loadedNotRunning, notLoaded, unknown }`. Use `state.rawValue` for the JSON `state` string; `state == .running` for `up`.
- `HTTPResponse.json(_ status: Int, _ object: Any)` serializes any JSON object.
- `FakeRunner` keys responses by `([path] + args).joined(separator: " ")`; `launchctl list` ⇒ key `"/bin/launchctl list"`, stdout format `PID\tStatus\tLabel\n<pid>\t<status>\t<label>\n...` (a service absent from this output is `.notLoaded`).
- The `guarded { ... }` wrapper inside `register` already enforces the bearer check and returns `401` when missing/invalid.

- [ ] **Step 1: Write the three failing tests**

Add these to `RoutesTests.swift` (inside the `RoutesTests` class):

```swift
    func testSummaryReportsPriorityDownCount() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-summary-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for label in ["com.example.alpha", "com.example.beta"] {
            let body: [String: Any] = ["Label": label, "ProgramArguments": ["/bin/true"]]
            let data = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
            try data.write(to: dir.appendingPathComponent("\(label).plist"))
        }

        let fake = FakeRunner()
        // alpha is running (PID present); beta is absent from `launchctl list` → notLoaded.
        fake.responses["/bin/launchctl list"] = ProcessResult(
            stdout: "PID\tStatus\tLabel\n42\t0\tcom.example.alpha\n", stderr: "", exitCode: 0)
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor, client: monitor.client,
                        token: "tok", priorityLabels: ["com.example.alpha", "com.example.beta"])

        let req = HTTPRequest(method: "GET", path: "/summary",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        let obj = try JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        XCTAssertEqual(obj?["priorityDown"] as? Int, 1)
        XCTAssertEqual(obj?["priorityTotal"] as? Int, 2)
        let rows = obj?["priority"] as? [[String: Any]] ?? []
        let upByLabel = Dictionary(uniqueKeysWithValues:
            rows.compactMap { r -> (String, Bool)? in
                guard let l = r["label"] as? String, let u = r["up"] as? Bool else { return nil }
                return (l, u)
            })
        XCTAssertEqual(upByLabel["com.example.alpha"], true)
        XCTAssertEqual(upByLabel["com.example.beta"], false)
    }

    func testSummaryAllUpWhenAllRunning() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-summary-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for label in ["com.example.alpha", "com.example.beta"] {
            let body: [String: Any] = ["Label": label, "ProgramArguments": ["/bin/true"]]
            let data = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
            try data.write(to: dir.appendingPathComponent("\(label).plist"))
        }

        let fake = FakeRunner()
        fake.responses["/bin/launchctl list"] = ProcessResult(
            stdout: "PID\tStatus\tLabel\n42\t0\tcom.example.alpha\n99\t0\tcom.example.beta\n",
            stderr: "", exitCode: 0)
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: fake, uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor, client: monitor.client,
                        token: "tok", priorityLabels: ["com.example.alpha", "com.example.beta"])

        let req = HTTPRequest(method: "GET", path: "/summary",
                              headers: ["Authorization": "Bearer tok"], body: Data())
        let resp = router.handle(req)
        XCTAssertEqual(resp.status, 200)
        let obj = try JSONSerialization.jsonObject(with: resp.body) as? [String: Any]
        XCTAssertEqual(obj?["priorityDown"] as? Int, 0)
        XCTAssertEqual(obj?["priorityTotal"] as? Int, 2)
    }

    func testSummaryUnauthorizedReturns401() {
        let dir = FileManager.default.temporaryDirectory
        let monitor = ServiceMonitor(
            scanner: PlistScanner(directory: dir),
            client: LaunchctlClient(runner: FakeRunner(), uid: 501)
        )
        let router = Router()
        Routes.register(router: router, monitor: monitor, client: monitor.client,
                        token: "tok", priorityLabels: [])
        let req = HTTPRequest(method: "GET", path: "/summary", headers: [:], body: Data())
        XCTAssertEqual(router.handle(req).status, 401)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RoutesTests`
Expected: the three new tests FAIL — the router has no `/summary` route, so `testSummary...Count`/`AllUp` get a 404 (not 200) and the assertions fail. (`testSummaryUnauthorizedReturns401` may already pass, since an unmatched route returns 404 ≠ 200 too — that's fine; it must end green after Step 3.)

- [ ] **Step 3: Implement the `/summary` route**

In `Routes.swift`, inside `register(...)`, add this route (place it right after the `GET "/services"` route, before the `POST .../start` route):

```swift
        router.add("GET", "/summary", guarded { _, _ in
            do {
                let snap = try monitor.snapshot()
                let prioritySet = Set(priorityLabels)
                let priority = prioritySet.isEmpty
                    ? snap : snap.filter { prioritySet.contains($0.label) }
                let rows: [[String: Any]] = priority.map { s in
                    ["label": s.label, "state": s.state.rawValue, "up": s.state == .running]
                }
                let payload: [String: Any] = [
                    "priorityDown": priority.filter { $0.state != .running }.count,
                    "priorityTotal": priority.count,
                    "priority": rows,
                ]
                return .json(200, payload)
            } catch { NSLog("LaunchDashboard route error: \(error)"); return .text(500, "internal error") }
        })
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RoutesTests`
Expected: all RoutesTests PASS, including the three new ones.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: entire suite PASS (no regressions).

- [ ] **Step 6: Commit**

```bash
git add tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Routes.swift \
        tools/launch-dashboard/Tests/LaunchDashboardTests/RoutesTests.swift
git commit -m "feat: add GET /summary endpoint for priority service health"
```

---

## Task 3: Sketchybar item registration

Create the `launchdash` item and wire it into the bar. Styling mirrors the existing `cpu` item; color is left neutral here and recolored by the plugin each tick.

**Files:**
- Create: `.config/sketchybar/items/launchdash.sh`
- Modify: `.config/sketchybar/sketchybarrc` (add a `source` line in the Right group)

- [ ] **Step 1: Create `items/launchdash.sh`**

```bash
#!/usr/bin/env bash

# Neutral until the first plugin tick recolors it. Click toggles the popup.
sketchybar --add item launchdash right \
	--set launchdash \
	update_freq=5 \
	icon="" \
	icon.color="$COMMENT" \
	icon.padding_left=10 \
	label.color="$LABEL_COLOR" \
	label.padding_right=10 \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COMMENT" \
	background.color="$BAR_COLOR" \
	background.drawing=on \
	popup.height=24 \
	popup.drawing=off \
	script="$PLUGIN_DIR/launchdash.sh" \
	click_script="sketchybar --set launchdash popup.drawing=toggle"
```

(`$COMMENT`, `$LABEL_COLOR`, `$CORNER_RADIUS`, `$BORDER_WIDTH`, `$BAR_COLOR`, `$PLUGIN_DIR` all come from `variables.sh`, which `sketchybarrc` sources before any item.)

- [ ] **Step 2: Source the item in `sketchybarrc`**

In `.config/sketchybar/sketchybarrc`, in the `# Right` group, add a line after `source "$ITEM_DIR/memory.sh"`:

```bash
source "$ITEM_DIR/cpu.sh"
source "$ITEM_DIR/memory.sh"
source "$ITEM_DIR/launchdash.sh"
```

- [ ] **Step 3: Make the new item executable**

Run: `chmod +x /Users/predbjorn/.dotfiles/.config/sketchybar/items/launchdash.sh`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add .config/sketchybar/items/launchdash.sh .config/sketchybar/sketchybarrc
git commit -m "feat(sketchybar): add launchdash item registration"
```

(Deployment + visual verification happens in Task 6 — config here is copied, not symlinked.)

---

## Task 4: Sketchybar plugin (data + popup)

The per-tick script: fetch `/summary`, recolor the glyph, rebuild the popup rows. Reads the bearer token from the dashboard's 0600 `config.json`.

**Files:**
- Create: `.config/sketchybar/plugins/launchdash.sh`

**Glyphs (FontAwesome codepoints, all present in JetBrainsMono Nerd Font):**
- Healthy ``  — check-circle (U+F058)
- Down ``  — exclamation-triangle (U+F071)
- Unknown ``  — question-circle (U+F059)
- Row dot ``  — circle (U+F111)

(If you prefer a "pulse" glyph for healthy you may swap it, but verify it renders in Task 6.)

**Popup-rebuild mechanic:** sketchybar `--query <item>` returns JSON whose `.popup.items[]` lists current popup child names. Remove those, then add one `launchdash.row.N` child per priority service via `--add item <name> popup.launchdash`.

- [ ] **Step 1: Create `plugins/launchdash.sh`**

```bash
#!/usr/bin/env bash

source "$HOME/.config/sketchybar/variables.sh"

ICON_OK=""        # check-circle
ICON_DOWN=""      # exclamation-triangle
ICON_UNKNOWN=""   # question-circle
DOT=""            # circle

CONFIG="$HOME/Library/Application Support/LaunchDashboard/config.json"

# Tear down popup rows from the previous tick so we can rebuild cleanly.
clear_popup_rows() {
	local rows
	rows=$(sketchybar --query launchdash 2>/dev/null | jq -r '.popup.items[]?' 2>/dev/null)
	for row in $rows; do
		sketchybar --remove "$row" 2>/dev/null
	done
}

set_offline() {
	clear_popup_rows
	sketchybar --set launchdash \
		icon="$ICON_UNKNOWN" icon.color="$COMMENT" \
		label="" background.border_color="$COMMENT"
	sketchybar --add item launchdash.row.0 popup.launchdash \
		--set launchdash.row.0 icon="$DOT" icon.color="$COMMENT" \
		label="dashboard offline" 2>/dev/null
}

# 1. Resolve the token; bail to offline if config is missing/unreadable.
TOKEN=$(jq -r '.bearerToken // empty' "$CONFIG" 2>/dev/null)
if [ -z "$TOKEN" ]; then
	set_offline
	exit 0
fi

# 2. Fetch the summary; bail to offline on curl failure / empty / non-JSON.
JSON=$(curl -sS --max-time 2 -H "Authorization: Bearer $TOKEN" \
	http://127.0.0.1:8765/summary 2>/dev/null)
if [ -z "$JSON" ] || ! echo "$JSON" | jq empty >/dev/null 2>&1; then
	set_offline
	exit 0
fi

# 3. Recolor the glyph from priorityDown.
DOWN=$(echo "$JSON" | jq -r '.priorityDown // 0')
if [ "$DOWN" -gt 0 ] 2>/dev/null; then
	sketchybar --set launchdash \
		icon="$ICON_DOWN" icon.color="$RED" \
		label="$DOWN" background.border_color="$RED"
else
	sketchybar --set launchdash \
		icon="$ICON_OK" icon.color="$GREEN" \
		label="" background.border_color="$GREEN"
fi

# 4. Rebuild popup rows, one per priority service.
clear_popup_rows
i=0
while IFS=$'\t' read -r label state up; do
	[ -z "$label" ] && continue
	if [ "$up" = "true" ]; then dot_color="$GREEN"; else dot_color="$RED"; fi
	sketchybar --add item "launchdash.row.$i" popup.launchdash \
		--set "launchdash.row.$i" \
		icon="$DOT" icon.color="$dot_color" \
		label="$label  $state" 2>/dev/null
	i=$((i + 1))
done < <(echo "$JSON" | jq -r '.priority[] | [.label, .state, (.up|tostring)] | @tsv')
```

- [ ] **Step 2: Make the plugin executable**

Run: `chmod +x /Users/predbjorn/.dotfiles/.config/sketchybar/plugins/launchdash.sh`
Expected: no output.

- [ ] **Step 3: Static lint with bash**

Run: `bash -n /Users/predbjorn/.dotfiles/.config/sketchybar/plugins/launchdash.sh`
Expected: no output (no syntax errors). Full runtime verification is in Task 6 (requires a live sketchybar + dashboard).

- [ ] **Step 4: Commit**

```bash
git add .config/sketchybar/plugins/launchdash.sh
git commit -m "feat(sketchybar): add launchdash plugin (summary fetch + popup)"
```

---

## Task 5: Documentation

Document the new endpoint and the sketchybar integration in the tool README.

**Files:**
- Modify: `tools/launch-dashboard/README.md` (HTTP API table ~line 47-52, and a new section)

- [ ] **Step 1: Add `/summary` to the HTTP API table**

In `README.md`, add this row to the API table immediately after the `GET /services` row (line ~47):

```markdown
| GET    | `/summary`                    | Priority-service health: `{priorityDown, priorityTotal, priority[]}` |
```

- [ ] **Step 2: Add a sketchybar integration section**

After the `curl ... /services ...` example block (the fenced block ending at line ~57), add:

```markdown
### Sketchybar health glyph

`/summary` powers an ambient health glyph in the user's sketchybar. The bar item
(`.config/sketchybar/items/launchdash.sh`) and its plugin
(`.config/sketchybar/plugins/launchdash.sh`) curl this endpoint every 5s:

- **Green** check glyph — all priority services running.
- **Red** triangle glyph + count — one or more priority services not running right now.
- **Gray** "?" glyph — the dashboard isn't reachable.

Click the glyph for a popup listing each priority service with a green/red dot.

`priorityDown` counts priority services whose state is not `running` (PID-based —
catches crashes, manual stops, and never-started alike). "Priority" = `config.priorityLabels`
(empty ⇒ all services).

```bash
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/summary | jq
```

Sketchybar config is **copied, not symlinked** — after editing `.config/sketchybar/`,
deploy with `setupfiles/sync.sh` then `sketchybar --reload`.
```

- [ ] **Step 3: Commit**

```bash
git add tools/launch-dashboard/README.md
git commit -m "docs: document /summary endpoint and sketchybar health glyph"
```

---

## Task 6: Deploy and verify end-to-end

Operational task — no unit tests, verified by running things directly (same manual-verify approach as `install.sh`). Rebuild the dashboard so it serves `/summary`, deploy the sketchybar config, then walk the state matrix.

**Files:** none modified (runs existing scripts).

- [ ] **Step 1: Rebuild + reload the dashboard agent**

Run: `cd /Users/predbjorn/.dotfiles/tools/launch-dashboard && ./scripts/install.sh`
Expected: "Building release binary...", bundle assembled, agent bootstrapped, ends with "Installed to .../LaunchDashboard.app".

- [ ] **Step 2: Verify `/summary` serves live data**

Run:
```bash
TOKEN=$(jq -r .bearerToken "$HOME/Library/Application Support/LaunchDashboard/config.json")
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/summary | jq
```
Expected: JSON with `priorityDown`, `priorityTotal`, and a `priority` array of `{label,state,up}` for `com.nors.ai-daemon` and `com.nors.cloudflared`.

- [ ] **Step 3: Verify auth is enforced**

Run: `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8765/summary`
Expected: `401`.

- [ ] **Step 4: Deploy the sketchybar config and reload**

Run: `cd /Users/predbjorn/.dotfiles && ./setupfiles/sync.sh && sketchybar --reload`
Expected: sync copies `.config/sketchybar/` to `~/.config/sketchybar/`; bar reloads with the new `launchdash` item visible on the right.

- [ ] **Step 5: Run the plugin directly (no errors)**

Run: `NAME=launchdash bash ~/.config/sketchybar/plugins/launchdash.sh; echo "exit=$?"`
Expected: `exit=0`, no error output. The bar glyph updates.

- [ ] **Step 6: Walk the state matrix (visual)**

1. **Healthy:** both priority services running ⇒ glyph is **green** check, no count.
2. **Down:** `launchctl bootout gui/$(id -u)/com.nors.cloudflared` (or stop one from the menu-bar app), wait ~5s ⇒ glyph turns **red** with count `1`.
3. **Popup:** click the glyph ⇒ popup lists both priority services, the stopped one with a **red** dot, the running one **green**. Click again ⇒ popup closes.
4. **Recover:** restart the stopped service ⇒ glyph returns to **green** within ~5s.
5. **Offline:** `launchctl bootout gui/$(id -u)/com.prebenhafnor.launch-dashboard`, wait ~5s ⇒ glyph turns **gray "?"**, popup shows "dashboard offline". Then re-run `./tools/launch-dashboard/scripts/install.sh` to bring it back.

- [ ] **Step 7: Confirm no uncommitted changes remain**

Run: `git status --short`
Expected: clean (all code/config/doc changes already committed in Tasks 1-5; this task only ran scripts).

---

## Self-Review Notes

- **Spec coverage:** `/summary` route + `priorityLabels` plumbing (Tasks 1-2), 3 named TDD tests (Task 2), item (Task 3), plugin with offline/green/red + popup rebuild (Task 4), README (Task 5), deploy + state-matrix verify (Task 6). All spec sections mapped.
- **Type consistency:** `ServiceState.rawValue` strings (`running`/`loadedNotRunning`/`notLoaded`/`unknown`) match the spec's `state` values; `up == (state == .running)`; `priorityDown == count(state != .running)`. `Routes.register` param name `priorityLabels: [String]` used identically in signature, AppDelegate call, and all test call sites.
- **Empty-priority semantics:** `prioritySet.isEmpty ? snap : filter` — empty `priorityLabels` ⇒ all services are priority, matching `AppDelegate.pollOnQueue` and the spec.
