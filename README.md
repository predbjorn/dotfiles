# dotfiles

Personal macOS dotfiles repository (`~/.dotfiles`) that automates development environment setup. Manages shell configuration, window management, keyboard shortcuts, and development tooling via symlinks and setup scripts.

## Quick Start

### Prerequisites

1. Install Xcode from the App Store
2. Log in to Apple Store
3. Grant Full Disk Access: System Settings > Privacy & Security > Full Disk Access > Terminal
4. Generate SSH key and add to GitHub:
   ```sh
   cd ~/dotfiles
   chmod +x gitssh.sh
   ./gitssh.sh
   ```
   Then follow the [GitHub SSH guide](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account).
5. Authenticate GitHub CLI:
   ```sh
   gh auth login   # Select SSH, then login in browser
   ```

### Full Install (primary Mac)

```sh
chmod +x install.sh
./install.sh
```

Must be run **multiple times** — some steps depend on prior steps finishing (e.g. Homebrew must exist before packages install, zsh must be set before node/python setup).

After install, set Finicky as default browser.

### Lightweight Install (secondary Mac)

```sh
chmod +x install-light.sh
./install-light.sh
```

Installs a minimal subset: core CLI tools, pyenv + Python, NVM + Node, pnpm, the window management stack (Yabai + skhd + Sketchybar), and lightweight GUI apps (iTerm2, Cursor, Flycut, Karabiner-Elements).

Check install status anytime:
```sh
./install-light.sh --check
```

## Repository Structure

```
dotfiles/
├── install.sh                  Main orchestrator (primary Mac)
├── install-light.sh            Lightweight installer (secondary Mac)
├── gitssh.sh                   SSH key generation helper
├── Brewfile                    Full Homebrew package list
├── Brewfile.light              Minimal Homebrew package list
│
├── setupfiles/                 Individual setup scripts
│   ├── common.sh               Shared helpers (colors, check_tool, setup_homebrew)
│   ├── zsh.sh                  Zsh + oh-my-zsh + Powerlevel10k + symlinks
│   ├── node.sh                 NVM + Node LTS
│   ├── python.sh               pyenv + Python 3.12 + pip packages
│   ├── ruby.sh                 rbenv setup
│   ├── npm.sh                  Global npm packages
│   ├── sync.sh                 Deploy window manager + tool configs
│   ├── init_script.sh          Cron jobs + git repo cloning
│   ├── macos.sh                macOS defaults (Finder, Dock, screenshots)
│   └── java.md                 Manual jenv/Java setup notes
│
├── .config/                    Configuration files
│   ├── .zshrc                  Main Zsh config
│   ├── .p10k.zsh               Powerlevel10k prompt theme
│   ├── .gemrc                  Ruby gem config
│   ├── .finicky.js             Browser routing rules
│   ├── karabiner.json          Keyboard remapping (Karabiner-Elements)
│   ├── skhdrc                  Hotkey daemon config (skhd)
│   ├── yabairc                 Tiling window manager config (Yabai)
│   ├── cloudflared/            Cloudflare tunnel config
│   └── sketchybar/             Status bar config + plugins + C helper
│
├── zsh/                        Zsh modules loaded by .zshrc
│   ├── aliases.zsh             Shell aliases
│   ├── path.zsh                PATH exports and env vars
│   ├── functions.zsh           Shell functions
│   └── .env.zsh                Secrets (gitignored)
│
├── bin/                        Executable scripts
│   ├── focus_window_wrapper.sh Yabai app-focus helper (used by skhd)
│   └── claude-worktree.sh      Git worktree + Claude session launcher
│
├── script/                     Utility scripts
│   ├── wallpaper.py            AI wallpaper generator (DALL-E 3)
│   ├── wallpaper_gemini.py     AI wallpaper generator (Gemini)
│   ├── setCronjobs.py          Installs wallpaper cron job
│   ├── windowarr.sh            Yabai window/space arrangement helpers
│   └── sync-brew.sh            Brewfile drift checker
│
├── AppleScripts/               macOS automation scripts
│   ├── hacktime.applescript    Open dev apps + arrange windows
│   ├── portal.applescript      Launch portal project in iTerm
│   ├── tren.applescript        Launch tren project in iTerm
│   ├── fou.applescript         Launch foundation project in iTerm
│   └── ...
│
├── githubProjects/             Git repo management
│   ├── githubProject           Repo list (owner/repo → local path)
│   ├── setupGitRepos.py        Clone missing repos via gh
│   ├── copy_env.py             Backup .env files
│   └── paste_env.py            Restore .env files
│
├── themes/                     Terminal themes
│   └── catppuccin_mocha.yml    Warp terminal theme (Catppuccin Mocha)
│
├── resources/                  Sound effects for shell notifications
│   ├── zelda.wav
│   ├── randomstarwars/1-5.wav
│   └── ...
│
└── oh-my-zsh/lib/
    └── correction.zsh          Custom nocorrect overrides
```

## Install Flow

### `install.sh` (full)

Runs these steps sequentially:

1. `setupfiles/common.sh` — load helpers, set env vars
2. Install Xcode CLI tools (exits if not present — rerun)
3. Install/update Homebrew
4. `setupfiles/zsh.sh` — Zsh, oh-my-zsh, Powerlevel10k, symlinks
5. `brew bundle` — install everything in `Brewfile`
6. `setupfiles/node.sh` — zsh-nvm plugin + Node LTS
7. `setupfiles/python.sh` — pyenv + Python 3.12 + pip packages
8. `setupfiles/ruby.sh` — rbenv
9. `setupfiles/npm.sh` — global npm packages
10. `setupfiles/sync.sh` — deploy window manager configs
11. Symlink cloudflared config
12. `setupfiles/init_script.sh` — cron jobs + clone git repos
13. Create `~/screenshots`
14. `setupfiles/macos.sh` — apply macOS defaults

### `install-light.sh` (lightweight)

Runs only steps 1-4, 6-7 with `Brewfile.light` instead of `Brewfile`. Skips: ruby, npm globals, sync, init scripts, and macOS defaults. Includes a `--check` mode for status reporting.

## Symlink Strategy

Dotfiles are deployed via symlinks and copies:

| Script | Source | Destination | Method |
|--------|--------|-------------|--------|
| `zsh.sh` | `.config/.zshrc` | `~/.zshrc` | symlink |
| `zsh.sh` | `.config/.p10k.zsh` | `~/.p10k.zsh` | symlink |
| `zsh.sh` | `.config/.gemrc` | `~/.gemrc` | symlink |
| `sync.sh` | `.config/karabiner.json` | `~/.config/karabiner/karabiner.json` | symlink |
| `sync.sh` | `.config/yabairc` | `~/.config/yabai/yabairc` | symlink |
| `sync.sh` | `.config/skhdrc` | `~/.config/skhd/skhdrc` | copy |
| `sync.sh` | `.config/sketchybar/` | `~/.config/sketchybar/` | copy (full dir) |
| `sync.sh` | `.config/.finicky.js` | `~/.finicky.js` | copy |
| `sync.sh` | `themes/catppuccin_mocha.yml` | `~/.warp/themes/` | copy |
| `install.sh` | `.config/cloudflared/` | `~/.cloudflared/config.yml` | symlink |

Symlinked configs take effect immediately on edit. Copied configs (sketchybar, finicky, skhd, Warp theme) require re-running `sync.sh` or copying manually.

## Key Tools

### Shell: Zsh + oh-my-zsh + Powerlevel10k

`.config/.zshrc` loads oh-my-zsh with plugins (`git`, `zsh-autosuggestions`, `zsh-nvm`, `zsh-syntax-highlighting`) and the Powerlevel10k theme. Modular config is split across `zsh/`:

- **`aliases.zsh`** — Git shortcuts (`commit`, `gd`, `gitclearall`), directory navigation (`_hack`, `_dot`), React Native helpers (`rni`, `clean`, `is`), system utilities (`caff`, `tunnel`)
- **`path.zsh`** — PATH setup for Homebrew, pyenv, rbenv, jenv, NVM, Android SDK, Google Cloud SDK, VS Code
- **`functions.zsh`** — `mk` (mkdir+cd), `update` (full system update), `hacktime` (open all dev apps), `check` (find unused npm deps), `_done` (play random Star Wars sound)
- **`.env.zsh`** — Secrets and API keys (gitignored)

### Window Management: Yabai + skhd + Sketchybar

**Yabai** (`.config/yabairc`) — BSP tiling window manager. 40px top gap for Sketchybar, 12px window gaps. Excludes System Settings, Simulator, and other non-tileable apps from management. Pins specific apps to displays/spaces (Safari → display 2, Spotify → space 5).

**skhd** (`.config/skhdrc`) — Hotkey daemon providing:
- `alt + hjkl` — focus windows (vim-style)
- `shift + alt + hjkl` — swap/move windows
- `hyper + hjkl` — resize windows
- `cmd + alt + 1-8` — focus spaces
- `shift + alt + 1-9` — move window to space
- `alt + f` — fullscreen, `alt + t` — float/center, `alt + g` — toggle gaps
- `hyper + r` — re-run sync.sh, `hyper + p` — generate wallpaper
- `ctrl + shift + [key]` — focus specific apps (with force-move via `cmd` modifier)

**Sketchybar** (`.config/sketchybar/`) — Custom status bar with Catppuccin Mocha theme. Widgets: workspace indicators, focused app, Spotify (with rich popup controls), calendar, brew updates, GitHub notifications, WiFi, battery, CPU usage, Svim mode. Includes a compiled C helper for CPU stats.

### Keyboard: Karabiner-Elements

`.config/karabiner.json` has 5 complex modification rules:
1. **Disable Cmd+Opt+H/M** — prevent accidental "Hide Others" / "Minimize All"
2. **Fn-key passthrough** — F1-F12 as function keys in dev apps (iTerm, VS Code, etc.)
3. **Caps Lock → Hyper** — remaps to Cmd+Ctrl+Opt+Shift (used extensively by skhd)
4. **Right Cmd + hjkl → Arrow keys** — vim navigation (disabled by default)
5. **SpaceLauncher shortcuts** — Hold space as a modifier key for app launching:

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| Space+B | Safari | Space+N | Notes |
| Space+T | Toggl Track | Space+M | Mail |
| Space+G | Chrome | Space+P | Spotify |
| Space+S | Slack | Space+U | Postman |
| Space+C | VS Code | Space+. | iTerm |
| Space+X | Xcode | Space+L | Sourcetree |
| Space+D | Simulator | Space+\ | Sourcetree |
| Space+R | RN Debugger | Space+8 | Spotify Play/Pause |

Two-key folder shortcuts (Space+F, then):
- **D** → `~/Downloads`, **C** → `~/Library/Mobile Documents` (iCloud), **R** → `~/Library`

Tapping space alone (< 200ms) types a normal space.

### Browser Routing: Finicky

`.config/.finicky.js` — Default browser is Safari. Routes `meet.google.com`, `plus.google.com`, and `datastudio.google.com` to Chrome.

### Version Managers

- **NVM** (Node) — installed via zsh-nvm oh-my-zsh plugin
- **pyenv** (Python) — Python 3.12 with pip packages: openai, requests, google-genai, python-dotenv
- **rbenv** (Ruby) — installed, manual version setup
- **jenv** (Java) — PATH configured, manual setup documented in `setupfiles/java.md`

### Cloudflare Tunnel

`.config/cloudflared/config.yml` — Named tunnel mapping `local8000.prebenhafnor.com` to `http://localhost:8000`. Started via the `tunnel` alias.

## Scripts

### AI Wallpaper Generators

- `script/wallpaper.py` — Generates dark forest landscapes in Catppuccin colors using DALL-E 3
- `script/wallpaper_gemini.py` — Same concept using Google Gemini
- `script/setCronjobs.py` — Installs a daily noon cron job for wallpaper generation
- Triggered manually via `hyper + p` (skhd shortcut)

### Window Arrangement

- `script/windowarr.sh` — Helper functions for Yabai space/window management (`ensure_space_exists`, `move_app_to_space`, `move_all_windows_from_space`)
- `bin/focus_window_wrapper.sh` — Smart app focus: finds window on current display, falls back to other displays, optionally force-moves to current space
- `AppleScripts/hacktime.applescript` — Detects monitor config and positions dev app windows in a grid layout

### Git Repo Management

- `githubProjects/githubProject` — List of repos to clone (owner/repo → local path)
- `githubProjects/setupGitRepos.py` — Clones any repos from the list that don't exist locally
- `githubProjects/copy_env.py` / `paste_env.py` — Backup and restore `.env` files across projects

### Brewfile Drift

`script/sync-brew.sh` — Compares installed packages against `Brewfile`, reports packages installed locally but not tracked, and apps in `/Applications` not in the Brewfile.

## Brewfile vs Brewfile.light

| | Brewfile (full) | Brewfile.light |
|---|---|---|
| **CLI tools** | git, gh, wget, jq, fd, trash, mas, coreutils, cloudflared, nmap, imagemagick, mongosh, docker-compose, aria2 | git, gh, wget, jq, fd, trash, coreutils, lazygit, delta, tmux, eza |
| **Languages** | pyenv, rbenv, openjdk, jenv, maven, cocoapods, fastlane | pyenv, pnpm |
| **WM stack** | yabai, skhd, sketchybar, borders, switchaudio-osx | same |
| **GUI apps** | VS Code, Chrome, Firefox, Slack, iTerm2, Warp, Spotify, Android Studio, Docker, Postman, Sourcetree, Karabiner, Steam, Discord, ~20 more | iTerm2, Cursor, Flycut, Karabiner-Elements |
| **App Store** | Keynote, Pixelmator, Numbers, Pages, Kindle, Flow, Dropover | — |

## Backup

1. Run `githubProjects/copy_env.py` to back up `.env` files
2. Commit and push dotfiles changes
