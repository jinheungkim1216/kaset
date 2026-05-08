#!/usr/bin/env bash
# Stacked info item: title (top, via icon field) + position/duration
# (bottom, via label field). Both are pinned to width KASET_INFO_WIDTH
# with `align=left`; `label.padding_left=-KASET_INFO_WIDTH` slides the
# time back so it overlaps the title's horizontal range, and matched
# `y_offset` on each splits them onto two rows.
#
# `icon.scroll_duration > 0` (and `label.scroll_duration > 0`) is
# requested for completeness, but SketchyBar v2.23 does not actually
# scroll — the visible scrolling is driven manually by `kaset_update.sh`
# in response to the `kaset_marquee_tick` event the bridge publishes.
KASET_INFO_WIDTH="${KASET_INFO_WIDTH:-40}"

sketchybar --add item kaset.info right \
           --set kaset.info \
                 scroll_texts=on \
                 icon="—" \
                 icon.font="SF Pro:Semibold:11.0" \
                 icon.color=0xffffffff \
                 icon.width="$KASET_INFO_WIDTH" \
                 icon.align=left \
                 icon.y_offset=7 \
                 icon.padding_left=2 \
                 icon.padding_right=0 \
                 icon.scroll_duration=8000 \
                 label="—:— / —:—" \
                 label.font="SF Mono:Regular:9.0" \
                 label.color=0xffaaaaaa \
                 label.width="$KASET_INFO_WIDTH" \
                 label.align=left \
                 label.y_offset=-7 \
                 label.padding_left="-$KASET_INFO_WIDTH" \
                 label.padding_right=2 \
                 label.scroll_duration=8000 \
           --subscribe kaset.info kaset_update
