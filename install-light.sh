#!/bin/bash

# install-light.sh — Lightweight installer for secondary Mac
# Usage: ./install-light.sh           # install/update everything
#        ./install-light.sh --check   # verify tool status only
#        ./install-light.sh --status  # alias for --check

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setupfiles/common.sh"

# ─── Check mode ─────────────────────────────────────────────────────

run_check() {
    echo ""
    echo "=============================="
    echo "  Tool Status Check"
    echo "=============================="
    echo ""

    local missing=0

    # --- Core tools ---
    info "Core tools:"
    check_tool "Homebrew" "brew" || ((missing++))
    check_tool "git" "git" || ((missing++))
    check_tool "gh" "gh" || ((missing++))
    check_tool "wget" "wget" || ((missing++))
    check_tool "jq" "jq" || ((missing++))
    check_tool "fd" "fd" || ((missing++))
    if cmd_exists trash; then
        success "trash: installed"
    else
        fail "trash: not found"; ((missing++))
    fi
    check_tool "tmux" "tmux" || ((missing++))
    check_tool "delta" "delta" || ((missing++))
    check_tool "lazygit" "lazygit" || ((missing++))
    check_tool "watchman" "watchman" || ((missing++))
    check_tool "pnpm" "pnpm" || ((missing++))

    # eza uses different version flag
    if cmd_exists eza; then
        success "eza: $(eza --version 2>&1 | head -1)"
    else
        fail "eza: not found"; ((missing++))
    fi

    echo ""
    info "Shell:"
    check_tool "zsh" "zsh" || ((missing++))

    # oh-my-zsh
    if [ -d "$HOME/.oh-my-zsh" ]; then
        success "oh-my-zsh: installed"
    else
        fail "oh-my-zsh: not found"; ((missing++))
    fi

    # Powerlevel10k
    if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
        success "Powerlevel10k: installed"
    else
        fail "Powerlevel10k: not found"; ((missing++))
    fi

    echo ""
    info "Node/JS:"
    # NVM
    if [ -d "$HOME/.nvm" ] || [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-nvm" ]; then
        success "NVM: installed"
    else
        fail "NVM: not found"; ((missing++))
    fi

    if cmd_exists node; then
        success "Node: $(node --version 2>&1)"
    else
        fail "Node: not found"; ((missing++))
    fi

    echo ""
    info "Python:"
    check_tool "pyenv" "pyenv" || ((missing++))

    if cmd_exists python; then
        success "Python: $(python --version 2>&1)"
    else
        fail "Python: not found"; ((missing++))
    fi

    if cmd_exists pip; then
        success "pip: $(pip --version 2>&1 | head -1)"
    else
        fail "pip: not found"; ((missing++))
    fi

    echo ""
    info "Symlinks:"
    if [ -L "$HOME/.zshrc" ]; then
        success ".zshrc: symlinked → $(readlink "$HOME/.zshrc")"
    else
        fail ".zshrc: not symlinked"; ((missing++))
    fi

    if [ -L "$HOME/.p10k.zsh" ]; then
        success ".p10k.zsh: symlinked → $(readlink "$HOME/.p10k.zsh")"
    else
        fail ".p10k.zsh: not symlinked"; ((missing++))
    fi

    echo ""
    info "Cask apps:"
    for app in "iTerm" "Cursor" "Flycut"; do
        if [ -d "/Applications/${app}.app" ]; then
            success "$app: installed"
        else
            fail "$app: not found"; ((missing++))
        fi
    done

    echo ""
    echo "=============================="
    if [ "$missing" -eq 0 ]; then
        success "All tools OK!"
    else
        warn "$missing tool(s) missing or not found"
    fi
    echo ""

    return "$missing"
}

# ─── Handle --check / --status ──────────────────────────────────────

if [[ "$1" == "--check" || "$1" == "--status" ]]; then
    run_check
    exit $?
fi

# ─── Install mode ───────────────────────────────────────────────────

echo ""
echo "=============================="
echo "  Lightweight Mac Setup"
echo "=============================="
echo ""

# 1. Xcode CLI tools + Homebrew
setup_xcode_cli
setup_homebrew

# 2. Brew bundle with lightweight Brewfile
info "Installing Homebrew packages (Brewfile.light)..."
brew bundle --file="$SCRIPT_DIR/Brewfile.light"
success "Homebrew packages installed"

# 3. Zsh setup (oh-my-zsh, Powerlevel10k, symlinks)
info "Setting up Zsh..."
chmod a+x "$SCRIPT_DIR/setupfiles/zsh.sh"
source "$SCRIPT_DIR/setupfiles/zsh.sh"
success "Zsh setup complete"

# 4. Node setup (zsh-nvm plugin, Node LTS)
info "Setting up Node..."
chmod a+x "$SCRIPT_DIR/setupfiles/node.sh"
source "$SCRIPT_DIR/setupfiles/node.sh"
success "Node setup complete"

# 5. Python setup (pyenv, Python 3.12, pip packages)
info "Setting up Python..."
chmod a+x "$SCRIPT_DIR/setupfiles/python.sh"
source "$SCRIPT_DIR/setupfiles/python.sh"
success "Python setup complete"

# 6. Final verification
echo ""
info "Running verification..."
run_check

echo ""
success "Lightweight setup complete! Open a new terminal to apply shell changes."
