#!/bin/zsh

# Log in to the Personal Claude desktop instance.
#
# Both instances run the same Claude.app bundle, so macOS hands the browser's
# claude:// login callback to the oldest running instance (the main one). This
# quits the main instance, lets you log in with only Personal running, then
# starts the main instance again. Run it from a terminal, not from inside the
# main Claude app (quitting it would kill that session).

set -e

personal_dir="$HOME/Library/Application Support/Claude-Personal"

# Uses ps rather than pgrep: pgrep silently misses some Claude instances.
claude_procs() {
	ps -axo pid=,args= | grep -E "^ *[0-9]+ /Applications/Claude.app/Contents/MacOS/Claude( |$)"
}

# PIDs of main Claude processes (the ones without our --user-data-dir).
main_pids() {
	claude_procs | grep -v -F -- "--user-data-dir=$personal_dir" | awk '{print $1}'
}

personal_running() {
	claude_procs | grep -q -F -- "--user-data-dir=$personal_dir"
}

pids=($(main_pids))
if (( ${#pids} )); then
	echo "Quitting main Claude (pid ${pids[*]})..."
	kill -TERM "${pids[@]}"
	for _ in {1..30}; do
		[ -z "$(main_pids)" ] && break
		sleep 0.5
	done
	if [ -n "$(main_pids)" ]; then
		echo "Main Claude did not quit. Quit it manually and re-run."
		exit 1
	fi
fi

if ! personal_running; then
	echo "Starting Claude Personal..."
	open -n -a Claude --args --user-data-dir="$personal_dir"
fi

echo
echo "Log in from the Claude Personal window now."
echo "The browser's \"Open Claude\" prompt will go to Personal, since it's the only instance."
read -r "?Press Enter once you're logged in to restart main Claude... "

# -n is required: plain `open -a Claude` would just focus the Personal instance.
open -n -a Claude
echo "Main Claude restarted."
