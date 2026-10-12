#!/usr/bin/env bash

source "$HOME/.config/sketchybar/variables.sh"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

set_color() {
	sketchybar --set "$NAME" icon.color="$1" background.border_color="$1"
}

show_status() {
	if pgrep -x yabai >/dev/null; then
		set_color "$GREEN"
	else
		set_color "$RED"
	fi
}

if [ "$SENDER" = "mouse.clicked" ]; then
	set_color "$YELLOW"
	if pgrep -x yabai >/dev/null; then
		yabai --restart-service
	else
		yabai --start-service
	fi
	# Give launchd a moment to bring the process back before re-checking.
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		sleep 0.5
		pgrep -x yabai >/dev/null && break
	done
fi

show_status
