#!/usr/bin/env bash
# Previous-track button.
KASET_ICON_PREV="${KASET_ICON_PREV:-⏮}"
KASET_DISPLAY="${KASET_DISPLAY-}"

sketchybar --add item kaset.prev right \
           --set kaset.prev \
                 icon="$KASET_ICON_PREV" \
                 click_script="$KASET_PLUGIN_DIR/kaset_prev.sh" \
                 display="$KASET_DISPLAY" \
                 padding_left=2 padding_right=0
