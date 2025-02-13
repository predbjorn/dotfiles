#!/bin/bash

# Set up cronjobs
if command -v python &> /dev/null
then
	chmod a+x $DOTFILES/script/setCronjobs.py
	python $DOTFILES/script/setCronjobs.py
	
	chmod a+x $DOTFILES/githubProjects/setupGitRepos.py;
	python $DOTFILES/githubProjects/setupGitRepos.py;
else
	echo "python is not installed."
fi