#!/bin/bash

if command -v python &> /dev/null
then
	chmod a+x $DOTFILES/githubProjects/setupGitRepos.py;
	python $DOTFILES/githubProjects/setupGitRepos.py;
else
	echo "python is not installed."
fi