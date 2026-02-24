#!/bin/zsh
focus_window () {
	local app="$1"
	local force_move="$2"
	window_id="$(yabai -m query --windows --display | jq -r "map(select(.app==\"$app\"))[0].id")"
	if [ "$window_id" = "null" ]; then
		window_id="$(yabai -m query --windows | jq -r "map(select(.app==\"$app\"))[0].id")"
		if [ "$window_id" = "null" ]; then
			echo "No window found for app $app"
			open -a "$app"
		fi
		display_id="$(yabai -m query --windows | jq -r "map(select(.id==$window_id))[0].display")" 
		if [ "$force_move" = "true" ]; then
			yabai -m window $window_id --space $(yabai -m query --spaces --space | jq -r '.index') --display $(yabai -m query --displays --display | jq -r '.index')
		else 
			echo "No window found for app $app on this display, moving to display $display_id"
			yabai -m display --focus "$display_id" 
		fi
		yabai -m window --focus "$window_id"
	else 
		if [ "$force_move" = "true" ]; then
			echo "Moving app $app to the current space: $(yabai -m query --spaces --space | jq -r '.index')"
			yabai -m window $window_id --space $(yabai -m query --spaces --space | jq -r '.index') --display $(yabai -m query --displays --display | jq -r '.index')
		else
			yabai -m window --focus "$window_id"
		fi 
	fi
}

echo "Focus window wrapper"
echo "App: $1"
echo "Force move: $2"
focus_window "$1" "$2"


