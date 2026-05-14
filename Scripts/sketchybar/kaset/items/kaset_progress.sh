#!/usr/bin/env bash
# Progress slider. Click anywhere on the track sets the playback
# position via `kaset_seek.sh`, which receives `$PERCENTAGE` from
# sketchybar and forwards it to the `seek to N` AppleScript command.
KASET_PROGRESS_WIDTH="${KASET_PROGRESS_WIDTH:-100}"
KASET_PROGRESS_HEIGHT="${KASET_PROGRESS_HEIGHT:-2}"
KASET_DISPLAY="${KASET_DISPLAY-}"

sketchybar --add slider kaset.progress right "$KASET_PROGRESS_WIDTH" \
           --set kaset.progress \
                 slider.percentage=0 \
                 slider.background.height="$KASET_PROGRESS_HEIGHT" \
                 click_script="$KASET_PLUGIN_DIR/kaset_seek.sh" \
                 display="$KASET_DISPLAY" \
                 padding_left=2 padding_right=2 \
           --subscribe kaset.progress kaset_update
