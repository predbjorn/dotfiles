#!/bin/bash
# Daily Homebrew upgrade, run by launchd (com.predbjorn.brew-upgrade).
# Logs to ~/Library/Logs/brew-upgrade.log and posts a macOS notification with the result.
set -uo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

notify() {
	osascript -e "display notification \"$1\" with title \"brew upgrade\"" 2>/dev/null || true
}

echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

if ! brew update; then
	notify "brew update failed — see ~/Library/Logs/brew-upgrade.log"
	exit 1
fi

outdated=$(brew outdated --quiet | wc -l | tr -d ' ')
if [ "$outdated" = "0" ]; then
	echo "Everything up to date."
	exit 0
fi

# stdin is not a TTY, so casks that need sudo fail instead of hanging.
if brew upgrade </dev/null; then
	brew cleanup --prune=7
	notify "Upgraded $outdated package(s)"
else
	brew cleanup --prune=7
	notify "Some upgrades failed — see ~/Library/Logs/brew-upgrade.log"
	exit 1
fi
