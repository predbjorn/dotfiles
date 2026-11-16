#!/usr/bin/env bash
# simq badge: pending approval count + one notification per new request.
# SIMQ_BADGE_DRY=1 prints the commands instead of running them.

SIMQ_HOME="${SIMQ_HOME:-$HOME/.simq}"
STATE_FILE="${SIMQ_BADGE_STATE:-${TMPDIR:-/tmp}/simq-badge-last-id}"
NAME="${NAME:-simq}"

# Line 1 = pending count; then one line per not-yet-notified pending request.
OUT="$(SIMQ_HOME="$SIMQ_HOME" STATE_FILE="$STATE_FILE" /usr/bin/python3 -I -c '
import json, os
try:
    with open(os.path.join(os.environ["SIMQ_HOME"], "state.json")) as f:
        reqs = json.load(f)["requests"]
    pending = []
    for r in reqs:
        try:
            if r.get("status") == "pending":
                pending.append((int(r["id"]), r))
        except Exception:
            continue
    try:
        with open(os.environ["STATE_FILE"]) as f:
            last = int(f.read().strip() or 0)
    except (OSError, ValueError):
        last = 0
    lines = [str(len(pending))]
    for i, r in pending:
        if i > last:
            proj = os.path.basename(str(r.get("project", "")).rstrip("/"))
            text = "#%s %s %s \u00b7 %s" % (i, r.get("type", ""), r.get("detail", ""), proj)
            lines.append(" ".join(text.split()))
    if pending:
        with open(os.environ["STATE_FILE"], "w") as f:
            f.write(str(max([last] + [i for i, _ in pending])))
    print("\n".join(lines))
except Exception:
    print(0)
' 2>/dev/null)"

COUNT="$(head -n1 <<<"$OUT")"
case "$COUNT" in '' | *[!0-9]*) COUNT=0 ;; esac

# Never eval: args are passed as argv so request text cannot be interpreted.
run() {
	if [ "${SIMQ_BADGE_DRY:-}" = 1 ]; then
		printf '%q ' "$@"
		echo
	else
		"$@"
	fi
}

if [ "$COUNT" -eq 0 ]; then
	run sketchybar --set "$NAME" drawing=off
	exit 0
fi
run sketchybar --set "$NAME" drawing=on label="$COUNT"

# Text goes in as argv, never as AppleScript source.
tail -n +2 <<<"$OUT" | while IFS= read -r line; do
	[ -n "$line" ] || continue
	run osascript -e 'on run argv' \
		-e 'display notification (item 1 of argv) with title "simq" subtitle "needs your approval"' \
		-e 'end run' "$line"
done
