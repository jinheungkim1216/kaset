#!/usr/bin/env bash
# Progress slider. Click anywhere on the track sets the playback
# position via `kaset_seek.sh`, which receives `$PERCENTAGE` from
# sketchybar and forwards it to the `seek to N` AppleScript command.
sketchybar --add slider kaset.progress right 100 \
           --set kaset.progress \
                 slider.percentage=0 \
                 slider.background.height=2 \
                 click_script="$KASET_PLUGIN_DIR/kaset_seek.sh" \
                 padding_left=2 padding_right=2 \
           --subscribe kaset.progress kaset_update
