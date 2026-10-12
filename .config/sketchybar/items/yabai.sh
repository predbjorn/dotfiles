#!/usr/bin/env bash

# Yabai status pill. Green = running, red = stopped. Click restarts (or starts) the service.
sketchybar --add item yabai right \
	--set yabai \
	update_freq=30 \
	updates=on \
	icon="󰕰" \
	icon.color="$COMMENT" \
	icon.padding_left=10 \
	icon.padding_right=10 \
	label.drawing=off \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COMMENT" \
	background.color="$ITEM_BG_COLOR" \
	background.drawing=on \
	script="$PLUGIN_DIR/yabai.sh" \
	--subscribe yabai mouse.clicked
