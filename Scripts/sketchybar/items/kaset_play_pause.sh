#!/usr/bin/env bash
# Play / pause button. Doubles as the script-bearing driver for the
# whole widget: its 1-Hz update_freq tick polls AppleScript for state
# and `--set`s the time / progress / play-icon for every other kaset.*
# item. Title rotation is handled directly by the bridge daemon, not
# by this script, so this item subscribes to `kaset_update` only.
sketchybar --add item kaset.play_pause right \
           --set kaset.play_pause \
                 icon="▶" \
                 click_script="$KASET_PLUGIN_DIR/kaset_play_pause.sh" \
                 script="$KASET_PLUGIN_DIR/kaset_update.sh" \
                 update_freq=1 \
                 padding_left=0 padding_right=0 \
           --subscribe kaset.play_pause kaset_update
