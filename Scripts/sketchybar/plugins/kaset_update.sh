#!/usr/bin/env bash
# Reads Kaset's current player state and pushes it to every kaset.* item.
# Triggered by the kaset_update custom event AND by a 1-Hz update_freq.
set -euo pipefail

PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins/kaset"
LAST_VIDEO_FILE="${TMPDIR:-/tmp}/kaset-sketchybar-last-video.txt"
TITLE_STASH_FILE="${TMPDIR:-/tmp}/kaset-sketchybar-title.txt"
MARQUEE_OFFSET_FILE="${TMPDIR:-/tmp}/kaset-sketchybar-marquee-offset"

# Bail out cleanly if sketchybar isn't on PATH (e.g. uninstalled / not yet
# installed). At 1Hz, `command not found` would otherwise spam the log.
command -v sketchybar >/dev/null 2>&1 || exit 0

# Manual marquee window/step — shared between the full-update and the
# fast marquee-tick paths so both rotate at a consistent visual rhythm.
KASET_MARQUEE_WINDOW="${KASET_MARQUEE_WINDOW:-10}"
KASET_MARQUEE_STEP="${KASET_MARQUEE_STEP:-1}"

# Fast path: the bridge daemon fires kaset_marquee_tick at sub-second
# cadence (e.g. 200 ms) so the title scroll stays smooth. We don't poll
# AppleScript here — we just rotate the cached title by one step and push
# only the icon back to SketchyBar.
if [[ "${SENDER:-}" == "kaset_marquee_tick" ]]; then
    [[ -s "$TITLE_STASH_FILE" ]] || exit 0
    CACHED_TITLE=$(cat "$TITLE_STASH_FILE")
    DISPLAY_TITLE=$(python3 - "$CACHED_TITLE" "$KASET_MARQUEE_WINDOW" "$KASET_MARQUEE_STEP" "$MARQUEE_OFFSET_FILE" <<'PY'
import os, sys
title, window, step, mfile = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
if len(title) <= window:
    print(title)
    sys.exit(0)
padded = title + "   •   "
n = len(padded)
offset = 0
if os.path.exists(mfile):
    try: offset = int(open(mfile).read().strip()) % n
    except (ValueError, OSError): pass
new_offset = (offset + step) % n
try: open(mfile, "w").write(str(new_offset))
except OSError: pass
doubled = padded + padded
print(doubled[offset:offset + window])
PY
    )
    sketchybar --set kaset.info icon="$DISPLAY_TITLE"
    exit 0
fi

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

# Stash the full title so the kaset_marquee_tick fast path can rotate it
# at sub-second cadence without re-querying AppleScript. We also reset the
# marquee offset whenever the title changes so the new track always starts
# scrolling from its first character.
PREV_TITLE=""
if [[ -f "$TITLE_STASH_FILE" ]]; then
    PREV_TITLE=$(cat "$TITLE_STASH_FILE")
fi
if [[ "$TITLE" != "$PREV_TITLE" ]]; then
    printf '%s' "$TITLE" > "$TITLE_STASH_FILE"
    rm -f "$MARQUEE_OFFSET_FILE"
fi

# Manual marquee: SketchyBar's native scroll_duration / scroll_texts
# do not actually scroll in v2.23 (they only truncate). The marquee tick
# event normally drives rotation; here we still compute the current frame
# so the 1-Hz full update doesn't visibly stall the scroll between ticks.
DISPLAY_TITLE=$(python3 - "$TITLE" "$KASET_MARQUEE_WINDOW" "$KASET_MARQUEE_STEP" "$MARQUEE_OFFSET_FILE" <<'PY'
import os, sys
title, window, step, mfile = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
if len(title) <= window:
    if os.path.exists(mfile):
        try: os.remove(mfile)
        except OSError: pass
    print(title)
else:
    padded = title + "   •   "
    n = len(padded)
    offset = 0
    if os.path.exists(mfile):
        try: offset = int(open(mfile).read().strip()) % n
        except (ValueError, OSError): pass
    new_offset = (offset + step) % n
    try: open(mfile, "w").write(str(new_offset))
    except OSError: pass
    doubled = padded + padded
    print(doubled[offset:offset + window])
PY
)

sketchybar --set kaset.info        icon="$DISPLAY_TITLE" label="$TIME_LABEL" \
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
