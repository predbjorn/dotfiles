#!/bin/sh

echo "Setting up your Mac..."

echo "Setup brew"
# Check for Homebrew and install if we don't have it
if test ! $(which brew); then
  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

xcode-select –-install

# Update Homebrew recipes
brew update

echo "Install all brew dependencies"
# Install all our dependencies with bundle (See Brewfile)
brew tap homebrew/bundle
brew bundle
echo "Brew dependencies installed"

chmod a+x setupfiles/zsh.sh;
source setupfiles/zsh.sh;

chmod a+x setupfiles/node.sh;
source setupfiles/node.sh;

chmod a+x setupfiles/python.sh;
source setupfiles/python.sh;

chmod a+x setupfiles/ruby.sh;
source setupfiles/ruby.sh;

chmod a+x setupfiles/npm.sh;
source setupfiles/npm.sh;
s
chmod a+x setupfiles/hackingfolder.sh;
source setupfiles/hackingfolder.sh;

chmod a+x setupfiles/sync.sh;
source setupfiles/sync.sh;

chmod a+x setupfiles/init_script.sh;
source setupfiles/init_script.sh;

# Set up cronjobs
if command -v python &> /dev/null
then
	chmod a+x githubProjects/setupGitRepos.py;
	python githubProjects/setupGitRepos.py;
else
	echo "python is not installed."
fi

# Set macOS preferences
# We will run this last because this will reload the shell
mkdir -p $HOME/screenshots # folder for all screenshots, obvoiusly!
chmod a+x setupfiles/macos.sh;
source setupfiles/macos.sh;
