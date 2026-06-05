#!/usr/bin/env bash

source "$HOME/.config/sketchybar/variables.sh"

ICON_OK=""        # check-circle
ICON_DOWN=""      # exclamation-triangle
ICON_UNKNOWN=""   # question-circle
DOT=""            # circle

CONFIG="$HOME/Library/Application Support/LaunchDashboard/config.json"

# Tear down popup rows from the previous tick so we can rebuild cleanly.
clear_popup_rows() {
	local rows
	rows=$(sketchybar --query launchdash 2>/dev/null | jq -r '.popup.items[]?' 2>/dev/null)
	for row in $rows; do
		sketchybar --remove "$row" 2>/dev/null
	done
}

set_offline() {
	clear_popup_rows
	sketchybar --set launchdash \
		icon="$ICON_UNKNOWN" icon.color="$COMMENT" \
		label="" background.border_color="$COMMENT"
	sketchybar --add item launchdash.row.0 popup.launchdash \
		--set launchdash.row.0 icon="$DOT" icon.color="$COMMENT" \
		label="dashboard offline" 2>/dev/null
}

# 1. Resolve the token; bail to offline if config is missing/unreadable.
TOKEN=$(jq -r '.bearerToken // empty' "$CONFIG" 2>/dev/null)
if [ -z "$TOKEN" ]; then
	set_offline
	exit 0
fi

# 2. Fetch the summary; bail to offline on curl failure / empty / non-JSON.
JSON=$(curl -sS --max-time 2 -H "Authorization: Bearer $TOKEN" \
	http://127.0.0.1:8765/summary 2>/dev/null)
if [ -z "$JSON" ] || ! echo "$JSON" | jq empty >/dev/null 2>&1; then
	set_offline
	exit 0
fi

# 3. Recolor the glyph from priorityDown.
DOWN=$(echo "$JSON" | jq -r '.priorityDown // 0')
if [ "$DOWN" -gt 0 ] 2>/dev/null; then
	sketchybar --set launchdash \
		icon="$ICON_DOWN" icon.color="$RED" \
		label="$DOWN" background.border_color="$RED"
else
	sketchybar --set launchdash \
		icon="$ICON_OK" icon.color="$GREEN" \
		label="" background.border_color="$GREEN"
fi

# 4. Rebuild popup rows, one per priority service.
clear_popup_rows
i=0
while IFS=$'\t' read -r label state up; do
	[ -z "$label" ] && continue
	if [ "$up" = "true" ]; then dot_color="$GREEN"; else dot_color="$RED"; fi
	sketchybar --add item "launchdash.row.$i" popup.launchdash \
		--set "launchdash.row.$i" \
		icon="$DOT" icon.color="$dot_color" \
		label="$label  $state" 2>/dev/null
	i=$((i + 1))
done < <(echo "$JSON" | jq -r '.priority[] | [.label, .state, (.up|tostring)] | @tsv')
