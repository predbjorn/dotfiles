#!/bin/bash

# Define the base directories
base_dir=~/Hacking
dest_dir=~/Hacking/variables
local_dir=~/githubProject_local

# Create the destination directory if it doesn't exist
mkdir -p "$dest_dir"

# Read the list of projects from the file
while read -r line; do
	# Extract the project name and folder
	project=$(echo "$line" | awk '{print $1}')
	folder=$(echo "$line" | awk '{print $2}')
	
	# Define the full path to the project folder
	project_dir="$base_dir/$folder"
	
	# Check if the project exists in the local directory
	if [ -d "$local_dir/$project" ]; then
		project_dir="$local_dir/$project"
	fi
	
	# Find all .env files in the project directory
	find "$project_dir" -type f -name "*.env*" | while read -r env_file; do
		# Define the destination path for the .env file
		relative_path="${env_file#$project_dir/}"
		dest_path="$dest_dir/$project/$relative_path"
		
		# Create the destination directory if it doesn't exist
		mkdir -p "$(dirname "$dest_path")"
		# Print the name and path of the .env file found
		echo "Found .env file: $env_file"
		# Copy the .env file to the destination
		cp "$env_file" "$dest_path"
	done
done < ./githubProject