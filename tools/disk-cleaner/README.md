# disk-cleaner

Native SwiftUI app opened from the sketchybar disk-cleanup button (left-click;
right-click still runs a silent background sweep).

- **Disk Overview** — free space plus sizes of the usual disk hogs (Xcode,
  simulators, Android/Gradle, JS package caches, ML caches, Docker, Caches,
  Downloads, Trash, `~/Hacking`). Badges show whether the cleanup script handles
  each one. Symlinked (relocated) dirs show their target instead of a size.
- **Cleanup** — runs `bin/disk-cleanup.sh --progress` (optionally `--dry-run` /
  `--deep`) and shows each step live with what it found/freed. Shares the
  sketchybar lock so bar and app never sweep at once, and updates the bar icon.
- **Simulators & Emulators** — iOS simulators, simulator runtimes, Android AVDs and
  SDK system images, each with size and a Delete button (confirmation first).

## Install

```bash
tools/disk-cleaner/scripts/install.sh
```

`setupfiles/sync.sh` runs this automatically when the app isn't installed yet.
