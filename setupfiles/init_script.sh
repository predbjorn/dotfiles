#!/bin/bash

# Set up cronjobs
if command -v python &> /dev/null
then
	chmod a+x $DOTFILES/script/setCronjobs.py
	python $DOTFILES/script/setCronjobs.py
else
	echo "python is not installed."
fi