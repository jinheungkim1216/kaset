#!/usr/bin/env bash
# Next-track button. Rightmost item in the kaset widget.
KASET_ICON_NEXT="${KASET_ICON_NEXT:-⏭}"
KASET_DISPLAY="${KASET_DISPLAY-}"

sketchybar --add item kaset.next right \
           --set kaset.next \
                 icon="$KASET_ICON_NEXT" \
                 click_script="$KASET_PLUGIN_DIR/kaset_next.sh" \
                 display="$KASET_DISPLAY" \
                 padding_left=0 padding_right=2
