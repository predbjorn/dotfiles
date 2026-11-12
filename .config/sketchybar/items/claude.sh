#!/usr/bin/env bash
# Two pills that open/focus the main and Personal Claude desktop instances.

add_claude() {
	local name="$1" label="$2" color="$3"
	sketchybar --add item "$name" left \
		--set "$name" \
		icon="󰚩" \
		icon.color="$color" \
		icon.padding_left=10 \
		label="$label" \
		label.color="$color" \
		label.padding_right=10 \
		background.height=26 \
		background.corner_radius="$CORNER_RADIUS" \
		background.padding_left=5 \
		background.border_width="$BORDER_WIDTH" \
		background.border_color="$color" \
		background.color="$ITEM_BG_COLOR" \
		background.drawing=on \
		click_script="$PLUGIN_DIR/claude_open.sh ${name#claude_}"
}

add_claude claude_main "Claude" "$ORANGE"
add_claude claude_personal "Personal" "$GREEN"
