#!/bin/bash

# Ensure GitHub CLI is installed
if ! command -v gh &> /dev/null
then
	echo "GitHub CLI (gh) could not be found. Please install it first."
	exit 1
fi

# Fetch and list all repositories
gh repo list --limit 100