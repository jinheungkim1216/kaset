#!/usr/bin/env bash
# Next-track button. Rightmost item in the kaset widget.
sketchybar --add item kaset.next right \
           --set kaset.next \
                 icon="⏭" \
                 click_script="$KASET_PLUGIN_DIR/kaset_next.sh" \
                 padding_left=0 padding_right=2
