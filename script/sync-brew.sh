#!/bin/bash

# Create a folder called tempBrew
brewFile="$DOTFILES/Brewfile"
tempBrew="$DOTFILES/script/tempBrew"
mkdir -p $tempBrew

# Change to the tempBrew directory
cd $tempBrew
# Run `brew bundle dump` to generate a Brewfile
brew bundle dump --force

# Go back to the parent directory
cd ../..
# Set the output files for unique lines
unique_installed_file="$tempBrew/uniqueinstalled"
unique_dot_file="$tempBrew/uniquedot"
: > "$unique_installed_file" # Empty the file if it exists
: > "$unique_dot_file" # Empty the file if it exists

# Set the output file for extra applications
extra_apps_file="$tempBrew/extraappsinstalled"
: > "$extra_apps_file" # Empty the file if it exists

# List all applications in /Applications and compare with Brewfile
for app in /Applications/*.app; do
	app_name=$(basename "$app" .app)
	app_name_lower=$(basename "$app" .app | tr '[:upper:]' '[:lower:]')
	app_name_witout_spaces=$(basename "$app" .app | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
	if ! grep "$app_name" "$brewFile" && ! grep "$app_name_lower" "$brewFile" && ! grep "$app_name_witout_spaces" "$brewFile"; then
		echo "$app_name" >> "$extra_apps_file"
	fi
done

# ls -a
ls -a script/tempBrew
# Compare each line from tempBrew/Brewfile to Brewfile
while IFS= read -r line; do
	if ! grep -Fxq "$line" Brewfile; then
		echo "$line" >> "$unique_installed_file"
	fi
done < script/tempBrew/Brewfile

# Compare each line from Brew to tempBrew/Brewfile
# while IFS= read -r line; do
# 	if ! grep -Fxq "$line" script/tempBrew/Brewfile; then
# 		echo "$line" >> "$unique_installed_file"
# 	fi
# done < Brew

# Compare each line from Brewfile to tempBrew/Brewfile
while IFS= read -r line; do
	if [[ ! "$line" =~ ^# ]] && ! grep -Fxq "$line" script/tempBrew/Brewfile; then
		echo "$line" >> "$unique_dot_file"
	fi
done < Brewfile

# Output the result file location
echo "Comparison completed. Unique lines are in $unique_file."

# Clean up: Delete the syncBrew folder
# rm -rf syncBrew

# Notify the user of cleanup
# echo "Temporary folder syncBrew has been deleted."
