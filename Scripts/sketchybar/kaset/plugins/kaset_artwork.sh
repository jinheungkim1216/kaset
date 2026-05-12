#!/usr/bin/env bash
# Downloads artworkURL → ~/.cache/kaset-sketchybar/artwork-<videoId>.jpg
# (skipping the download if the file already exists), then sets the
# kaset.artwork item's background image. Called by kaset_update.sh
# only when the video ID changes.
set -euo pipefail

VIDEO_ID="${1:-}"
ARTWORK_URL="${2:-}"

if [[ -z "$VIDEO_ID" || -z "$ARTWORK_URL" ]]; then
    exit 0
fi

# Reject obvious placeholders (e.g. "https://music.youtube.com/" which
# Kaset returns transiently before metadata fully loads). Real artwork
# URLs are full asset URLs with a path.
case "$ARTWORK_URL" in
    https://music.youtube.com/|http://music.youtube.com/) exit 0 ;;
esac

CACHE_DIR="$HOME/.cache/kaset-sketchybar"
mkdir -p "$CACHE_DIR"

# Evict files older than 30 days. Best effort — failure is non-fatal.
find "$CACHE_DIR" -type f -mtime +30 -delete 2>/dev/null || true

ARTWORK_FILE="$CACHE_DIR/artwork-${VIDEO_ID}.jpg"

# Returns 0 if file starts with JPEG magic bytes (FF D8 FF), 1 otherwise.
# Some asset hosts return HTML error pages with HTTP 200 on rejected
# clients, which `curl -f` does not catch.
is_jpeg() {
    local file="$1"
    [[ -s "$file" ]] || return 1
    local hdr
    hdr=$(LC_ALL=C head -c 3 "$file" | xxd -p 2>/dev/null)
    [[ "$hdr" == "ffd8ff" ]]
}

if [[ ! -f "$ARTWORK_FILE" ]]; then
    # Download to a temp file and rename atomically so a concurrent
    # invocation can't observe (or clobber) a partially-written file.
    TMP_FILE="${ARTWORK_FILE}.tmp.$$"
    if ! curl -fsSL --max-time 5 -o "$TMP_FILE" "$ARTWORK_URL"; then
        rm -f "$TMP_FILE"
        exit 0
    fi
    if ! is_jpeg "$TMP_FILE"; then
        # Server returned a non-JPEG (often an HTML error page). Discard
        # so the next track-change retries with a fresh URL.
        rm -f "$TMP_FILE"
        exit 0
    fi
    mv -f "$TMP_FILE" "$ARTWORK_FILE"
fi

command -v sketchybar >/dev/null 2>&1 || exit 0

sketchybar --set kaset.artwork background.image="$ARTWORK_FILE" \
    background.image.scale=0.15
