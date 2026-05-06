#!/usr/bin/env bash
# Slider click handler. SketchyBar passes the click position as
# $PERCENTAGE (0..100). We compute the target seconds from the current
# duration and dispatch it via the AppleScript `seek to N` command
# that Phase 1 added.
set -euo pipefail

PERCENTAGE="${PERCENTAGE:-0}"

DURATION=$(osascript -e 'tell application "Kaset" to get player info' 2>/dev/null \
    | jq -r '.duration // 0')

if [[ "$DURATION" == "0" || "$DURATION" == "null" || -z "$DURATION" ]]; then
    exit 0
fi

TARGET=$(awk -v p="$PERCENTAGE" -v d="$DURATION" 'BEGIN { printf "%d", (p / 100.0) * d }')

osascript -e "tell application \"Kaset\" to seek to $TARGET"
