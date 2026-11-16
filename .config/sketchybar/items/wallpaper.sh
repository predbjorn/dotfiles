#!/usr/bin/env bash

# Wallpaper switcher: click for a menu to pick today's set or weather (script/wallpaper.py).
sketchybar --add item wallpaper right \
	--set wallpaper \
	icon="󰋵" \
	icon.color="$CYAN" \
	icon.padding_left=10 \
	icon.padding_right=10 \
	label.drawing=off \
	background.height=26 \
	background.corner_radius="$CORNER_RADIUS" \
	background.padding_right=5 \
	background.border_width="$BORDER_WIDTH" \
	background.border_color="$CYAN" \
	background.color="$ITEM_BG_COLOR" \
	background.drawing=on \
	popup.height=24 \
	popup.drawing=off \
	script="$PLUGIN_DIR/wallpaper.sh" \
	click_script="$PLUGIN_DIR/wallpaper.sh toggle" \
	--subscribe wallpaper mouse.exited.global
