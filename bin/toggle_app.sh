#!/bin/zsh
# Toggle app: focus if not frontmost, hide if already frontmost
export PATH="/opt/homebrew/bin:$PATH"
app="$1"

# Use yabai to check if the currently focused window belongs to the target app
focused_app=$(yabai -m query --windows --window 2>/dev/null | jq -r '.app // empty')

if [ "$focused_app" = "$app" ]; then
    osascript -e "tell application \"System Events\" to set visible of application process \"$app\" to false"
else
    "$HOME/.dotfiles/bin/focus_window_wrapper.sh" "$app"
fi
