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
- **Cheatsheet** — full-keymap Markdown export with copy-to-clipboard and save-to-file.
- **Conflict detection** — covers the entire keymap including unmanaged bindings (no false comfort).
- **Drift detection** — shows a "Make it live" banner if the repo skhdrc is ahead of the deployed copy.

## v1 limitations

- **Multi-line yabai pipelines are audit-only.** The reference section shows them and flags conflicts,
  but you cannot structurally edit them here. Use "Open in $EDITOR" and edit manually.
  Structured editing of multi-line pipelines is a planned v2 goal.
- Adding new bindings is limited to the skhd `hyper` modifier layer. Space-leader (karabiner)
  bindings must be edited manually for now.

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
