# Launch Dashboard: Inspect URLs + Tunnel Routes — Design

**Date:** 2026-06-07
**Component:** `tools/launch-dashboard/` (Swift / SwiftUI menu-bar app)
**Status:** Approved (design)

## Summary

Two independent features for the LaunchDashboard menu-bar app:

1. **Inspect URL** — clicking a service row (e.g. `com.nors.ai-daemon`) opens that
   service's URL in the browser. Per-service URLs (public + local) are configured in
   `config.json`.
2. **Tunnel routes** — a separate window lists the cloudflared ingress rules from
   `~/.cloudflared/config.yml` with on/off toggles, editing the config (comment-out)
   and reloading the tunnel.

No new third-party dependencies (the app is dependency-free by design).

---

## Feature 1 — Inspect URL

### Config mechanism

Add an optional map to `Config` (decodes from `config.json`):

```json
"inspectTargets": {
  "com.nors.ai-daemon": {
    "public": "https://daemon.prebenhafnor.com",
    "local":  "http://localhost:8787"
  }
}
```

- Optional (`inspectTargets: [String: InspectTarget]?`) so existing `config.json`
  still decodes.
- `InspectTarget = { public: String?, local: String? }` — both optional; a target
  with neither is treated as absent.
- Seeded for `com.nors.ai-daemon`; the user adds more entries by hand.

### UI behavior (`ServicesView`)

- A row whose `label` has an `inspectTargets` entry with a non-nil `public` (or
  `local`) becomes **clickable**: subtle accent tint on the label plus a small
  `globe` SF Symbol.
- Clicking the row opens **public** (falling back to `local` if `public` is nil) via
  `NSWorkspace.shared.open(url)`.
- The existing `⋯` menu gains explicit items when a target exists:
  - `Open <public host>` → opens the public URL
  - `Open <local host:port>` → opens the local URL
  - Only the items whose URL is present are shown.
- Rows with no target render exactly as today (plain, non-clickable).

### Data flow

`AppDelegate` already owns `config`. It passes `config.inspectTargets` into
`ServicesViewModel` (new `@Published var inspectTargets: [String: InspectTarget]`)
during `pollOnQueue()` (or once at init, since it's immutable). `ServicesView`
invokes a new `onOpenURL: (URL) -> Void` closure wired by `MenuBarController` /
`AppDelegate` to `NSWorkspace.open`.

---

## Feature 2 — Tunnel routes (view + toggle)

### Entry point

A **"Tunnel routes…" button** in the popover footer (next to the legend). The
`.transient` popover closes as the new window takes focus, which is fine.

### Window

`UI/TunnelRoutesView.swift` hosted in an `NSWindow` (via a small
`TunnelRoutesWindowController`). Contents:

- A table/list of ingress rules: each shows `hostname → service` with an on/off
  `Toggle`.
- The catch-all rule (`- service: http_status:404`, no hostname) is shown
  **read-only** and is never toggleable.
- A status line shows the result of the last apply ("Reloaded", or an error).

### Toggle semantics

- **Off** = prefix the rule's lines (`- hostname:` and its following `service:`)
  with `# ` (preserving indentation).
- **On** = strip the leading comment prefix from those lines.
- Pure line-based transform. Comments and every other line in the file are
  preserved verbatim. No YAML library; no reformatting.

### Write path (symlink-aware)

`~/.cloudflared/config.yml` is a **symlink** into the dotfiles repo (created by
`install.sh`). To avoid clobbering the symlink:

1. Resolve the symlink to its real target (the dotfiles file).
2. Atomic-write the new text to the **real target** (temp file + rename within the
   target's directory), preserving the file's POSIX permissions.
3. The symlink at `~/.cloudflared/config.yml` continues to point at the (updated)
   dotfiles file.

This surfaces as a git diff in dotfiles, which the user commits when ready
(accepted trade-off).

After a successful write, reload the tunnel:

```
launchctl kickstart -k gui/$(id -u)/com.prebenhafnor.cloudflared
```

### Config knobs

Optional `Config` fields with code-level defaults (no need to set them):

- `cloudflaredConfigPath` — default `~/.cloudflared/config.yml`
- `cloudflaredLabel` — default `com.prebenhafnor.cloudflared`

---

## Architecture

| Piece | Type | Responsibility |
|---|---|---|
| `Models/InspectTarget.swift` (or in `Config.swift`) | new | `{ public: String?, local: String? }` |
| `Models/IngressRule.swift` | new | `{ hostname: String?, service: String, enabled: Bool, isCatchAll: Bool, lineRange }` |
| `Core/IngressConfigParser.swift` | new | **pure**: `parse(text) -> [IngressRule]`, `toggle(text, hostname) -> String` |
| `Core/CloudflaredController.swift` | new | IO: resolve symlink, read, parse, atomic-write to real target, reload via launchctl |
| `UI/TunnelRoutesView.swift` | new | routes window SwiftUI view |
| `UI/TunnelRoutesWindowController.swift` | new | hosts the view in an `NSWindow`, single-instance |
| `Models/Config.swift` | edit | add `inspectTargets`, `cloudflaredConfigPath`, `cloudflaredLabel` (all optional) |
| `UI/ServicesView.swift` | edit | clickable rows, open-URL menu items, footer "Tunnel routes…" button |
| `UI/MenuBarController.swift` | edit | thread `onOpenURL` and `onOpenTunnelRoutes` closures |
| `AppDelegate.swift` | edit | wire `NSWorkspace.open` + open-routes-window; pass `inspectTargets` to the VM |

### Parsing model (Feature 2 detail)

The `ingress:` section is a YAML list. Each rule is one of:

- **Active host rule** — `- hostname: <h>` line followed by a `  service: <s>` line.
- **Commented host rule** — `# - hostname: <h>` followed by `#   service: <s>`
  (the comment prefix may be `# ` or `#`).
- **Catch-all** — `- service: http_status:404` (no hostname) → `isCatchAll = true`.

The parser records each rule's source line range so `toggle()` only rewrites those
lines. Descriptive comment lines that don't match a host-rule shape (e.g.
`# nors ai-daemon dashboard`) are passthrough and left untouched. A rule the parser
can't confidently model is surfaced read-only with its toggle disabled.

---

## Error handling

- `config.yml` missing/unreadable → routes window shows an error, no toggle rows.
- Unparseable/ambiguous rule → shown, toggle disabled.
- Parse failure on apply → file left untouched, error in status line.
- Write failure → file left untouched (atomic rename), error surfaced.
- Reload failure → error surfaced; the file edit still stands (user can reload by hand).

---

## Testing

- `IngressConfigParserTests` (pure, no IO):
  - parse active + commented + catch-all from a representative `config.yml`.
  - round-trip: `parse → toggle(off) → parse` shows the rule disabled; toggling on
    restores byte-identical text (idempotency both directions).
  - indentation preserved; comment prefix `# ` vs `#` both handled.
  - catch-all is never affected by `toggle()`.
  - non-host comment lines preserved verbatim.
- `ConfigTests`: decoding `config.json` with and without `inspectTargets`;
  `InspectTarget` with partial fields.
- IO/reload layer (`CloudflaredController`) kept thin; symlink-resolution +
  atomic-write covered by a focused test against a temp symlink if practical.

---

## Out of scope (YAGNI)

- No HTTP endpoints for ingress — stays local UI only. (Future extension.)
- No add/remove of routes in the UI — toggle existing rules only. (Future
  extension.)
- No editing of service targets/ports from the UI.
