#!/usr/bin/env bash

sketchybar --set "$NAME" icon="󰋊" label="$(df -H / | tail -1 | awk '{print $4}')"
