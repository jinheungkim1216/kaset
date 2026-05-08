#!/usr/bin/env bash
# Previous-track button.
sketchybar --add item kaset.prev right \
           --set kaset.prev \
                 icon="⏮" \
                 click_script="$KASET_PLUGIN_DIR/kaset_prev.sh" \
                 padding_left=2 padding_right=0
