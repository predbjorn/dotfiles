#!/usr/bin/env bash

# Tren mark; click opens the beta quality page in the local ops console (Mac mini).
sketchybar --add item tren right \
	--set tren \
	icon.drawing=off \
	label.drawing=off \
	background.image="$HOME/.config/sketchybar/images/tren.png" \
	background.image.scale=0.5 \
	background.image.padding_left=12 \
	background.image.padding_right=12 \
	width=44 \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$COMMENT" \
	background.color="$ITEM_BG_COLOR" \
	background.drawing=on \
	click_script="open 'http://127.0.0.1:8090/beta'"
