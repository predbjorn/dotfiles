#!/usr/bin/env bash

VOLUME=$(osascript -e "output volume of (get volume settings)")

# External soundcards/interfaces expose no software volume control (osascript
# returns "missing value") — hide the widget entirely while one is active.
if ! [[ "$VOLUME" =~ ^[0-9]+$ ]]; then
	sketchybar --set "$NAME" drawing=off
	exit 0
fi

sketchybar --set "$NAME" drawing=on

MUTED=$(osascript -e "output muted of (get volume settings)")

if [ "$MUTED" != "false" ]; then
	ICON="󰖁"
	VOLUME=0
else
	case ${VOLUME} in
	100) ICON="" ;;
	[5-9]*) ICON="" ;;
	[0-9]*) ICON="" ;;
	*) ICON="" ;;
	esac
fi

sketchybar -m \
	--set "$NAME" icon=$ICON \
	--set "$NAME" label="$VOLUME%"
