#!/usr/bin/env bash
# Album art. Image is set by `kaset_artwork.sh` (the plugin) when the
# track changes. Click activates Kaset — `open -a` brings the window
# forward across Spaces, which plain AppleScript `activate` does not.
KASET_ARTWORK_SCALE="${KASET_ARTWORK_SCALE:-0.15}"
KASET_DISPLAY="${KASET_DISPLAY-}"

sketchybar --add item kaset.artwork right \
           --set kaset.artwork \
                 background.image.scale="$KASET_ARTWORK_SCALE" \
                 background.color=0x00000000 \
                 click_script="$KASET_PLUGIN_DIR/kaset_activate.sh" \
                 display="$KASET_DISPLAY" \
                 padding_left=4 padding_right=4
