# SketchyBar Integration

A SketchyBar widget for Kaset — shows the current track artwork,
title, transport controls (prev / play-pause / next), playback time,
and a click-to-seek progress bar.

## Prerequisites

- macOS 26+ (Kaset's minimum).
- [SketchyBar](https://github.com/FelixKratz/SketchyBar) running:
  ```sh
  brew tap FelixKratz/formulae
  brew install sketchybar
  ```
- `jq` and `curl` on `PATH`:
  ```sh
  brew install jq
  ```
- A working Kaset.app build with AppleScript / Distributed Notifications
  support — Phase 1 is on `main`.

## Install

From the Kaset checkout:

```sh
./Scripts/sketchybar/install.sh
```

This builds the bridge daemon (`kaset-sketchybar-bridge`) in release
mode and:

| What | Where |
|---|---|
| Bridge binary | `~/.local/bin/kaset-sketchybar-bridge` |
| Widget bundle | `~/.config/sketchybar/kaset/` |
| ├ Entry point | `~/.config/sketchybar/kaset/kaset.sh` |
| ├ Item scripts | `~/.config/sketchybar/kaset/items/*.sh` |
| ├ Plugin scripts | `~/.config/sketchybar/kaset/plugins/*.sh` |
| └ Version stamp | `~/.config/sketchybar/kaset/VERSION` |
| LaunchAgent | `~/Library/LaunchAgents/app.kaset.sketchybar-bridge.plist` |
| Logs | `~/.local/share/kaset/sketchybar-bridge.log` |

The LaunchAgent is bootstrapped immediately and will auto-start on
login.

Then add a single line to your existing `sketchybarrc` (so the Kaset
widget can coexist with whatever else you already have):

```sh
echo 'source "$HOME/.config/sketchybar/kaset/kaset.sh"' \
  >> ~/.config/sketchybar/sketchybarrc
```

`kaset.sh` is the only file you ever need to touch to restyle the
widget — every font/color/width/icon knob is declared at the top of
that file. The item and plugin scripts under `items/kaset/` and
`plugins/kaset/` just consume those env vars.

If you don't yet have a `sketchybarrc`, copy the bundled minimal
example as a starting point:

```sh
cp ./Scripts/sketchybar/sketchybarrc.example ~/.config/sketchybar/sketchybarrc
```

Reload SketchyBar:

```sh
sketchybar --reload
```

## What you get

Six items, all anchored on the right side of the bar (you can move
them — see customization):

```
[artwork] [title — artist] [⏮] [▶/⏸] [⏭] [▬▬▬▬○▬▬▬▬] 1:23 / 3:45
```

- **Artwork** updates when the track changes (cached at
  `~/.cache/kaset-sketchybar/artwork-<videoId>.jpg`; cache evicts after
  30 days).
- **Title** shows `Track Name — Artist`, truncated to 30 chars.
- **Prev / Play-Pause / Next** dispatch the matching AppleScript
  commands to Kaset.
- **Progress** is a SketchyBar slider — click anywhere on it to seek
  to that position.
- **Time** shows `current / total` in `M:SS`.

## How it works

```
PlayerService (Kaset.app)
   │  posts NSDistributedNotification on track / playback / like change
   ▼
kaset-sketchybar-bridge   (LaunchAgent, ~50 LoC Swift)
   │  100 ms debounce
   ▼
sketchybar --trigger kaset_update
   │
   ▼
plugins/kaset_update.sh   (driver, also runs at 1 Hz)
   │  osascript … get player info  →  jq  →  sketchybar --set …
   ▼
Items refresh
```

The 1-Hz driver runs even between distributed-notification events so
the progress bar advances smoothly. Discrete events (track change /
play-pause / like) refresh immediately via the bridge.

See [docs/distributed-notifications.md](distributed-notifications.md)
for the notification schema and [docs/applescript.md](applescript.md)
for the command surface.

## Customization

Every tunable lives in `~/.config/sketchybar/kaset/kaset.sh`. Edit the
`Configuration` block at the top, then `sketchybar --reload`.

| Knob | Default | What it does |
|---|---|---|
| `KASET_INFO_WIDTH` | `40` | width of the stacked title / time column |
| `KASET_INFO_Y_OFFSET` | `7` | vertical split between title and time |
| `KASET_PROGRESS_WIDTH` | `100` | slider track length |
| `KASET_PROGRESS_HEIGHT` | `2` | slider track thickness |
| `KASET_ARTWORK_SCALE` | `0.15` | album art scale factor |
| `KASET_UPDATE_FREQ` | `1` | seconds between AppleScript polls |
| `KASET_TITLE_FONT` | `SF Pro:Semibold:11.0` | title typography |
| `KASET_TIME_FONT` | `SF Mono:Regular:9.0` | time-label typography |
| `KASET_TITLE_COLOR` | `0xffffffff` | title color (AARRGGBB) |
| `KASET_TIME_COLOR` | `0xffaaaaaa` | time-label color |
| `KASET_ICON_PREV` / `_NEXT` / `_PLAY` / `_PAUSE` | `⏮ ⏭ ▶ ⏸` | transport glyphs |
| `KASET_MARQUEE_WINDOW` | `10` | visible characters of the marquee |
| `KASET_MARQUEE_STEP` | `1` | characters scrolled per tick |
| `KASET_DISPLAY` | (empty) | restrict widget to a monitor: empty = all, `active`, or display index (`1`, `2`, `1,3`, …). **Do not** pass `0` — sketchybar parses it as bit 0 and pins to display 1. |

You can also override any of these **before** sourcing `kaset.sh` in
your sketchybarrc:

```sh
KASET_INFO_WIDTH=80
KASET_TITLE_COLOR=0xffff66cc
KASET_DISPLAY=2     # only show on monitor 2 (sketchybar's display index)
source "$HOME/.config/sketchybar/kaset/kaset.sh"
```

**Multi-monitor**: sketchybar enumerates displays left → right starting
at `1`. `KASET_DISPLAY=active` follows whichever monitor your cursor /
focused window is on; pass a fixed index to pin the widget to one
monitor regardless of focus.

**ASCII fallback icons** (no SF Pro / Unicode glyphs registered):

```sh
KASET_ICON_PREV="<<"
KASET_ICON_NEXT=">>"
KASET_ICON_PLAY="|>"
KASET_ICON_PAUSE="||"
source "$HOME/.config/sketchybar/kaset/kaset.sh"
```

For the runtime play/pause swap to also pick up new glyphs, export
`KASET_ICON_PLAY` / `KASET_ICON_PAUSE` in sketchybar's *launch*
environment (e.g. your shell rc), not just before the source line.

**Position / order**: items anchor on `right` and are sourced in
reverse visual order inside `kaset.sh`. Reorder the `source` lines, or
change `--add item … right` to `left`/`center` inside the
corresponding `kaset/items/*.sh`.

**Polling interval `=0`** disables polling and relies entirely on
distributed notifications — the progress bar won't advance between
track changes.

## Troubleshooting

- **Widget bundle version**: `cat ~/.config/sketchybar/kaset/VERSION`
  (or `echo $KASET_WIDGET_VERSION` after sourcing the entry point).
  Useful when you've vendored / copied the bundle and aren't sure
  which version is live.
- **Bridge log**: `tail -f ~/.local/share/kaset/sketchybar-bridge.log`.
  You should see a `ready, listening for 3 notifications` line shortly
  after login.
- **Bridge status**: `launchctl print gui/$(id -u)/app.kaset.sketchybar-bridge`.
- **Force-restart bridge**: `launchctl kickstart -k gui/$(id -u)/app.kaset.sketchybar-bridge`.
- **Smoke-test the data source**:
  ```sh
  osascript -e 'tell application "Kaset" to get player info'
  ```
  This is what every plugin script reads from. Empty / error output
  means Kaset isn't running or hasn't initialized yet.
- **Items not refreshing on track change**: check the bridge log for
  `failed to invoke sketchybar` or `sketchybar exited with status N`
  (means `sketchybar` isn't on the bridge's `PATH` — log out / log
  back in to pick up shell config).
- **Click-to-seek doesn't work**: confirm Kaset is on a build that
  includes the `seek to N` AppleScript command (Phase 1, on `main`).

## Uninstall

```sh
./Scripts/sketchybar/uninstall.sh
```

This removes the binary, plugins, and LaunchAgent. Your `sketchybarrc`
edits, artwork cache, and logs are left in place for you to clean up
manually.
