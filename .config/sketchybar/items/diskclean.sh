#!/usr/bin/env bash

COLOR="$CYAN"

# Left-click opens DiskCleaner.app (overview, live cleanup progress, simulator
# and emulator manager). Right-click runs the sweep silently in the background.
sketchybar --add item diskclean right \
	--set diskclean \
	icon="󰃢" \
	icon.color="$COLOR" \
	icon.padding_left=10 \
	icon.padding_right=10 \
	label.drawing=off \
	label.color="$COLOR" \
	label.padding_right=10 \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COLOR" \
	background.color="$ITEM_BG_COLOR" \
	background.drawing=on \
	click_script="\"$PLUGIN_DIR/diskclean.sh\" click"
