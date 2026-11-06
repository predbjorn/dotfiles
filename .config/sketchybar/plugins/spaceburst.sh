#!/usr/bin/env bash

# Click on the storage item: rescan the disk with spaceburst and open the
# sunburst map. The scan takes ~2 minutes, so it runs in the background and
# the storage label shows progress until the map opens.

source "$HOME/.config/sketchybar/variables.sh"

SPACEBURST="$HOME/Hacking/projects/spaceburst"
LOCK="/tmp/sketchybar-spaceburst.lock"

set_label() { # label, color
	sketchybar --set storage label="$1" label.color="$2" icon.color="$2" \
		background.border_color="$2"
}

restore() {
	sketchybar --set storage label.color="$BLUE" icon.color="$BLUE" \
		background.border_color="$BLUE" \
		label="$(df -H / | tail -1 | awk '{print $4}')"
}

# Ignore repeat clicks while a scan is already in flight.
if ! mkdir "$LOCK" 2>/dev/null; then
	exit 0
fi
trap 'rm -rf "$LOCK"' EXIT

if [ ! -f "$SPACEBURST/scan.py" ]; then
	set_label "no spaceburst" "$RED"
	sleep 6
	restore
	exit 1
fi

set_label "scanning…" "$YELLOW"
if /usr/bin/python3 "$SPACEBURST/scan.py" >/tmp/spaceburst.log 2>&1; then
	open "$SPACEBURST/diskmap.html"
	restore
else
	set_label "scan failed" "$RED"
	sleep 6
	restore
fi
