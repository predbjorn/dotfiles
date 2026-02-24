#!/bin/bash

## Python with pyenv for version management
## $ brew install openssl readline sqlite3 xz zlib
## $ brew install pyenv
## SETUP in PATH:
## export PYENV_ROOT="$HOME/.pyenv"
## export PATH="$PYENV_ROOT/bin:$PATH"
## eval "$(pyenv init --path)"


if ! command -v pyenv &> /dev/null; then
	echo "penv not found, installing..."
	brew install openssl readline sqlite3 xz zlib tcl-tk@8
	brew install pyenv
else
	echo "pyenv is already installed"
fi

brew install openssl readline sqlite3 xz zlib tcl-tk@8
brew upgrade pyenv

## list available versions: 
## $ pyenv install -l
## list your versions: 
## $ pyenv versions
## All of the versions are installed in ~/.pyenv/versions


## echo "updating to latest python version"
if ! command -v python &> /dev/null; then
	echo "Python not found, installing..."
	pyenv install 3.12.9
	pyenv global 3.12.9
else
	echo "Python is already installed"
fi

# Install pip if not installed
if ! command -v pip &> /dev/null; then
	echo "pip not found, installing..."
	curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
	python get-pip.py
	rm get-pip.py
else
	echo "pip is already installed:"
	pyenv which pip
fi

pip install --upgrade pip

echo "Insatalling python packages (with pip)"
## Install Python packages
pip install datetime openai requests python-dotenv google-genai

# brew "python@3.11"
# brew "python"