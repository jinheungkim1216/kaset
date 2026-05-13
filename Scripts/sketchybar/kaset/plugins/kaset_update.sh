#!/usr/bin/env bash
# Reads Kaset's current player state and pushes it to every kaset.* item.
# Triggered by the kaset_update custom event AND by a 1-Hz update_freq.
# Title rotation (marquee) is NOT done here — it lives in the bridge
# daemon, which reads $TITLE_STASH_FILE 5x/sec and writes the icon
# directly. This script just keeps the stash + offset files in sync
# with the AppleScript-truth title.
#
# If Kaset.app is not running, this script hides the widget and bails
# out *before* invoking AppleScript — `tell application "Kaset" to …`
# would otherwise auto-launch Kaset, which is exactly what users who
# closed it don't want.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LAST_VIDEO_FILE="${TMPDIR:-/tmp}/kaset-sketchybar-last-video.txt"
LAST_RUNNING_FILE="${TMPDIR:-/tmp}/kaset-sketchybar-running.txt"
TITLE_STASH_FILE="${TMPDIR:-/tmp}/kaset-sketchybar-title.txt"
MARQUEE_OFFSET_FILE="${TMPDIR:-/tmp}/kaset-sketchybar-marquee-offset"

# Bail out cleanly if sketchybar isn't on PATH (e.g. uninstalled / not yet
# installed). At 1Hz, `command not found` would otherwise spam the log.
command -v sketchybar >/dev/null 2>&1 || exit 0

# ── Visibility gate ──────────────────────────────────────────────────
# `pgrep -x` exact-matches the process name (Kaset.app's main binary).
# Done BEFORE any AppleScript call so we don't auto-launch Kaset.
if pgrep -x Kaset >/dev/null 2>&1; then
    IS_RUNNING=1
else
    IS_RUNNING=0
fi

PREV_RUNNING=""
if [[ -f "$LAST_RUNNING_FILE" ]]; then
    PREV_RUNNING=$(cat "$LAST_RUNNING_FILE")
fi

if [[ "$IS_RUNNING" != "$PREV_RUNNING" ]]; then
    printf '%s' "$IS_RUNNING" > "$LAST_RUNNING_FILE"
    if [[ "$IS_RUNNING" == "1" ]]; then
        DRAW=on
    else
        DRAW=off
        # Drop the title stash so the bridge daemon stops rotating
        # yesterday's track between now and when Kaset comes back.
        rm -f "$TITLE_STASH_FILE" "$MARQUEE_OFFSET_FILE"
    fi
    sketchybar --set kaset.artwork    drawing="$DRAW" \
               --set kaset.info       drawing="$DRAW" \
               --set kaset.progress   drawing="$DRAW" \
               --set kaset.prev       drawing="$DRAW" \
               --set kaset.play_pause drawing="$DRAW" \
               --set kaset.next       drawing="$DRAW"
fi

# Nothing to refresh while Kaset is closed.
[[ "$IS_RUNNING" == "0" ]] && exit 0

# ── Poll Kaset for the latest state ──────────────────────────────────
INFO=$(osascript -e 'tell application "Kaset" to get player info' 2>/dev/null) || INFO='{}'

# Validate JSON. `osascript` can exit 0 but emit a non-JSON string
# (e.g. an AppleScript runtime warning); without this guard, jq would
# fail under `set -e` and silently kill the driver.
printf '%s' "$INFO" | jq -e . >/dev/null 2>&1 || INFO='{}'

# Parse JSON. `// ""` falls back to empty string for missing keys; `// 0` for numbers.
NAME=$(printf '%s' "$INFO"        | jq -r '.currentTrack.name      // ""')
ARTIST=$(printf '%s' "$INFO"      | jq -r '.currentTrack.artist    // ""')
VIDEO_ID=$(printf '%s' "$INFO"    | jq -r '.currentTrack.videoId   // ""')
ARTWORK_URL=$(printf '%s' "$INFO" | jq -r '.currentTrack.artworkURL // ""')
DURATION=$(printf '%s' "$INFO"    | jq -r '.duration               // 0')
POSITION=$(printf '%s' "$INFO"    | jq -r '.position               // 0')
IS_PLAYING=$(printf '%s' "$INFO"  | jq -r '.isPlaying              // false')

# Format seconds → "M:SS".
fmt_time() {
    local secs=${1%.*}                      # drop fractional part
    if [[ -z "$secs" || "$secs" == "null" ]]; then
        secs=0
    fi
    printf '%d:%02d' $((secs / 60)) $((secs % 60))
}

TIME_LABEL="$(fmt_time "$POSITION") / $(fmt_time "$DURATION")"

# Progress percentage 0..100. awk handles floats safely.
if [[ "$DURATION" != "0" && "$DURATION" != "null" && -n "$DURATION" ]]; then
    PCT=$(awk -v p="$POSITION" -v d="$DURATION" 'BEGIN { printf "%d", (p / d) * 100 }')
else
    PCT=0
fi

# Play/pause icon. Unicode glyphs by default; override via env vars (e.g. ASCII).
if [[ "$IS_PLAYING" == "true" ]]; then
    PLAY_ICON="${KASET_ICON_PAUSE:-⏸}"
else
    PLAY_ICON="${KASET_ICON_PLAY:-▶}"
fi

# Title — em-dashed "Track — Artist" or just track / "—" when empty.
if [[ -z "$NAME" ]]; then
    TITLE="—"
elif [[ -n "$ARTIST" ]]; then
    TITLE="$NAME — $ARTIST"
else
    TITLE="$NAME"
fi

# Stash the full title so the bridge daemon's marquee rotator (running
# at sub-second cadence) can read it without re-querying AppleScript.
# Reset the marquee offset whenever the title changes so the new track
# always starts scrolling from its first character.
PREV_TITLE=""
if [[ -f "$TITLE_STASH_FILE" ]]; then
    PREV_TITLE=$(cat "$TITLE_STASH_FILE")
fi
if [[ "$TITLE" != "$PREV_TITLE" ]]; then
    printf '%s' "$TITLE" > "$TITLE_STASH_FILE"
    rm -f "$MARQUEE_OFFSET_FILE"
fi

# Time / progress / play-pause are all the bridge does NOT touch — the
# 5 Hz marquee loop only sets `kaset.info icon=`, never the label or
# the other items, so a 1-Hz refresh from here is enough.
sketchybar --set kaset.info        label="$TIME_LABEL" \
           --set kaset.progress    slider.percentage="$PCT" \
           --set kaset.play_pause  icon="$PLAY_ICON"

# Refresh artwork only when the video ID actually changes.
LAST_VIDEO=""
if [[ -f "$LAST_VIDEO_FILE" ]]; then
    LAST_VIDEO=$(cat "$LAST_VIDEO_FILE")
fi

if [[ "$VIDEO_ID" != "$LAST_VIDEO" ]]; then
    printf '%s' "$VIDEO_ID" > "$LAST_VIDEO_FILE"
    if [[ -n "$VIDEO_ID" && -n "$ARTWORK_URL" ]]; then
        "$PLUGIN_DIR/kaset_artwork.sh" "$VIDEO_ID" "$ARTWORK_URL" || true
    else
        sketchybar --set kaset.artwork background.image=
    fi
fi
