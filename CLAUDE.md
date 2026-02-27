# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal macOS dotfiles repository (`~/.dotfiles`) that automates development environment setup. Manages shell configuration, window management, keyboard shortcuts, and development tooling via symlinks and setup scripts.

## Installation

- **Full install**: Run `./install.sh` — must be run **multiple times** (some steps depend on prior steps).
- **Lightweight install**: Run `./install-light.sh` — minimal setup for a secondary Mac. Use `--check` to verify status.
- Prerequisites: Xcode installed, Apple Store logged in, Full Disk Access for Terminal, SSH key on GitHub, `gh auth login` completed.

## Repository Structure

- **`install.sh`** / **`install-light.sh`** — Install orchestrators (full vs lightweight)
- **`setupfiles/`** — Individual setup scripts: `common.sh` (shared helpers), `zsh.sh`, `node.sh`, `python.sh`, `ruby.sh`, `npm.sh`, `sync.sh` (deploy configs), `init_script.sh`, `macos.sh`
- **`.config/`** — All configuration files (zshrc, yabairc, skhdrc, karabiner.json, sketchybar/, .finicky.js, cloudflared/)
- **`zsh/`** — Zsh modules loaded by .zshrc: `aliases.zsh`, `path.zsh`, `functions.zsh`, `.env.zsh` (secrets, gitignored)
- **`bin/`** — Executable scripts: `focus_window_wrapper.sh` (yabai app focus), `claude-worktree.sh` (git worktree + claude)
- **`script/`** — Utility scripts: `wallpaper.py` / `wallpaper_gemini.py` (AI wallpaper generators), `windowarr.sh` (yabai helpers), `setCronjobs.py`, `sync-brew.sh` (Brewfile drift checker)
- **`AppleScripts/`** — macOS automation (hacktime window arrangement, project launchers)
- **`githubProjects/`** — Repo list + clone script + .env backup/restore
- **`Brewfile`** / **`Brewfile.light`** — Homebrew package definitions (full vs minimal)
- **`resources/`** — Sound effects for shell notifications (Zelda, Star Wars, Pokemon)
- **`themes/`** — Warp terminal Catppuccin Mocha theme

## Symlink Strategy

Dotfiles are deployed via symlinks and copies in the setup scripts:

- **`setupfiles/zsh.sh`** — Symlinks `.zshrc`, `.p10k.zsh`, `.gemrc` from `.config/` to `$HOME`
- **`setupfiles/sync.sh`** — Symlinks karabiner.json and yabairc; copies skhdrc, sketchybar/, .finicky.js, and Warp theme to their standard locations

Key env vars: `$DOTFILES` → `~/.dotfiles`, `$XDG_CONFIG_HOME` → `~/.config`

Symlinked configs take effect immediately. Copied configs (sketchybar, finicky, skhd, Warp theme) require re-running `setupfiles/sync.sh`.

## Key Tools Configured

- **Shell**: Zsh + oh-my-zsh + Powerlevel10k theme
- **Window management**: Yabai (tiling WM) + skhd (hotkey daemon) + Sketchybar (status bar, Catppuccin theme)
- **Keyboard**: Karabiner-Elements (caps→hyper, space-as-leader app launcher, fn-key passthrough)
- **Browser routing**: Finicky (Safari default, Chrome for Google Meet/Docs)
- **Version managers**: NVM (Node), pyenv (Python), rbenv (Ruby), jenv (Java)
- **Tunnel**: Cloudflare tunnel for localhost exposure

## When Editing Configs

- Zsh aliases/functions/paths are modular files in `zsh/` — edit the specific file, not `.config/.zshrc`
- Window management shortcuts live in `.config/skhdrc`; window arrangement helpers in `script/windowarr.sh`
- Yabai rules (ignored apps, layout settings) are in `.config/yabairc`
- Karabiner keyboard remapping (hyper key, SpaceLauncher shortcuts) is in `.config/karabiner.json`
- Sketchybar has its own directory structure under `.config/sketchybar/` with items/, plugins/, and a C helper binary
- After changing symlinked configs, no re-linking needed; after changing copied configs (sketchybar, finicky, skhd, Warp theme), re-run `setupfiles/sync.sh` or copy manually
