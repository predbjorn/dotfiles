#!/usr/bin/env bash

# Menu for the wallpaper item: today's set, next set, weather, gallery, and every set.
#   wallpaper.sh toggle         open/close the menu (click on the bar item)
#   wallpaper.sh menu|weather   show the main menu or the weather list
#   wallpaper.sh run ARGS...    run wallpaper.py ARGS in the background, then show the menu again

source "$HOME/.config/sketchybar/variables.sh"

ITEM=wallpaper
SELF="$PLUGIN_DIR/wallpaper.sh"
# Same Python and script the launchd job runs (master's checkout).
AGENT="$HOME/Library/LaunchAgents/com.predbjorn.wallpaper.plist"
PYTHON=$(plutil -extract ProgramArguments.0 raw "$AGENT" 2>/dev/null || echo python3)
SCRIPT=$(plutil -extract ProgramArguments.1 raw "$AGENT" 2>/dev/null || echo "$HOME/.dotfiles/script/wallpaper.py")

ICON_SET="󰋵"
ICON_NEXT="󰒭"
ICON_AUTO="󰁪"
ICON_GALLERY="󱢈"
ICON_BACK="󰁍"
ICON_ON="󰄬"
ICON_OFF=" "

weather_icon() {
	case "$1" in
	auto) echo "󰖕" ;;
	clear) echo "󰖙" ;;
	overcast) echo "󰖐" ;;
	fog) echo "󰖑" ;;
	rain) echo "󰖗" ;;
	sleet) echo "󰙿" ;;
	snow) echo "󰖘" ;;
	windy) echo "󰖝" ;;
	thunder) echo "󰖓" ;;
	storm) echo "󰙾" ;;
	blizzard) echo "󰼶" ;;
	aurora) echo "󰖔" ;;
	*) echo "$ICON_SET" ;;
	esac
}

clear_rows() {
	local rows
	rows=$(sketchybar --query "$ITEM" 2>/dev/null | jq -r '.popup.items[]?' 2>/dev/null)
	[ -n "$rows" ] && sketchybar $(printf -- '--remove %s ' $rows) 2>/dev/null
}

# row NAME ICON ICON_COLOR LABEL LABEL_COLOR [CLICK]
row() {
	local args=(--add item "$ITEM.$1" popup."$ITEM" --set "$ITEM.$1"
		icon="$2" icon.color="$3" icon.padding_left=10 icon.width=26
		label="$4" label.color="$5" label.padding_right=14)
	[ -n "$6" ] && args+=(click_script="$6")
	ROWS+=("${args[@]}")
}

status() {
	STATUS=$("$PYTHON" "$SCRIPT" --status 2>/dev/null)
	[ -n "$STATUS" ] && echo "$STATUS" | jq empty 2>/dev/null
}

main_menu() {
	ROWS=()
	if ! status; then
		row err "$ICON_SET" "$RED" "wallpaper.py failed" "$LABEL_COLOR"
	else
		local label weather pinned real
		label=$(jq -r '.label // "no sets"' <<<"$STATUS")
		weather=$(jq -r '.weather' <<<"$STATUS")
		pinned=$(jq -r '.pinned' <<<"$STATUS")
		real=$(jq -r '.real // ""' <<<"$STATUS" | sed 's/_/ /g')
		[ "$weather" = auto ] && weather_label="weather: Oslo${real:+ ($real)}" || weather_label="weather: $weather"
		row now "$ICON_SET" "$CYAN" "$label" "$WHITE"
		row next "$ICON_NEXT" "$WHITE" "next set" "$LABEL_COLOR" "$SELF run --reroll"
		row weather "$(weather_icon "$(jq -r '.weather' <<<"$STATUS")")" "$YELLOW" "$weather_label  ›" "$LABEL_COLOR" "$SELF weather"
		if [ "$pinned" = true ] || [ "$(jq -r '.weather' <<<"$STATUS")" != auto ]; then
			row auto "$ICON_AUTO" "$GREEN" "back to automatic" "$LABEL_COLOR" "$SELF run --show auto --weather auto"
		fi
		row gallery "$ICON_GALLERY" "$MAGENTA" "gallery" "$LABEL_COLOR" "$SELF run --gallery"
		local current i=0
		current=$(jq -r '.set' <<<"$STATUS")
		while IFS=$'\t' read -r key name; do
			if [ "$key" = "$current" ]; then
				row "set.$i" "$ICON_ON" "$CYAN" "$name" "$WHITE" "$SELF run --show $key"
			else
				row "set.$i" "$ICON_OFF" "$COMMENT" "$name" "$COMMENT" "$SELF run --show $key"
			fi
			i=$((i + 1))
		done < <(jq -r '.sets[] | [.key, .label] | @tsv' <<<"$STATUS")
	fi
	clear_rows
	sketchybar "${ROWS[@]}" --set "$ITEM" popup.drawing=on
}

weather_menu() {
	ROWS=()
	status || { main_menu; return; }
	local current
	current=$(jq -r '.weather' <<<"$STATUS")
	row back "$ICON_BACK" "$WHITE" "back" "$LABEL_COLOR" "$SELF menu"
	for preset in auto $(jq -r '.presets[]' <<<"$STATUS"); do
		local name=$preset color=$COMMENT
		[ "$preset" = auto ] && name="Oslo's real weather"
		[ "$preset" = "$current" ] && color=$WHITE
		row "wx.$preset" "$(weather_icon "$preset")" "$([ "$preset" = "$current" ] && echo "$YELLOW" || echo "$COMMENT")" \
			"$name" "$color" "$SELF run --weather $preset"
	done
	clear_rows
	sketchybar "${ROWS[@]}" --set "$ITEM" popup.drawing=on
}

case "${1:-$SENDER}" in
toggle)
	if [ "$(sketchybar --query "$ITEM" | jq -r '.popup.drawing')" = on ]; then
		sketchybar --set "$ITEM" popup.drawing=off
	else
		main_menu
	fi
	;;
menu) main_menu ;;
weather) weather_menu ;;
run)
	shift
	sketchybar --set "$ITEM" popup.drawing=off icon.color="$COMMENT"
	(
		"$PYTHON" "$SCRIPT" "$@" >>"$HOME/Library/Logs/wallpaper.log" 2>&1
		sketchybar --set "$ITEM" icon.color="$CYAN"
	) &
	;;
mouse.exited.global) sketchybar --set "$ITEM" popup.drawing=off ;;
esac
