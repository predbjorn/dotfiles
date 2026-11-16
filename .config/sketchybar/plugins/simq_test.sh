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

rm -f "$T/last-id"
cat >"$T/home/state.json" <<'J'
{"requests":[{"id":7,"type":"avd","detail":"say \"hi\" \\ there","project":"/x/q","status":"pending"}]}
J
out="$(run)"
[ "$(notes "$out")" = 1 ]; check "quote: single osascript line" $?
grep -qF 'say \"hi\" \\ there' <<<"$out"; check "quote: escaped in script" $?

[ $fail -eq 0 ] && echo "all ok"
exit $fail
