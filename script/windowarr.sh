#!/bin/sh

ensure_space_exists() {
	local space="$1"
	
	if ! yabai -m query --spaces | jq -e --arg space "$space" '.[] | select(.index == ($space | tonumber))' > /dev/null; then
		yabai -m space --create
	fi
}

move_all_windows_from_space() {
	local space="$1"
	local target_space="$2"
	ensure_space_exists "$target_space"
	yabai -m query --windows --space "$space" | jq -r '.[] | .id' | while read -r id; do
		yabai -m window "$id" --space "$target_space"
	done
}

add_rule_for_app() {
	local app="$1"
	local space="$2"
	yabai -m rule --add app="^$app$" display=^$space
}

move_app_to_space() {
	local app="$1"
	local space="$2"
	local move_all="$3"
	
	ensure_space_exists "$space"
	if [ "$move_all" = "true" ]; then
		yabai -m query --windows | jq -r --arg app "$app" '.[] | select(.app == $app) | .id' | while read -r id; do
			yabai -m window "$id" --space "$space"
		done
	else
		yabai -m query --windows | jq -r --arg app "$app" '.[] | select(.app == $app) | .id' | head -n 1 | while read -r id; do
			yabai -m window "$id" --space "$space"
		done
	fi
	
	yabai -m space --focus "$space"
}

# Example usage:
move_all_windows_from_space 1 4
move_all_windows_from_space 2 5
move_all_windows_from_space 3 5
move_all_windows_from_space 4 5
move_all_windows_from_space 6 5
move_app_to_space Safari 1 true
add_rule_for_app Safari 1
move_app_to_space Code 2 false
move_app_to_space iTerm2 3 true
move_app_to_space Slack 4 true
move_app_to_space Mail 4 true
move_app_to_space Spotify 6 true