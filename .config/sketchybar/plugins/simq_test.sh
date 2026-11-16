#!/usr/bin/env bash
# Tests for simq.sh. Run: bash plugins/simq_test.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok() { :; }
check() { # desc, condition-exit
	if [ "$2" -ne 0 ]; then echo "FAIL: $1"; fail=1; fi
}
run() { SIMQ_HOME="$T/home" SIMQ_BADGE_STATE="$T/last-id" SIMQ_BADGE_DRY=1 NAME=simq bash "$HERE/simq.sh" 2>&1; }
notes() { grep -c '^osascript' <<<"$1"; }

mkdir -p "$T/home"

out="$(run)"
grep -q 'drawing=off' <<<"$out"; check "no state file -> drawing=off" $?

echo '{not json' >"$T/home/state.json"
out="$(run)"
grep -q 'drawing=off' <<<"$out"; check "corrupt state -> drawing=off" $?

cat >"$T/home/state.json" <<'J'
{"requests":[
{"id":1,"type":"avd","detail":"Pixel","project":"/x/NorsCare","status":"pending"},
{"id":2,"type":"avd","detail":"Tab","project":"/x/nors","status":"pending"},
{"id":3,"type":"avd","detail":"Old","project":"/x/a","status":"approved"},
{"id":4,"type":"avd","detail":"Gone","project":"/x/b","status":"expired"}]}
J
out="$(run)"
grep -q 'label=2' <<<"$out"; check "2 pending -> label=2" $?
[ "$(notes "$out")" = 2 ]; check "2 notifications first run" $?

out="$(run)"
grep -q 'label=2' <<<"$out"; check "rerun -> label=2" $?
[ "$(notes "$out")" = 0 ]; check "rerun -> 0 notifications" $?

cat >"$T/home/state.json" <<'J'
{"requests":[
{"id":1,"type":"avd","detail":"Pixel","project":"/x/NorsCare","status":"pending"},
{"id":2,"type":"avd","detail":"Tab","project":"/x/nors","status":"pending"},
{"id":5,"type":"avd","detail":"New","project":"/x/c","status":"pending"}]}
J
out="$(run)"
[ "$(notes "$out")" = 1 ]; check "new id 5 -> 1 notification" $?
grep -q 'label=3' <<<"$out"; check "label=3" $?

# --- real (non-dry) runs with fake sketchybar/osascript on PATH ---
mkdir -p "$T/bin"
for c in sketchybar osascript; do
	cat >"$T/bin/$c" <<F
#!/bin/bash
{ printf '%s' "$c"; for a in "\$@"; do printf '\t%s' "\$a"; done; printf '\n'; } >>"$T/calls.log"
F
	chmod +x "$T/bin/$c"
done
runreal() { rm -f "$T/calls.log" "$T/last-id"; PATH="$T/bin:$PATH" SIMQ_HOME="$T/home" SIMQ_BADGE_STATE="$T/last-id" NAME=simq bash "$HERE/simq.sh"; }

PAY=("x' ; touch $T/PWNED #" "x' \$(touch $T/PWNED) #" 'x `touch '"$T"'/PWNED` y' 'a"b\c' 'x" & do shell script "touch '"$T"'/PWNED" & "')
for field in detail type project; do
	for p in "${PAY[@]}"; do
		python3 - "$T/home/state.json" "$field" "$p" <<'P'
import json, sys
r = {"id": 7, "type": "avd", "detail": "d", "project": "/x/q", "status": "pending"}
r[sys.argv[2]] = sys.argv[3]
json.dump({"requests": [r]}, open(sys.argv[1], "w"))
P
		runreal
		[ ! -e "$T/PWNED" ]; check "no side effect ($field: $p)" $?
		want="$(python3 -c '
import sys, os
f, p = sys.argv[1], sys.argv[2]
r = {"type": "avd", "detail": "d", "project": "q"}
r[f] = os.path.basename(p) if f == "project" else p
print(" ".join(("#7 %s %s · %s" % (r["type"], r["detail"], r["project"])).split()))' "$field" "$p")"
		got="$(grep '^osascript' "$T/calls.log" | tail -1 | awk -F'\t' '{print $NF}')"
		[ "$got" = "$want" ]; check "notification arg exact ($field: $p) got=[$got] want=[$want]" $?
		[ "$(grep -c '^osascript' "$T/calls.log")" = 1 ]; check "one osascript call ($field)" $?
		rm -f "$T/PWNED"
	done
done

# malformed entries must not hide good ones
cat >"$T/home/state.json" <<'J'
{"requests":[
{"id":"abc","type":"avd","detail":"bad","project":"/x/a","status":"pending"},
{"type":"avd","status":"pending"},
"junk",
{"id":9,"type":"avd","detail":"ok","project":"/x/b","status":"pending"}]}
J
runreal
grep -q $'^sketchybar\t--set\tsimq\tdrawing=on\tlabel=1$' "$T/calls.log"; check "bad entries skipped -> label=1" $?
[ "$(grep -c '^osascript' "$T/calls.log")" = 1 ]; check "bad entries: 1 notification" $?

[ $fail -eq 0 ] && echo "all ok"
exit $fail
