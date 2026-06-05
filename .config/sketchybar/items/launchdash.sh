#!/usr/bin/env bash

# Neutral until the first plugin tick recolors it. Click toggles the popup.
sketchybar --add item launchdash right \
	--set launchdash \
	update_freq=5 \
	icon="" \
	icon.color="$COMMENT" \
	icon.padding_left=10 \
	label.color="$LABEL_COLOR" \
	label.padding_right=10 \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COMMENT" \
	background.color="$BAR_COLOR" \
	background.drawing=on \
	popup.height=24 \
	popup.drawing=off \
	script="$PLUGIN_DIR/launchdash.sh" \
	click_script="sketchybar --set launchdash popup.drawing=toggle"
