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
  each with size and a Delete button (confirmation first).
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

## Install

```bash
tools/disk-cleaner/scripts/install.sh
```

`setupfiles/sync.sh` runs this automatically when the app isn't installed yet.
