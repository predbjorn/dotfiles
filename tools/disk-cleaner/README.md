# disk-cleaner

Native SwiftUI app opened by left-clicking the sketchybar storage item
(free space). Right-click there scans with spaceburst and opens the map in the
browser instead.

- **Disk Overview** — free space plus sizes of the usual disk hogs (Xcode,
  simulators, Android/Gradle, JS package caches, ML caches, Docker, Caches,
  Downloads, Trash, `~/Hacking`). Badges show whether the cleanup script handles
  each one. Symlinked (relocated) dirs show their target instead of a size.
- **Cleanup** — runs `bin/disk-cleanup.sh --progress` (optionally `--dry-run` /
  `--deep`) and shows each step live with what it found/freed.
- **Devices & Caches** — iOS simulators, simulator runtimes, Android AVDs and
  SDK system images, Xcode DerivedData (per project/worktree) and Gradle caches,
  each with size and a Delete button (confirmation first). Rows show **who uses
  them** so you can tell what's safe to delete: Gradle caches/distributions list
  the repos whose `gradle/wrapper/gradle-wrapper.properties` pins that version
  (main checkout + worktree count, expand for names; `Unused` / `Worktrees only`
  badges), iOS runtimes list the projects whose deployment target they satisfy
  (`Only runtime for N` vs `Replaceable`), and simulators/AVDs note the repo
  they're named for and any `~/.simq/policy.json` pin. `~/Hacking` (or
  `$HACKING`) is scanned with `find`, skipping `node_modules`, `Pods`, build
  dirs and hidden dirs other than `.claude`/`.worktrees`.
  DerivedData and **Claude Scratch Builds** (`xcodebuild -derivedDataPath` inside
  `/private/tmp/claude-<uid>/*/*/scratchpad`) are marked `In use` when any process
  has its working directory in that worktree (`lsof`) or an xcodebuild is writing
  there; the header's **Delete N idle** removes only the rest. Gradle has
  **Delete N unused** (versions nothing pins), and stopped simulators get
  **Clear caches** (their `Library/Caches` + `tmp`; apps and data stay).
- **Disk Map** — the [spaceburst](https://github.com/cfmatre/spaceburst) sunburst
  of the whole Data volume, shown in a web view. Rescan from the toolbar (live
  progress), or right-click a wedge to reveal it in Finder, copy its path or
  rescan just that folder. Expects the repo at `~/Hacking/projects/spaceburst`
  (override with `SPACEBURST`).

`open diskcleaner://<pane>` (`overview`, `cleanup`, `devices`, `map`) switches
pane, also when the app is already running.

The scan runs as Disk Cleaner, so for a complete map give the app Full Disk
Access (the "N folders unreadable" link in the Disk Map header opens the setting).
macOS may drop that grant after a rebuild, since the app is ad-hoc signed.

## simq

When simq (`~/Hacking/simq`) is set up, the Devices pane reads its
`$SIMQ_HOME/policy.json` and `state.json` (default `~/.simq`, read-only, no lock)
and shows:

- a summary line: sims/emulators held, sessions queued, pending requests;
- pool sims/AVDs as `simq Sim-A · held|free|reserved|booted outside simq`, with who holds it and how
  long it has been idle. Delete is disabled while a session holds one, and
  otherwise warns that removing it breaks the pool;
- running sims/AVDs outside the pool as `Running · outside simq pool`;
- `Pinned by simq` on the pinned iOS runtime and Android system image (deleting
  one asks with a warning that it breaks the pool and `simq repair`), and a
  `simq pin` suffix on pinned Gradle versions. Gradle versions simq doesn't pin
  get **Delete N not pinned by simq**.

The **simq** pane (`diskcleaner://simq`, or `-pane simq` on launch) is where you
answer simq instead of the terminal. Its sidebar badge shows the pending request
count; the sketchybar simq badge opens it. It re-reads `$SIMQ_HOME` whenever simq
writes it and runs every change through the `simq` CLI (`$SIMQ_BIN`, else
`~/.local/bin/simq`) with `CLAUDE_*` stripped, so simq sees a human. URLs only
switch panes; they never run an action.

- **Waiting for you:** pending requests, newest first, with **Approve**,
  **Approve + pin** (download requests), **Force** (once simq says the request
  needs `--force`) and **Deny**. CLI output shows under the row.
- **Pool:** each pool device with holder, held for and idle for; past
  `idle_minutes` it's flagged "will be handed over on request". **Release**
  (asks first if a Claude session is still active on it; **Release mine** for
  yours) and **Take** (`simq acquire <kind> --device X`, free or idle devices
  only).
- **Queues:** sessions waiting per kind, with position and wait time.
- **Pool:** booted state comes from `simctl`/`adb` every 15 s. A pool device that is
  booted with no lease shows **booted outside simq** (sessions can't take it) and a
  **Shut down** button (`simq release <device>`); if a session's process ended while
  holding it, the row says simq keeps it for that session when it resumes.
- **Health:** **Run doctor** shows `simq doctor` output. **Create missing devices**
  runs `simq repair`, which recreates pool simulators and emulators that no longer
  exist (same names; **Force** appears when disk space is short).

Buttons are disabled while a command runs. A missing `~/.simq` or a broken policy
hides all of this (the pane says "simq not set up"). Tests:
`swift test` (fixture in `Tests/DiskCleanerTests/Fixtures/simq`). To preview a
state, run `open -a DiskCleaner --env SIMQ_HOME=/path/to/fixture`.

## Install

```bash
tools/disk-cleaner/scripts/install.sh
```

`setupfiles/sync.sh` runs this automatically when the app isn't installed yet.
