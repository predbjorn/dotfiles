#!/bin/bash

echo "Setting up your Mac..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setupfiles/common.sh"

setup_xcode_cli
setup_homebrew

chmod a+x setupfiles/zsh.sh;
source setupfiles/zsh.sh;

echo "Install all brew dependencies"
# Install all our dependencies with bundle (See Brewfile)
brew tap homebrew/bundle
brew bundle
echo "Brew dependencies installed"

chmod a+x setupfiles/node.sh;
source setupfiles/node.sh;

chmod a+x setupfiles/python.sh;
source setupfiles/python.sh;

chmod a+x setupfiles/ruby.sh;
source setupfiles/ruby.sh;

chmod a+x setupfiles/npm.sh;
source setupfiles/npm.sh;

chmod a+x setupfiles/sync.sh;
source setupfiles/sync.sh;

# Setup cloudflared tunnel config (single source of truth in dotfiles).
# The always-on launchd job (com.prebenhafnor.cloudflared) and any manual
# `cloudflared tunnel run` both read this config.
mkdir -p $HOME/.cloudflared
ln -sf $HOME/.dotfiles/.config/cloudflared/config.yml $HOME/.cloudflared/config.yml
# Legacy alias kept for older ai-daemon references to ~/.ai-daemon/cloudflared.yml.
mkdir -p $HOME/.ai-daemon
ln -sf $HOME/.dotfiles/.config/cloudflared/config.yml $HOME/.ai-daemon/cloudflared.yml

# Install & (re)load the personal cloudflared launch agent.
# Renders the __HOME__ placeholder to $HOME so the plist is portable across machines.
mkdir -p $HOME/Library/LaunchAgents
CF_PLIST="$HOME/Library/LaunchAgents/com.prebenhafnor.cloudflared.plist"
sed "s#__HOME__#$HOME#g" \
  "$HOME/.dotfiles/.config/cloudflared/com.prebenhafnor.cloudflared.plist" > "$CF_PLIST"
launchctl bootout "gui/$(id -u)/com.prebenhafnor.cloudflared" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$CF_PLIST" 2>/dev/null \
  || launchctl load -w "$CF_PLIST" 2>/dev/null || true

# Setup Claude Code config (settings + status line)
mkdir -p $HOME/.claude
ln -sf $HOME/.dotfiles/.claude/settings.json $HOME/.claude/settings.json
ln -sf $HOME/.dotfiles/.claude/settings.local.json $HOME/.claude/settings.local.json
chmod +x $HOME/.dotfiles/.claude/statusline.sh

chmod a+x setupfiles/init_script.sh;
source setupfiles/init_script.sh;

# Set macOS preferences
# We will run this last because this will reload the shell
mkdir -p $HOME/screenshots # folder for all screenshots, obvoiusly!
chmod a+x setupfiles/macos.sh;
source setupfiles/macos.sh;
