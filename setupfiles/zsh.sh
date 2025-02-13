#!/bin/bash

# SETUP ZSH SHELL:
# In brew file:
# brew "zsh"
# brew "zsh-completions"
# https://github.com/ohmyzsh/ohmyzsh/wiki

# Make ZSH the default shell environment
if grep -q "zsh" /etc/shells; then 
    echo "ZSH shell already in allowed shells"
else 
    chsh -s $(which zsh)
fi

brew install zsh 


if [ -d ~/.oh-my-zsh ]; then
	echo "oh-my-zsh is installed"
 else
 	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

if [ -d ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k ]; then
	echo "powerlevel10k already installed"
 else
	echo "Installing powerlevel10k"
 	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
fi
if [ -d ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions ]; then
	echo "zsh-completions already installed"
 else
	echo "Installing zsh-completions"
	git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions
fi

if [ -d ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting ]; then
	echo "zsh-syntax-highlighting already installed"
 else
	echo "Installing zsh-syntax-highlighting"
	git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
fi

if [ -d ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions ]; then
	echo "zsh-autosuggestions already installed"
 else
	echo "Installing zsh-autosuggestions"
	git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
fi

## Sync and symlink files:
# pk10 config
rm -rf $home/.p10k.zsh
ln -s $dotfiles/.config/.p10k.zsh $home/.p10k.zsh
# zshrc
rm -rf $home/.zshrc
ln -s $dotfiles/.config/.zshrc $home/.zshrc
# GEMS
rm -rf $home/.gemrc
ln -s $dotfiles/.config/.gemrc $home/.gemrc

