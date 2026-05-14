#!/usr/bin/env bash
# Play / pause button. Doubles as the script-bearing driver for the
# whole widget: its update_freq tick polls AppleScript for state
# and `--set`s the time / progress / play-icon for every other kaset.*
# item. Title rotation is handled directly by the bridge daemon, not
# by this script, so this item subscribes to `kaset_update` only.
KASET_UPDATE_FREQ="${KASET_UPDATE_FREQ:-1}"
KASET_ICON_PLAY="${KASET_ICON_PLAY:-▶}"
KASET_DISPLAY="${KASET_DISPLAY-}"

sketchybar --add item kaset.play_pause right \
           --set kaset.play_pause \
                 icon="$KASET_ICON_PLAY" \
                 click_script="$KASET_PLUGIN_DIR/kaset_play_pause.sh" \
                 script="$KASET_PLUGIN_DIR/kaset_update.sh" \
                 update_freq="$KASET_UPDATE_FREQ" \
                 display="$KASET_DISPLAY" \
                 padding_left=0 padding_right=0 \
           --subscribe kaset.play_pause kaset_update
