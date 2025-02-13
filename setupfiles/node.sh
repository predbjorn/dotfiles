#!/bin/bash

# NVM as a zsh plugin
# https://github.com/lukechilds/zsh-nvm
if [ -d ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-nvm ]; then
	echo "zsh-nvm is installed"
 else
	git clone https://github.com/lukechilds/zsh-nvm ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-nvm
fi

nvm upgrade
nvm install node

# nvm 
# https://github.com/nvm-sh/nvm

# view available versions
# $ nvm ls-remote
# Other commands:
# $ nvm use 16
# Now using node v16.9.1 (npm v7.21.1)
# $ node -v 
# v16.9.1
# $ nvm install 12
# Now using node v12.22.6 (npm v6.14.5)
# $ node -v
# v12.22.6