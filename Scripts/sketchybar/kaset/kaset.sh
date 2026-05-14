# ─── Kaset music widget ──────────────────────────────────────────────
# Single entry point for the Kaset SketchyBar widget. Source THIS file
# from your `sketchybarrc`:
#
#     source "$HOME/.config/sketchybar/kaset/kaset.sh"
#
# The widget is self-contained: this file, items/, and plugins/ all
# live under the same `kaset/` directory in both the repo and the
# installed layout. To uninstall, delete the directory.
#
# Visual layout (left → right of right group):
#
#                 ┌── title ──┐
#                 │           │
#   [artwork]   info-item   [progress] [⏮] [▶] [⏭]
#                 │           │
#                 └── time ───┘
#    │── album art ──│── navigation ──│── controls ──│
#
# `kaset.info` stacks the title and the position/duration label
# vertically using a fixed width plus a negative `label.padding_left`
# so the label re-overlaps the icon's horizontal range, with `y_offset`
# pushing each onto its own row.
#
# SketchyBar's `right` anchor places earlier-added items closest to the
# right edge, so the items below are sourced in *reverse* visual order:
# next first (rightmost), artwork last (leftmost).

# ─── Configuration ───────────────────────────────────────────────────
# Two flavours of knob:
#
#   • Baked-at-config-time (most of these): the value is passed to
#     `sketchybar --set` once when the widget is built, so editing
#     here + reloading sketchybar is enough.
#
#   • Read-at-runtime by plugins (KASET_ICON_PAUSE, KASET_MARQUEE_*):
#     plugin scripts and the bridge daemon see sketchybar's *launch*
#     environment, not this file's exports. Put those in your shell rc
#     or the sketchybar launchd plist if you want them to take effect.

# Paths — items and plugins are siblings of this file. Override either
# before sourcing if you want a custom location (rare).
KASET_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
KASET_ITEM_DIR="${KASET_ITEM_DIR:-$KASET_BASE_DIR/items}"
KASET_PLUGIN_DIR="${KASET_PLUGIN_DIR:-$KASET_BASE_DIR/plugins}"

# Self-heal stale overrides — earlier widget layouts kept everything
# flat under one directory, and users still have lines like
# `KASET_PLUGIN_DIR="$CONFIG_DIR/kaset"` in their sketchybarrc. With
# the new bundle layout that path points at the bundle root, not at
# the plugins subdir, so click/script invocations end up at non-
# existent paths. If the configured dir doesn't actually contain the
# canonical update script, fall back to the sibling plugins/ dir.
if [[ ! -f "$KASET_PLUGIN_DIR/kaset_update.sh" && -f "$KASET_BASE_DIR/plugins/kaset_update.sh" ]]; then
    KASET_PLUGIN_DIR="$KASET_BASE_DIR/plugins"
fi
if [[ ! -f "$KASET_ITEM_DIR/kaset_info.sh" && -f "$KASET_BASE_DIR/items/kaset_info.sh" ]]; then
    KASET_ITEM_DIR="$KASET_BASE_DIR/items"
fi
export KASET_ITEM_DIR KASET_PLUGIN_DIR

# Bundle version — bump the VERSION file when shipping changes under
# kaset/. After sourcing, run `echo $KASET_WIDGET_VERSION` to verify
# which build of the widget your sketchybar is actually running. Useful
# when you've copied the bundle around and aren't sure which copy is
# live.
if [[ -r "$KASET_BASE_DIR/VERSION" ]]; then
    KASET_WIDGET_VERSION="$(< "$KASET_BASE_DIR/VERSION")"
else
    KASET_WIDGET_VERSION="unknown"
fi
export KASET_WIDGET_VERSION

# Layout — widths/heights in points, y_offset in points (sketchybar units).
KASET_UPDATE_FREQ="${KASET_UPDATE_FREQ:-1}"
KASET_INFO_WIDTH="${KASET_INFO_WIDTH:-40}"
KASET_INFO_Y_OFFSET="${KASET_INFO_Y_OFFSET:-7}"
KASET_PROGRESS_WIDTH="${KASET_PROGRESS_WIDTH:-100}"
KASET_PROGRESS_HEIGHT="${KASET_PROGRESS_HEIGHT:-2}"
KASET_ARTWORK_SCALE="${KASET_ARTWORK_SCALE:-0.15}"
export KASET_UPDATE_FREQ KASET_INFO_WIDTH KASET_INFO_Y_OFFSET \
       KASET_PROGRESS_WIDTH KASET_PROGRESS_HEIGHT KASET_ARTWORK_SCALE

# Typography — sketchybar font specs are "Family:Style:Size".
KASET_TITLE_FONT="${KASET_TITLE_FONT:-SF Pro:Semibold:11.0}"
KASET_TIME_FONT="${KASET_TIME_FONT:-SF Mono:Regular:9.0}"
KASET_TITLE_COLOR="${KASET_TITLE_COLOR:-0xffffffff}"
KASET_TIME_COLOR="${KASET_TIME_COLOR:-0xffaaaaaa}"
export KASET_TITLE_FONT KASET_TIME_FONT KASET_TITLE_COLOR KASET_TIME_COLOR

# Icons — KASET_ICON_PLAY is the *initial* play glyph used at --set
# time. The 1-Hz update plugin swaps in $KASET_ICON_PAUSE / a
# refreshed $KASET_ICON_PLAY based on the AppleScript state; those two
# must be set in sketchybar's launch env to take effect at runtime.
KASET_ICON_PREV="${KASET_ICON_PREV:-⏮}"
KASET_ICON_NEXT="${KASET_ICON_NEXT:-⏭}"
KASET_ICON_PLAY="${KASET_ICON_PLAY:-▶}"
KASET_ICON_PAUSE="${KASET_ICON_PAUSE:-⏸}"
export KASET_ICON_PREV KASET_ICON_NEXT KASET_ICON_PLAY KASET_ICON_PAUSE

# Display restriction — sketchybar's per-item `display` property.
# Accepted values:
#   (empty)    all displays (default)
#   active     only on the currently active display
#   1, 2, ...  specific display index (sketchybar enumerates left → right
#              starting at 1; matches `--query` output)
#   1,3        comma-separated indices to show on multiple specific displays
# All six kaset.* items get this same value, so the widget shows up as
# a unit on the chosen monitor(s) only.
#
# NB: do NOT pass `display=0` — sketchybar parses that as "bit 0" and
# pins the item to display 1 only, which is almost never what you want.
# Empty string is the sentinel for "all displays".
KASET_DISPLAY="${KASET_DISPLAY-}"
export KASET_DISPLAY

# Marquee — read at runtime by the kaset-sketchybar-bridge daemon. Put
# these in the bridge's launchd plist (EnvironmentVariables) if you
# want non-default values; setting them here only affects shells that
# inherit from sketchybarrc, which the bridge does not.
KASET_MARQUEE_WINDOW="${KASET_MARQUEE_WINDOW:-10}"
KASET_MARQUEE_STEP="${KASET_MARQUEE_STEP:-1}"
export KASET_MARQUEE_WINDOW KASET_MARQUEE_STEP

# ─── Wiring ──────────────────────────────────────────────────────────

# Custom event the bridge daemon and update plugin both trigger —
# kaset.* items subscribe to it so they refresh together on track /
# playback changes. Marquee rotation is NOT an event: the bridge writes
# the title icon directly at ~5 Hz to avoid re-spawning shell + python
# on every tick.
sketchybar --add event kaset_update

# Controls (rightmost on screen)
source "$KASET_ITEM_DIR/kaset_next.sh"
source "$KASET_ITEM_DIR/kaset_play_pause.sh"
source "$KASET_ITEM_DIR/kaset_prev.sh"

# Navigation (middle)
source "$KASET_ITEM_DIR/kaset_progress.sh"
source "$KASET_ITEM_DIR/kaset_info.sh"

# Album art (leftmost on screen)
source "$KASET_ITEM_DIR/kaset_artwork.sh"

# ─── ASCII fallback recipe ───────────────────────────────────────────
# If you don't have SF Pro / Unicode glyphs rendering well, override
# the icon knobs above before sourcing — e.g. add to your sketchybarrc:
#
#   KASET_ICON_PREV="<<"
#   KASET_ICON_NEXT=">>"
#   KASET_ICON_PLAY="|>"
#   KASET_ICON_PAUSE="||"
#   source "$HOME/.config/sketchybar/kaset/kaset.sh"
#
# For runtime play/pause swap to actually pick up the new glyphs, also
# export KASET_ICON_PLAY/KASET_ICON_PAUSE in sketchybar's launch env.
