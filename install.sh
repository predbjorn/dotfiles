#!/bin/bash

echo "Setting up your Mac..."

echo "Setup brew"
# Check for Homebrew and install if we don't have it
if  ! command -v brew &> /dev/null; then
  	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/predbjorn/.zprofile
	eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if  ! command -v xcode-select &> /dev/null; then
	xcode-select –-install
fi

chmod a+x setupfiles/zsh.sh;
source setupfiles/zsh.sh;

if  ! command -v brew &> /dev/null; then
	echo "Homebrew not found, run again"
	exit 1
fi

# Update Homebrew recipes
brew update

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
