#!/usr/bin/env bash
# Open or focus a Claude desktop instance. Both run the same Claude.app bundle,
# so focus by PID. Usage: claude_open.sh main|personal

if [ "$1" = "personal" ]; then
	exec "$HOME/.dotfiles/bin/claude-personal.sh"
fi

# Main = the instance without --user-data-dir (default data folder).
pid=$(ps -axo pid=,args= | grep -E "^ *[0-9]+ /Applications/Claude.app/Contents/MacOS/Claude$" | awk 'NR==1 {print $1}')
if [ -n "$pid" ]; then
	osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" >/dev/null 2>&1
else
	open -n -a Claude
fi
