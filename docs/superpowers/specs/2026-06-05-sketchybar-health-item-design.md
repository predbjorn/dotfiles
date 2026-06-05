# Sketchybar Health Item for LaunchDashboard — Design

**Status:** Approved (brainstorming) — ready for implementation planning.
**Date:** 2026-06-05
**Depends on:** the existing `launch-dashboard` tool (committed to `master`), specifically its
loopback HTTP API and the `priorityLabels` config field.

## Goal

Add an ambient health indicator to the user's existing **sketchybar** status bar that shows,
at a glance, whether the **priority** LaunchAgents (`config.priorityLabels` — currently
`com.nors.ai-daemon` + `com.nors.cloudflared`) are up. It must be quiet when everything is fine
and obvious when something is down, and clicking it reveals a per-service list — without needing
to open the menu-bar app.

## Decisions (from brainstorming)

1. **Display:** a single **compact health glyph**. Green and quiet when all priority services are
   up; red **with a count** when any are down.
2. **"Down" semantics:** *down right now* = a priority service is **not running** (no PID), for any
   reason (crash, manual stop, never started). This is `state != running`, which is PID-based and
   reliable. (Deliberately **not** the transition-based "crashed" set — the user wants "is it up
   right now?", which also catches manual stops and already-down-at-startup.)
3. **Click:** toggles a native **sketchybar popup** listing each priority service with a green/red
   dot and its state.
4. **Data source:** a new compact **`GET /summary`** endpoint on the dashboard (single source of
   truth). The plugin stays trivial.
5. **API offline:** when the dashboard isn't reachable, the glyph shows a neutral **gray "?"** so
   "can't tell" is visibly distinct from "all good".

## Component 1 — `GET /summary` endpoint (Swift)

A new bearer-guarded route in `HTTP/Routes.swift`, computed from `ServiceMonitor.snapshot()`
filtered to the configured priority labels.

**Request:** `GET /summary`, header `Authorization: Bearer <token>` (same guard as every route;
missing/invalid → `401`).

**Response (200, `application/json`):**
```json
{
  "priorityDown": 1,
  "priorityTotal": 2,
  "priority": [
    {"label": "com.nors.ai-daemon",   "state": "running",          "up": true},
    {"label": "com.nors.cloudflared", "state": "loadedNotRunning",  "up": false}
  ]
}
```

**Semantics:**
- `up` = `status.state == .running` (PID present).
- `priorityDown` = count of priority services with `up == false`.
- `priorityTotal` = number of priority services present in the snapshot.
- The "priority" set = `priorityLabels` if non-empty; otherwise **all** services in the snapshot
  (consistent with the app: empty `priorityLabels` means "everything is priority").
- `state` is the raw `ServiceState` value (`running` / `loadedNotRunning` / `notLoaded` / `unknown`).
- Errors → `500` with a generic `"internal error"` body and the detail logged via `NSLog`
  (matches the existing route error convention).

**Plumbing change:** `Routes.register(router:monitor:client:token:)` gains a
`priorityLabels: [String]` parameter. `AppDelegate` passes `Array(self.priorityLabels)` (it already
holds the resolved set). Existing `Routes.register` call sites in tests pass `priorityLabels: []`.

**No new dependency on `CrashTracker`:** `/summary` is computed purely from the snapshot + the
priority list, so it needs nothing from `AppDelegate`'s in-memory crash state.

### Tests (TDD, `RoutesTests.swift`)
- `testSummaryReportsPriorityDownCount` — two priority plists, `launchctl list` reports one running
  (PID) and one absent; assert `priorityDown == 1`, `priorityTotal == 2`, and the per-label `up`
  flags.
- `testSummaryAllUpWhenAllRunning` — both priority services have PIDs; assert `priorityDown == 0`.
- `testSummaryUnauthorizedReturns401` — no token → `401`.

## Component 2 — Sketchybar item + plugin

Matches the repo's existing convention: `items/<name>.sh` registers + styles the item;
`plugins/<name>.sh` updates it on each tick. Item name: **`launchdash`**.

### `.config/sketchybar/items/launchdash.sh`
- `sketchybar --add item launchdash right` then `--set` with: `update_freq=5`, background/border
  styled like the existing `cpu`/`memory` items (`background.height`, `background.corner_radius`,
  `background.border_width=$BORDER_WIDTH`, `background.color=$BAR_COLOR`), `script=$PLUGIN_DIR/launchdash.sh`,
  and `click_script="sketchybar --set launchdash popup.drawing=toggle"`.
- Popup uses the global popup defaults already set in `sketchybarrc`.

### `.config/sketchybar/plugins/launchdash.sh`
Runs every `update_freq` seconds (and whenever sketchybar refreshes the item). Steps:
1. Resolve the API token: `jq -r .bearerToken "$HOME/Library/Application Support/LaunchDashboard/config.json"`.
2. `curl -sS --max-time 2 -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/summary`.
3. **On curl failure / empty / non-JSON** (dashboard down): set the glyph to a gray "?" icon
   (`icon.color=$COMMENT`, the muted Tokyonight gray), clear the label, and set a single popup row
   "dashboard offline". Return.
4. **On success:** read `priorityDown`:
   - `0` → green health glyph (`icon.color=$GREEN`), empty label (quiet).
   - `>0` → red warning glyph (`icon.color=$RED`), `label="$priorityDown"`.
5. **Rebuild popup rows:** one child item per `priority[]` entry, labeled `<label>  <state>`, dotted
   green if `up` else red. The plugin refreshes these each tick so a click shows current data.
   (Exact add/remove mechanics — e.g. removing prior `launchdash.popup.*` children then re-adding —
   are an implementation detail for the plan; the priority list is small, so rebuild-per-tick is fine.)

**Glyphs:** Nerd Font (JetBrainsMono Nerd Font, already the bar font). Pick a pulse/health glyph for
healthy, a warning/triangle glyph for down, and a question glyph for unknown. Exact codepoints chosen
during implementation.

### `.config/sketchybar/sketchybarrc`
Add `source "$ITEM_DIR/launchdash.sh"` in the right-side group (near `cpu`/`memory`).

## Files

| File | Change |
|------|--------|
| `tools/launch-dashboard/Sources/LaunchDashboard/HTTP/Routes.swift` | add `/summary` route + `priorityLabels` param |
| `tools/launch-dashboard/Sources/LaunchDashboard/AppDelegate.swift` | pass `priorityLabels` to `Routes.register` |
| `tools/launch-dashboard/Tests/LaunchDashboardTests/RoutesTests.swift` | update call sites + 3 `/summary` tests |
| `tools/launch-dashboard/README.md` | document `/summary` + sketchybar integration |
| `.config/sketchybar/items/launchdash.sh` | new item |
| `.config/sketchybar/plugins/launchdash.sh` | new plugin |
| `.config/sketchybar/sketchybarrc` | source the new item |

## Testing & deployment

- **Swift:** TDD the `/summary` route; full `swift test` must stay green. Then `./scripts/install.sh`
  rebuilds the release bundle and reloads the agent so it serves `/summary`. Verify with
  `curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/summary | jq`.
- **Sketchybar config is copied, not symlinked** (per CLAUDE.md): after editing the repo's
  `.config/sketchybar/`, deploy with `setupfiles/sync.sh` (or copy to `~/.config/sketchybar/`), then
  `sketchybar --reload`. Verify: glyph is green when both priority services run; stop one
  (`launchctl bootout …`) and confirm it goes red with count `1`; click → popup lists both with the
  right dots; kill the dashboard agent and confirm the glyph goes gray "?".
- The bash plugin is verified by running it directly (it should `--set` the item without error) and
  visually in the bar — same manual-verify approach used for `install.sh`.

## Out of scope (YAGNI)

- Exposing the transition-based crash set or crash history via `/summary` (the glyph only needs
  up/down "right now").
- Per-service controls from the sketchybar popup (start/stop/restart) — the menu-bar app already
  does control; the popup is read-only status.
- Remote push / webhooks (a separate future feature; `/summary` is a useful building block for it).
- Configuring which services the bar shows independently of `priorityLabels` — it intentionally
  mirrors the app's priority set.
