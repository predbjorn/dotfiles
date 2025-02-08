#!/bin/sh

echo "Setting up your Mac..."

# Check for Homebrew and install if we don't have it
if test ! $(which brew); then
  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# Update Homebrew recipes
brew update

# Install all our dependencies with bundle (See Brewfile)
brew tap homebrew/bundle
brew bundle

mkdir -p $HOME/screenshots
# Install services
# yabai 
mkdir -p $XDG_CONFIG_HOME/yabai
rm -rf $XDG_CONFIG_HOME/yabai/.yabairc
ln -s $HOME/.dotfiles/config/.yabairc $XDG_CONFIG_HOME/yabai/.yabairc
chmod +x $XDG_CONFIG_HOME/yabai/.yabairc
yabai --start-service

mkdir -p $XDG_CONFIG_HOME/skhd
rm -rf $XDG_CONFIG_HOME/skhd/.skhdrc
ln -s $HOME/.dotfiles/config/.skhdrc $XDG_CONFIG_HOME/skhd/.skhdrc
chmod +x $XDG_CONFIG_HOME/skhd/.skhdrc
skhd --start-service


# Make ZSH the default shell environment
if grep -q "zsh" /etc/shells; then 
    echo "ZSH shell already in allowed shells"
else 
    chsh -s $(which zsh)
fi

if [ -d ~/.oh-my-zsh ]; then
	echo "oh-my-zsh is installed"
 else
 	sh -c
	  "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

if [ -d ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k ]; then
	echo "powerlevel10k is installed"
 else
 	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
fi
if [ -d ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions ]; then
	echo "zsh-completions is installed"
 else
 	  git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions
fi

## Sync and symlink files:
# pk10 config
rm -rf $HOME/.p10k.zsh
ln -s $HOME/.dotfiles/.p10k.zsh $HOME/.p10k.zsh
# zshrc
rm -rf $HOME/.zshrc
ln -s $HOME/.dotfiles/.zshrc $HOME/.zshrc
# GEMS
rm -rf $HOME/.gemrc
ln -s $HOME/.dotfiles/.gemrc $HOME/.gemrc

# # # list all available versions:
# rbenv install -l
# # install a Ruby version:
# rbenv install 2.4.1
# set ruby version for a specific dir
# rbenv local 2.4.1
# # set ruby version globally
# rbenv global 2.4.1
# # rbenv rehash
# gem update --system


chmod a+x pip.sh;
source npm.sh;

chmod a+x npm.sh;
source npm.sh;

chmod a+x hackingfolder.sh;
source hackingfolder.sh;

# Symlink the Mackup config file to the home directory
# ln -s $HOME/.dotfiles/.mackup.cfg $HOME/.mackup.cfg

# Set macOS preferences
# We will run this last because this will reload the shell
# source .macos
chmod a+x macos.sh;
source macos.sh;

# Setup cronjobs
if command -v python3.11 &> /dev/null
then
	chmod a+x setCronjobs.py
	python3.11 ./setCronjobs.py
else
	echo "python3.11 is not installed."
fi