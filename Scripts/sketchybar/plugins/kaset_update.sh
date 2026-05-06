#!/usr/bin/env bash
# Reads Kaset's current player state and pushes it to every kaset.* item.
# Triggered by the kaset_update custom event AND by a 1-Hz update_freq.
set -euo pipefail

PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins/kaset"
LAST_VIDEO_FILE="${TMPDIR:-/tmp}/kaset-sketchybar-last-video.txt"

INFO=$(osascript -e 'tell application "Kaset" to get player info' 2>/dev/null) || INFO='{}'

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

# Play/pause icon. SF Symbols glyphs by default; ASCII fallback via env vars.
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

sketchybar --set kaset.title       label="$TITLE" \
           --set kaset.time        label="$TIME_LABEL" \
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
