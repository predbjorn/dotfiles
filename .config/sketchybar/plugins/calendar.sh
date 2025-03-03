#!/bin/bash

sketchybar --set $NAME icon="$(date '+%a %d. %b(%V)')" label="$(date '+%H:%M')" weeknr="$(date '+%V')"
