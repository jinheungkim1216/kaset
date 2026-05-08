#!/usr/bin/env bash
# Album art. Image is set by `kaset_artwork.sh` (the plugin) when the
# track changes. Click activates Kaset — `open -a` brings the window
# forward across Spaces, which plain AppleScript `activate` does not.
sketchybar --add item kaset.artwork right \
           --set kaset.artwork \
                 background.image.scale=0.15 \
                 background.color=0x00000000 \
                 click_script="$KASET_PLUGIN_DIR/kaset_activate.sh" \
                 padding_left=4 padding_right=4
