#!/usr/bin/env bash

CORE_COUNT=$(sysctl -n hw.logicalcpu)
sketchybar --set "$NAME" icon="" label="$(ps -A -o %cpu | awk -v cores="$CORE_COUNT" '{s+=$1} END {printf "%.1f%%\n", s/cores}')"
