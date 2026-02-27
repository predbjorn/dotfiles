#!/bin/bash

# common.sh — Shared helper library for install scripts
# Sourced by install.sh and install-light.sh

# ─── Color output helpers ───────────────────────────────────────────

info()    { printf "\033[0;34m[info]\033[0m  %s\n" "$1"; }
success() { printf "\033[0;32m[ok]\033[0m    %s\n" "$1"; }
warn()    { printf "\033[0;33m[warn]\033[0m  %s\n" "$1"; }
fail()    { printf "\033[0;31m[FAIL]\033[0m  %s\n" "$1"; }

# ─── Utility functions ──────────────────────────────────────────────

cmd_exists() {
    command -v "$1" &>/dev/null
}

# check_tool NAME COMMAND — report installed/missing with version
check_tool() {
    local name="$1"
    local cmd="$2"
    if cmd_exists "$cmd"; then
        local ver
        ver=$("$cmd" --version 2>&1 | head -1)
        success "$name: $ver"
        return 0
    else
        fail "$name: not found"
        return 1
    fi
}

# ─── Environment variables ──────────────────────────────────────────

export DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Lowercase aliases used by zsh.sh symlink commands
export home="$HOME"
export dotfiles="$DOTFILES"

# ─── Xcode CLI tools ───────────────────────────────────────────────

setup_xcode_cli() {
    if xcode-select -p &>/dev/null; then
        success "Xcode CLI tools already installed"
    else
        info "Installing Xcode CLI tools..."
        xcode-select --install
        warn "Xcode CLI tools installing — re-run this script after installation completes"
        exit 1
    fi
}

# ─── Homebrew ───────────────────────────────────────────────────────

setup_homebrew() {
    if ! cmd_exists brew; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        success "Homebrew already installed"
    fi

    # Ensure brew is on PATH for the rest of the script
    if ! cmd_exists brew; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    if ! cmd_exists brew; then
        fail "Homebrew not found after install — re-run this script"
        exit 1
    fi

    info "Updating Homebrew..."
    brew update
}
