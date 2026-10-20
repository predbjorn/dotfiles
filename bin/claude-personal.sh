#!/bin/zsh

# Open the Personal Claude desktop instance (isolated --user-data-dir) and keep
# it alive across Claude's background "stealth updates".
#
# A stealth update quits the app and relaunches it without our --user-data-dir,
# so the Personal window just disappears. A detached watcher waits for the
# Personal process to exit, and if the shared log shows a stealth update right
# before the exit, it reopens Personal. A normal quit (Cmd+Q) is left alone.
#
# Usage: claude-personal.sh           open or focus Personal, start the watcher
#        claude-personal.sh --watch   (internal) run the watcher loop

personal_dir="$HOME/Library/Application Support/Claude-Personal"
log_file="$HOME/Library/Logs/Claude/main.log"
watch_pidfile="$HOME/Library/Caches/claude-personal-watch.pid"

personal_pid() {
	ps -axo pid=,args= | grep -F -- "/Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=$personal_dir" \
		| grep -v grep | awk 'NR==1 {print $1}'
}

launch_personal() {
	open -n -a Claude --args --user-data-dir="$personal_dir"
	local pid
	for _ in {1..30}; do
		pid=$(personal_pid)
		[ -n "$pid" ] && { echo "$pid"; return 0; }
		sleep 0.5
	done
	return 1
}

# Was there a stealth update in the log within the 30s before now? Both
# instances share this log, but the timing ties it to the exit we just saw.
exited_for_update() {
	local cutoff
	cutoff=$(date -v-30S "+%Y-%m-%d %H:%M:%S")
	tail -n 3000 "$log_file" 2>/dev/null \
		| awk -v c="$cutoff" 'substr($0, 1, 19) >= c' \
		| grep -q "\[stealth-update\] Triggering stealth update"
}

watch() {
	echo $$ > "$watch_pidfile"
	local pid
	pid=$(personal_pid)
	while [ -n "$pid" ]; do
		while kill -0 "$pid" 2>/dev/null; do
			sleep 2
		done
		exited_for_update || break
		# Let the update finish and the stealth relaunch settle first.
		sleep 5
		pid=$(personal_pid)
		[ -z "$pid" ] && pid=$(launch_personal)
	done
	rm -f "$watch_pidfile"
}

watcher_running() {
	[ -f "$watch_pidfile" ] && kill -0 "$(cat "$watch_pidfile")" 2>/dev/null
}

if [ "$1" = "--watch" ]; then
	watch
	exit 0
fi

pid=$(personal_pid)
if [ -n "$pid" ]; then
	osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" > /dev/null 2>&1
else
	pid=$(launch_personal) || { echo "Claude Personal did not start."; exit 1; }
fi

if ! watcher_running; then
	nohup "$0" --watch > /dev/null 2>&1 &
	disown
fi
