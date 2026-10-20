#!/usr/bin/env bash

COLOR="$CYAN"

# Click runs the cleanup in the background so the bar never blocks
# (the sweep over ~/Hacking takes minutes). Right-click previews instead.
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
	click_script="nohup \"$PLUGIN_DIR/diskclean.sh\" run >/dev/null 2>&1 &"
