#!/usr/bin/env bash
# Play / pause button. Doubles as the script-bearing driver for the
# whole widget: its 1-Hz update_freq tick polls AppleScript for state
# and `--set`s every other kaset.* item, and its kaset_marquee_tick
# subscription rotates the title icon at ~5 Hz between full polls.
# The shared `kaset_update.sh` script branches on $SENDER to pick path.
sketchybar --add item kaset.play_pause right \
           --set kaset.play_pause \
                 icon="▶" \
                 click_script="$KASET_PLUGIN_DIR/kaset_play_pause.sh" \
                 script="$KASET_PLUGIN_DIR/kaset_update.sh" \
                 update_freq=1 \
                 padding_left=0 padding_right=0 \
           --subscribe kaset.play_pause kaset_update kaset_marquee_tick
