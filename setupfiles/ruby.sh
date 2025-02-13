#!/bin/bash

# Install rbnv if not installed
if ! command -v rbenv &> /dev/null; then
	echo "rbnv not found, installing..."
	brew install rbenv
	rbenv init
else
	echo "rbnv is already installed"
fi

##########################
# THIS IS SET UP IN PATH #
##########################
# export GEM_HOME="$HOME/.gem"
# export PATH="$GEM_HOME/bin:$PATH"
# export PATH="$HOME/.rbenv/bin:$PATH"
# eval "$(rbenv init -)"


##########################
##  DOCS AND COMMANDS   ##
##########################
# Lists all Ruby versions known to rbenv
# $ rbenv versions

# Lists all Ruby versions known to rbenv
# $ rbenv versions

# # list latest stable versions:
# $ rbenv install -l

# # list all local versions:
# $ rbenv install -L

# # install a Ruby version:
# $ rbenv install 3.1.2

# $ gem env home
# # => ~/.rbenv/versions/<version>/lib/ruby/gems/...

# set local version
# $ rbenv local 3.1.2

# set global version
# $ rbenv global 3.1.2

# Displays the full path to the executable that rbenv
# $ rbenv which irb


