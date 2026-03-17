#!/usr/bin/env bash

sketchybar --set "$NAME" icon="" label="$(memory_pressure | awk '/percentage/{printf "%.0f%%", $5}')"
