#!/usr/bin/env bash
# simq badge: pending approval count + one notification per new request.
# SIMQ_BADGE_DRY=1 prints the commands instead of running them.

SIMQ_HOME="${SIMQ_HOME:-$HOME/.simq}"
STATE_FILE="${SIMQ_BADGE_STATE:-${TMPDIR:-/tmp}/simq-badge-last-id}"
NAME="${NAME:-simq}"

# Line 1 = pending count; then one line per not-yet-notified pending request.
OUT="$(SIMQ_HOME="$SIMQ_HOME" STATE_FILE="$STATE_FILE" /usr/bin/python3 -I -c '
import json, os, sys
try:
    with open(os.path.join(os.environ["SIMQ_HOME"], "state.json")) as f:
        reqs = json.load(f)["requests"]
    pending = [r for r in reqs if r.get("status") == "pending"]
    try:
        with open(os.environ["STATE_FILE"]) as f:
            last = int(f.read().strip() or 0)
    except (OSError, ValueError):
        last = 0
    lines = [str(len(pending))]
    for r in pending:
        if r["id"] > last:
            proj = os.path.basename(str(r.get("project", "")).rstrip("/"))
            text = "#%s %s %s · %s" % (r["id"], r.get("type", ""), r.get("detail", ""), proj)
            lines.append(" ".join(text.split()))
    if pending:
        new_last = max(last, max(r["id"] for r in pending))
        with open(os.environ["STATE_FILE"], "w") as f:
            f.write(str(new_last))
    print("\n".join(lines))
except Exception:
    print(0)
' 2>/dev/null)"

COUNT="$(head -n1 <<<"$OUT")"
case "$COUNT" in '' | *[!0-9]*) COUNT=0 ;; esac

run() {
	if [ "${SIMQ_BADGE_DRY:-}" = 1 ]; then
		printf '%s\n' "$*"
	else
		eval "$*"
	fi
}

if [ "$COUNT" -eq 0 ]; then
	run sketchybar --set "$NAME" drawing=off
	exit 0
fi
run sketchybar --set "$NAME" drawing=on label="$COUNT"

# Single-quote a string for the shell.
shq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

tail -n +2 <<<"$OUT" | while IFS= read -r line; do
	[ -n "$line" ] || continue
	esc="${line//\\/\\\\}"
	esc="${esc//\"/\\\"}"
	script="display notification \"$esc\" with title \"simq\" subtitle \"needs your approval\""
	run osascript -e "$(shq "$script")"
done
