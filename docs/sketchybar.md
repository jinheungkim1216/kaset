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
| Plugin scripts | `~/.config/sketchybar/plugins/kaset/*.sh` |
| LaunchAgent | `~/Library/LaunchAgents/app.kaset.sketchybar-bridge.plist` |
| Logs | `~/.local/share/kaset/sketchybar-bridge.log` |

The LaunchAgent is bootstrapped immediately and will auto-start on
login.

Then add the widget items to your `sketchybarrc`. Two equivalent
options:

```sh
# Option A: source the example file directly
echo 'source "$HOME/path/to/kaset/Scripts/sketchybar/sketchybarrc.example"' \
  >> ~/.config/sketchybar/sketchybarrc

# Option B: paste the contents of sketchybarrc.example into your rc
$EDITOR ~/.config/sketchybar/sketchybarrc
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

- **Position / order**: the example anchors items on `right`. Change
  to `left` or `center` per item, or shuffle the `--add` order.
- **Title length**: edit `max_label_chars=30` in `sketchybarrc.example`.
- **Colors**: SketchyBar's standard `background.color`, `label.color`,
  `icon.color` properties work on every item.
- **ASCII fallback icons** (no SF Pro / Unicode glyphs registered):
  ```sh
  sketchybar --set kaset.prev icon="<<"
  sketchybar --set kaset.next icon=">>"
  export KASET_ICON_PLAY="|>"     # picked up by kaset_update.sh
  export KASET_ICON_PAUSE="||"
  ```
- **Polling interval**: `kaset_update.sh` is wired to the
  `play_pause` item with `update_freq=1`. Change that number to
  decrease (=2 → every 2 seconds) or increase (=0 disables polling and
  relies entirely on distributed notifications, which means the
  progress bar won't advance between track changes).

## Troubleshooting

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
