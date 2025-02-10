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
ln -s $HOME/.dotfiles/.config/.p10k.zsh $HOME/.p10k.zsh
# zshrc
rm -rf $HOME/.zshrc
ln -s $HOME/.dotfiles/.config/.zshrc $HOME/.zshrc
# GEMS
rm -rf $HOME/.gemrc
ln -s $HOME/.dotfiles/.config/.gemrc $HOME/.gemrc


chmod a+x setupfiles/pip.sh;
source setupfiles/npm.sh;

chmod a+x setupfiles/npm.sh;
source setupfiles/npm.sh;
s
chmod a+x setupfiles/hackingfolder.sh;
source setupfiles/hackingfolder.sh;

chmod a+x setupfiles/init_script.sh;
source setupfiles/init_script.sh;

chmod a+x setupfiles/sync.sh;
source setupfiles/sync.sh;

# Set macOS preferences
# We will run this last because this will reload the shell
mkdir -p $HOME/screenshots
chmod a+x setupfiles/macos.sh;
source setupfiles/macos.sh;
