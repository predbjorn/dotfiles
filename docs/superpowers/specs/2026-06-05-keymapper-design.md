# Keymapper — Design

**Status:** Approved (multi-agent brainstorming: Skeptic → Constraint Guardian → User Advocate → Arbiter). Ready for implementation planning.
**Date:** 2026-06-05
**Process:** Structured design review. Disposition: **APPROVED** after one REVISE cycle (truth-in-labeling only; no architecture change).

## What it is (honest framing — D34)

**Keymapper** is a **launcher & single-line keymap editor + full-keymap auditor**: a windowed, on-demand
macOS app that gives a structured editor for the app/folder launchers and single-line hotkeys spread
across `.config/karabiner.json` and `.config/skhdrc`, and a read-only auditor (conflict detection +
cheatsheet) over the *entire* keymap. The dotfiles remain the single source of truth; the app edits
only clearly-delimited **managed regions** and never touches anything else.

It is **not** an "entire keymap editor." Multi-line yabai window-management pipelines are **audit-only**
in v1 (see Scope).

## Goal

Kill the real daily friction in the keymap:
- App launching is split across two files with two scripts (`karabiner` `space+<letter>` →
  `bin/toggle_app.sh`; `skhd` `hyper-b` / `ctrl+alt+cmd-b` → `bin/focus_window_wrapper.sh`).
- The hyper namespace is mostly unused; there are disabled/TODO bindings and a literal duplicate
  (`cmd + alt - 8` defined twice in `skhdrc`).
- Editing means hand-editing a 587-line JSON file.

Keymapper provides one place to *see and reason about* the whole keymap, and to *structurally edit* the
tractable majority (launchers + single-line bindings) without hand-editing JSON.

## Scope (D1, D15, D35)

| Capability | Coverage |
|---|---|
| **Audit** (conflict detection, cheatsheet, lint) | **Entire keymap** — both files, including opaque rules |
| **Structured edit** | Launchers + single-line bindings (karabiner managed rules + skhd managed region) |
| **Multi-line yabai pipelines** | **Audit-only (v1):** conflict-counted, in cheatsheet, "Open in `$EDITOR` at this line". Structured editing is an explicit **v2** goal (D35). |

## Target files & deployment facts (ground truth)

- `.config/karabiner.json` — JSON, **symlinked** to the live location. Karabiner-Elements auto-reloads on
  change **and rewrites the file itself** when its own GUI is used.
- `.config/skhdrc` — plain text (skhd syntax), **copied** to the live location by `setupfiles/sync.sh`.
  Edits to the repo file are **not live** until copied + skhd reloaded.
- Existing launcher scripts: `bin/toggle_app.sh` (toggle), `bin/focus_window_wrapper.sh` (focus).
- `skhdrc` contains multi-line yabai shell pipelines (`yabai … && index="$(… | jq …)" && …`).

## Architecture

Windowed, on-demand SwiftUI app (SwiftPM, `tools/keymapper/`, plain `.app`, **no LaunchAgent/daemon**),
mirroring the engineering bar of the sibling `tools/launch-dashboard` app (Sources/, Tests/,
`scripts/install.sh`, XCTest).

### Components

1. **Importers (read).**
   - *karabiner:* load JSON into a **lossless ordered object graph** (D24) — unmanaged rules/subtrees
     decode as an ordered `JSONValue` preserving **all** keys, including unknown/future ones. Managed
     rules are those whose `description` carries the app-maintained `keymap:` prefix (D32).
   - *skhd:* parse the fenced region `# >>> keymap-managed >>>` … `# <<< keymap-managed <<<` into
     structured entries; parse the rest read-only. Every binding stores its **verbatim source text/span**
     (D8).
2. **Model.** `Binding { chord, action, sourceFile, layer, managed }`.
   - `action` for launchers = `{ app, mechanism: toggle | focus | raw, rawCommand }` where `rawCommand`
     verbatim is the source of truth (D11).
   - Complex/opaque actions store the raw command string; the **chord (left side) is still parsed** so the
     binding participates in conflicts + cheatsheet (D29).
   - `layer` ∈ `space-leader | space-f-leader | karabiner-modifier | skhd-modifier` (D14).
3. **Editor UI** (D30) — two clearly labelled sections:
   - **Managed:** editable launchers + single-line bindings.
   - **Reference:** the rest of the keymap, shown read-only for audit; copy sets the audit-only
     expectation up front (D36).
4. **Conflict + lint engine** (D14, D31) — flags same-chord-twice **within a layer**, literal duplicates,
   and dead/disabled bindings. Detection covers the **whole keymap including opaque/read-only chords** —
   no false comfort. Cross-layer same-letter (`space+b` vs `hyper+b`) is **not** a conflict.
5. **Cheatsheet** — searchable/filterable full list; export to Markdown/HTML.
6. **Writers.**
   - *karabiner* (D7): mutate **only** managed rule objects within the parsed object graph; re-serialize
     the **whole** file (no string-splice) with a serializer tuned to Karabiner's format (2-space indent,
     preserved key order). Byte-for-byte is **not** promised here — guarantee is **semantic equivalence**
     with a possible **one-time normalization diff** on first write, stable thereafter (D23).
   - *skhd* (D8): regenerate **only** the fenced region; unchanged bindings pass through **byte-for-byte**;
     only added/edited/removed bindings are re-emitted.
   - Both always: **atomic write** — temp file on the same volume + `rename(2)`; the drift re-read (below)
     is the last op before rename (D17). Always write to the **resolved repo file** (`$DOTFILES/.config/…`),
     never over the deployed symlink/copy (D18).

### Data flow

1. **First run (D26):** auto-adopt existing launcher bindings (the SpaceLauncher rule + skhd app-focus
   bindings) into the managed model in **one backed-up migration**. No empty state, no per-binding
   promotion ritual. From then on those launchers are editable.
2. Launch → import both files → build model (+ read-only Reference) → diff repo `skhdrc` vs deployed copy
   for live-state display (D13, D28).
3. Edit a managed binding → **Save** = one atomic action (D27): write both repo files **and** deploy
   (scoped skhd copy + `skhd --reload`; karabiner goes live via symlink). The whole change set goes live
   **together** — no Save/Apply split, no half-live state.
4. A separate **"Make it live"** action surfaces only for externally-caused drift (plain language, D28).

### Subprocess & security posture (D19, D20)

- All subprocess calls (`skhd --reload`) and the skhd file copy use **argv arrays** with **absolute/configured
  paths** — never `sh -c` string interpolation; the copy is a `FileManager` operation.
- Any structured field (app name, path) interpolated into a generated `shell_command`/skhd line is
  **shell-escaped** (D19). No network surface, no bearer token, no daemon, runs as the user (no escalation).

### Error handling & recovery

- **Reconcile-before-write (D10):** hash/mtime files at import; re-read immediately before writing; if
  changed since import (e.g. Karabiner GUI rewrote it), **abort + reload** rather than clobber. Warn if
  Karabiner-Elements settings UI is running; warn on managed-rule description drift caused by external
  GUI renames only (in-app rename is safe, D32).
- **Post-write validation is semantic (D25):** check managed-region invariants, not just JSON
  well-formedness. On invalid output, **auto-revert from backup and re-apply** (copy + reload) so the
  running daemon matches disk — backup is a live rollback, not cold storage (D9).
- **Refuse-to-write** on an unparseable managed region; never silently drop.
- **Backups (D21, D22):** user-only (0600), in `~/Library/Application Support/Keymapper/backups/`
  (gitignored / non-synced, never inside the repo); keep last 20 per file, prune older.

## Testing (TDD — D16)

Fixtures use **real-world adversarial file shapes**, not just author-constructed ones:
- a Karabiner-GUI-reformatted `karabiner.json`,
- a yabai pipeline with `$(…)` / `jq` / nested quoting,
- a rule with a colliding `keymap:` description,
- a hand-edited deployed skhd copy diverging from the repo.

Plus:
- **Round-trip identity** — skhd fenced region: import→export of unchanged input is **byte-identical**.
- **Unknown-future-key survives a write** (karabiner losslessness, D24).
- **Unchanged binding preserved byte-for-byte** (skhd, D8).
- **Shell-metacharacter app name round-trips inert** (injection guard, D19).
- **Corrupt write auto-reverts and re-applies** (D9/D25).
- **Conflict detection** units, including collisions against opaque/read-only chords (D31).
- **Cross-layer same-letter is not a conflict** (D14).

## Files

| File | Change |
|---|---|
| `tools/keymapper/` | new SwiftPM app (Sources/, Tests/, `scripts/install.sh`, Info.plist) |
| `tools/keymapper/README.md` | honest framing (D34) + v1 limitation statement (D35) |
| `.config/skhdrc` | add the `# >>> keymap-managed >>>` … `# <<< keymap-managed <<<` fence around adopted launchers (one-time, via first-run migration) |
| `.config/karabiner.json` | adopted launcher rules gain the app-maintained `keymap:` description prefix (one-time migration) |
| `~/Library/Application Support/Keymapper/backups/` | runtime backups (not committed) |

(`.gitignore` should already exclude `~/Library/...`; the backups path is outside the repo by design.)

## Out of scope (YAGNI)

- Managing zsh aliases/functions.
- Live key-capture recording (press keys to bind).
- A GUI for arbitrary karabiner manipulator types beyond launchers + simple remaps.
- **Structured** editing of multi-line yabai pipelines (audit-only in v1; named **v2** goal — D35).
- Cloud sync; multi-machine reconciliation.
- Any network surface / remote control.

## Decision Log

Source: `(user)` = user choice; `(skeptic)` / `(guardian)` / `(advocate)` / `(arbiter)` = resolved review
objection.

| # | Decision | Source / rationale |
|---|---|---|
| D1 | Scope = entire keymap (audit all; structured-edit launchers + single-line; multi-line yabai audit-only) | user |
| D2 | Ownership = managed regions only; dotfiles stay source of truth | user |
| D3 | Form = windowed, on-demand, no daemon | user |
| D7 | karabiner writer = object-graph mutate + whole-file re-serialize (no string-splice) | skeptic (corruption) |
| D8 | Store verbatim source; unchanged skhd bindings pass byte-for-byte; only changed re-emitted | skeptic (fidelity) |
| D9 | Post-write re-parse; auto-revert from backup on invalid output | skeptic/guardian |
| D10 | Hash/mtime at import; re-read before write; abort+reload on drift; description-drift warning | skeptic (GUI concurrency) |
| D11 | Launcher action `{app, mechanism, rawCommand}`; rawCommand verbatim is truth; edit keeps the same script | skeptic (toggle vs focus) |
| D12 | Apply = isolated skhd copy + reload only (not whole sync.sh) | skeptic (blunt side effect) |
| D13 | On launch, diff repo skhdrc vs deployed copy; show live state | skeptic (stale audit) |
| D14 | Per-layer namespace; conflicts only within a layer | skeptic (leader vs modifier) |
| D15 | Linter reports across all; fixes for managed; promote/open-at-line for non-managed | skeptic (over-promise) |
| D16 | Real-world adversarial test fixtures + preservation/revert tests | skeptic (tests ≠ reality) |
| D17 | Atomic write: temp file + rename(2); drift re-read is last op | guardian (atomicity) |
| D18 | Always edit resolved REPO file; never the symlink/copy | guardian (symlink preservation) |
| D19 | **[Blocker closed]** shell-quote all interpolated fields; metachar fixture | guardian (injection) |
| D20 | argv arrays + absolute paths; no `sh -c`; FileManager copy | guardian (subprocess) |
| D21 | Backups 0600, in App Support, gitignored, never in repo | guardian (privacy) |
| D22 | Backup retention: keep last 20 per file | guardian (disk growth) |
| D23 | Byte-for-byte for skhd region only; karabiner = semantic equivalence + one-time normalization diff | guardian (contradiction) |
| D24 | **[Blocker closed]** lossless ordered JSONValue for unmanaged subtrees; future-key fixture | guardian (schema drift) |
| D25 | Semantic post-write validation; revert re-applies (copy + reload) | guardian (revert correctness) |
| D26 | First-run auto-adopts launchers (one backed-up migration); no promotion ritual | advocate (first-run emptiness) |
| D27 | Save = one atomic write+deploy; no Save/Apply split; whole change set goes live together | advocate (split / asymmetry) |
| D28 | Plain-language "Make it live"; rare given D27 | advocate (jargon) |
| D29 | Opaque bindings parsed at chord level (conflicts + cheatsheet) + open-at-line | advocate (worst-of-both) |
| D30 | UI = "Managed" (editable) + "Reference" (read-only audit) sections | advocate (greyed majority) |
| D31 | Conflict engine covers the whole keymap incl. opaque chords | advocate (false comfort) |
| D32 | `keymap:` prefix app-maintained; in-app rename safe; drift warning only on external GUI rename | advocate (rename punished) |
| D33 | Dual identity mechanism hidden behind Managed/Reference UI | advocate (two mechanisms) |
| D34 | Honest framing: "launcher & single-line editor + full-keymap auditor", not "entire keymap editor" | arbiter (truth-in-labeling) |
| D35 | Multi-line yabai = audit-only v1; structured edit named as v2 | arbiter |
| D36 | Reference section copy sets audit-only expectation up front | arbiter |

**Rejected / deferred objections:** none outstanding. The Arbiter declined to reopen scope (no cause; the
engineering is sound and progressive delivery was accepted), requiring only the branding fixes now encoded
in D34–D36.
