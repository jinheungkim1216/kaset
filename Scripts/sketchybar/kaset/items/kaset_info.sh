#!/usr/bin/env bash
# Stacked info item: title (top, via icon field) + position/duration
# (bottom, via label field). Both are pinned to width $KASET_INFO_WIDTH
# with `align=left`; `label.padding_left=-$KASET_INFO_WIDTH` slides the
# time back so it overlaps the title's horizontal range, and matched
# `y_offset` on each splits them onto two rows.
#
# `icon.scroll_duration > 0` (and `label.scroll_duration > 0`) is
# requested for completeness, but SketchyBar v2.23 does not actually
# scroll — the visible scrolling is driven by the kaset-sketchybar-
# bridge daemon, which writes the icon directly at ~5 Hz.
#
# All visual knobs are sourced from the entry-point env vars with safe
# standalone fallbacks, so this file works either via sketchybarrc.example
# or run on its own.
KASET_INFO_WIDTH="${KASET_INFO_WIDTH:-40}"
KASET_INFO_Y_OFFSET="${KASET_INFO_Y_OFFSET:-7}"
KASET_TITLE_FONT="${KASET_TITLE_FONT:-SF Pro:Semibold:11.0}"
KASET_TIME_FONT="${KASET_TIME_FONT:-SF Mono:Regular:9.0}"
KASET_TITLE_COLOR="${KASET_TITLE_COLOR:-0xffffffff}"
KASET_TIME_COLOR="${KASET_TIME_COLOR:-0xffaaaaaa}"
KASET_DISPLAY="${KASET_DISPLAY-}"

sketchybar --add item kaset.info right \
           --set kaset.info \
                 scroll_texts=on \
                 icon="—" \
                 icon.font="$KASET_TITLE_FONT" \
                 icon.color="$KASET_TITLE_COLOR" \
                 icon.width="$KASET_INFO_WIDTH" \
                 icon.align=left \
                 icon.y_offset="$KASET_INFO_Y_OFFSET" \
                 icon.padding_left=2 \
                 icon.padding_right=0 \
                 icon.scroll_duration=8000 \
                 label="—:— / —:—" \
                 label.font="$KASET_TIME_FONT" \
                 label.color="$KASET_TIME_COLOR" \
                 label.width="$KASET_INFO_WIDTH" \
                 label.align=left \
                 label.y_offset="-$KASET_INFO_Y_OFFSET" \
                 label.padding_left="-$KASET_INFO_WIDTH" \
                 label.padding_right=2 \
                 label.scroll_duration=8000 \
                 display="$KASET_DISPLAY" \
           --subscribe kaset.info kaset_update
