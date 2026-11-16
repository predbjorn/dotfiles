#!/usr/bin/env bash

COLOR="$ORANGE"

sketchybar --add event simq_changed \
	--add item simq right \
	--set simq \
	update_freq=60 \
	updates=on \
	drawing=off \
	icon="󰀦" \
	icon.color="$COLOR" \
	icon.padding_left=10 \
	label.color="$COLOR" \
	label.padding_right=10 \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COLOR" \
	background.color="$ITEM_BG_COLOR" \
	background.drawing=on \
	script="$PLUGIN_DIR/simq.sh" \
	click_script="open diskcleaner://simq" \
	--subscribe simq simq_changed
