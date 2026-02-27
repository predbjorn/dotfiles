# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal macOS dotfiles repository (`~/.dotfiles`) that automates development environment setup. Manages shell configuration, window management, keyboard shortcuts, and development tooling via symlinks and setup scripts.

## Installation

Run `./install.sh` from the repo root. It must be run **multiple times** to complete setup (some steps depend on prior steps finishing). Prerequisites: Xcode installed, Apple Store logged in, Full Disk Access for Terminal, SSH key on GitHub, `gh auth login` completed.

## Repository Structure

- **`install.sh`** — Main orchestrator that calls setup scripts in order
- **`setupfiles/`** — Individual setup scripts (zsh, node, python, ruby, npm, sync, macos, init_script)
- **`.config/`** — All configuration files (zshrc, yabairc, skhdrc, karabiner, sketchybar, finicky, cloudflared)
- **`zsh/`** — Zsh modules loaded by .zshrc: `aliases.zsh`, `path.zsh`, `functions.zsh`, `functions2.zsh`, `.env.zsh`
- **`bin/`** — Executable scripts (focus_window_wrapper.sh, claude-worktree.sh)
- **`script/`** — Utility scripts (windowarr.sh, setCronjobs.py, setupGitRepos.py, wallpaper.py)
- **`AppleScripts/`** — macOS automation (hacktime, project launchers, window arrangement)
- **`Brewfile`** — Homebrew package definitions

## Symlink Strategy

Dotfiles are deployed via symlinks and copies in the setup scripts:

- **`setupfiles/zsh.sh`** — Symlinks `.zshrc`, `.p10k.zsh`, `.gemrc` from `.config/` to `$HOME`
- **`setupfiles/sync.sh`** — Symlinks/copies yabairc, skhdrc, karabiner.json, sketchybar, finicky, cloudflared configs to their standard locations under `$HOME/.config/` or `$HOME/`

Key env vars: `$DOTFILES` → `~/.dotfiles`, `$XDG_CONFIG_HOME` → `~/.config`

## Key Tools Configured

- **Shell**: Zsh + oh-my-zsh + Powerlevel10k theme
- **Window management**: Yabai (tiling WM) + skhd (hotkey daemon) + Sketchybar (status bar)
- **Keyboard**: Karabiner-Elements (caps→hyper, space-as-leader app launcher)
- **Browser routing**: Finicky
- **Version managers**: NVM (Node), pyenv (Python), rbenv (Ruby), jenv (Java)

## When Editing Configs

- Zsh aliases/functions/paths are modular files in `zsh/` — edit the specific file, not `.config/.zshrc`
- Window management shortcuts live in `.config/skhdrc`; window arrangement helpers in `script/windowarr.sh`
- Yabai rules (ignored apps, layout settings) are in `.config/yabairc`
- Sketchybar has its own directory structure under `.config/sketchybar/` with items, plugins, and a helper binary
- After changing symlinked configs, no re-linking needed; after changing copied configs (sketchybar, finicky, Warp theme), re-run `setupfiles/sync.sh` or copy manually
