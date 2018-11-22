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


gem install cocoapods

# Removes .zshrc from $HOME (if it exists) and symlinks the .zshrc file from the .dotfiles

# Symlink the Mackup config file to the home directory
# ln -s $HOME/.dotfiles/.mackup.cfg $HOME/.mackup.cfg

# Set macOS preferences
# We will run this last because this will reload the shell
# source .macos