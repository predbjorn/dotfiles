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

# Setup cloudflared tunnel config
mkdir -p $HOME/.cloudflared
ln -sf $HOME/.dotfiles/.config/cloudflared/config.yml $HOME/.cloudflared/config.yml

chmod a+x setupfiles/init_script.sh;
source setupfiles/init_script.sh;

# Set macOS preferences
# We will run this last because this will reload the shell
mkdir -p $HOME/screenshots # folder for all screenshots, obvoiusly!
chmod a+x setupfiles/macos.sh;
source setupfiles/macos.sh;
