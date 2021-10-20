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





# Make ZSH the default shell environment
if grep -q "zsh" /etc/shells
then 
    echo "ZSH shell already in allowed shells"
else 
    chsh -s $(which zsh)
    rm -rf $HOME/.zshrc
    ln -s $HOME/.dotfiles/.zshrc $HOME/.zshrc
fi

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

# Install global NPM packages
npm install --global 
yarn 
npx 
typescript 
create-react-app 
react-native-cli 
react-native-rename
react-native-git-upgrade
@sanity/cli
firebase-tools
logcat-viewer


gem install cocoapods

# Removes .zshrc from $HOME (if it exists) and symlinks the .zshrc file from the .dotfiles

# Symlink the Mackup config file to the home directory
# ln -s $HOME/.dotfiles/.mackup.cfg $HOME/.mackup.cfg

# Set macOS preferences
# We will run this last because this will reload the shell
# source .macos