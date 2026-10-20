#!/usr/bin/env bash

source "$HOME/.config/sketchybar/variables.sh"

ENGINE="$HOME/.dotfiles/bin/disk-cleanup.sh"
LOCK="/tmp/sketchybar-diskclean.lock"

ICON_IDLE="󰃢" # broom
ICON_BUSY="󰔛" # timer
ICON_DONE="" # check
ICON_FAIL="" # warning

set_state() { # icon, color, label(optional)
	if [ -n "${3:-}" ]; then
		sketchybar --set diskclean icon="$1" icon.color="$2" \
			background.border_color="$2" label="$3" label.color="$2" label.drawing=on
	else
		sketchybar --set diskclean icon="$1" icon.color="$2" \
			background.border_color="$2" label.drawing=off
	fi
}

idle() { set_state "$ICON_IDLE" "$CYAN"; }

run() {
	# Ignore repeat clicks while a sweep is already in flight.
	if ! mkdir "$LOCK" 2>/dev/null; then
		set_state "$ICON_BUSY" "$YELLOW" "already running"
		sleep 3
		set_state "$ICON_BUSY" "$YELLOW" "cleaning…"
		return 0
	fi
	trap 'rm -rf "$LOCK"' EXIT

	if [ ! -x "$ENGINE" ]; then
		set_state "$ICON_FAIL" "$RED" "no script"
		sleep 6
		idle
		return 1
	fi

	set_state "$ICON_BUSY" "$YELLOW" "cleaning…"

	local out freed
	out=$("$ENGINE" 2>/dev/null | tail -1)
	freed=$(printf '%s' "$out" | sed -n 's/.*freed \(-\{0,1\}[0-9]\{1,\}\) GB.*/\1/p')

	if [ -z "$freed" ]; then
		set_state "$ICON_FAIL" "$RED" "failed"
	else
		set_state "$ICON_DONE" "$GREEN" "+${freed} GB"
	fi
	sleep 10
	idle
}

case "${1:-}" in
run) run ;;
*) idle ;;
esac
