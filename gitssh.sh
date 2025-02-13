#!/bin/bash

# Generate a new SSH key
ssh-keygen -t ed25519 -C "prebenhafnor@gmail.com"

# Start the ssh-agent in the background
eval "$(ssh-agent -s)"

# Ensure the .ssh directory exists
mkdir -p ~/.ssh

# Create or open the SSH config file
touch ~/.ssh/config

# Write configuration to the SSH config file
cat <<EOL >> ~/.ssh/config
Host *
	AddKeysToAgent yes
	UseKeychain yes
	IdentityFile ~/.ssh/id_ed25519
EOL

# Add the SSH key to the ssh-agent
ssh-add -K ~/.ssh/id_ed25519

# Add the SSH key to the Apple keychain
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Copy the SSH public key to the clipboard
pbcopy < ~/.ssh/id_ed25519.pub

echo "SSH key generated and added to the ssh-agent. The public key has been copied to your clipboard."