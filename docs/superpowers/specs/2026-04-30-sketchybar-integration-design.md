# SketchyBar Integration Design

**Date:** 2026-04-30
**Status:** Approved (pending implementation plan)

## Goal

Make Kaset usable from [SketchyBar](https://github.com/FelixKratz/SketchyBar) as a Now-Playing widget showing track artwork, title, play time, transport controls (prev / play-pause / next), and a clickable progress bar that supports seek-to-position.

## Non-Goals

- Sidebar / app navigation control from SketchyBar (not requested).
- Replacing AppleScript for command/query duties — AppleScript stays.
- Volume / shuffle / repeat / mute UI in the SketchyBar widget (out of scope; commands still available via AppleScript if a user wants to wire them).

## Architecture

```
┌────────────────────────────┐
│ Kaset.app                  │
│  PlayerService             │ ── (track / playback / like change) ──┐
│  AppleScript:              │                                       │
│   • play / pause / next /  │ ◀─ AppleScript (osascript) ──┐        │
│     previous / playpause   │                              │        │
│   • get player info        │                              │        ▼
│   • set volume / mute /    │                              │   NSDistributedNotificationCenter
│     shuffle / repeat / like│                              │        │
│   • seek to N  (NEW)       │                              │        │
└────────────────────────────┘                              │        ▼
                                              ┌─────────────┴───────────────┐
                                              │ kaset-sketchybar-bridge     │
                                              │ (Swift daemon, LaunchAgent) │
                                              │  notification → 100 ms      │
                                              │  debounce → exec            │
                                              │  `sketchybar --trigger      │
                                              │   kaset_update`             │
                                              └──────────────┬──────────────┘
                                                             │
                                                             ▼
                                              ┌──────────────────────────────┐
                                              │ sketchybar                   │
                                              │  subscribe kaset_update      │
                                              │  → plugins/kaset_update.sh   │
                                              │  (osascript get player info) │
                                              └──────────────────────────────┘
```

### Boundaries

- **Kaset → outside world:** two channels.
  - `NSDistributedNotification` for events (push, fire-and-forget, no return value).
  - AppleScript / NSScriptCommand for commands and queries (request/response).
  - Kaset's own code does not know about SketchyBar. The bridge is the only Kaset-aware component.
- **Bridge → SketchyBar:** a single shell exec — `sketchybar --trigger kaset_update`. SketchyBar does not know about the bridge.
- **Progress bar advancement** inherently needs polling because position progresses continuously. Discrete state changes (track change, play/pause flip, like flip) are event-driven.

## Phase 1 — Kaset App Changes

### 1.1 New AppleScript command: `seek to N`

| File | Change |
|---|---|
| `Sources/Kaset/Resources/Kaset.sdef` | Add `<command name="seek to" code="Kastseek">` with a real direct-parameter (seconds, integer or real). |
| `Sources/Kaset/Services/Scripting/ScriptCommands.swift` | New `KasetSeekCommand: NSScriptCommand`. Reads direct parameter, calls `playerService.seek(to: time)` on `MainActor`. Returns `errPlayerNotAvailable` when service is nil. |
| `docs/applescript.md` | Add row to commands table; add an example. |

Usage: `tell application "Kaset" to seek to 90`.

### 1.2 NSDistributedNotification publishing

**New file** `Sources/Kaset/Services/Player/PlayerService+Notifications.swift` (extension; keeps `PlayerService.swift` from growing).

**Notification names** (reverse-DNS):

| Name | Posted when |
|---|---|
| `app.kaset.player.trackChanged` | `currentTrack` becomes a different track (or becomes nil / non-nil). |
| `app.kaset.player.playbackStateChanged` | `state` transitions (loading / playing / paused / stopped). |
| `app.kaset.player.likeStatusChanged` | `currentTrackLikeStatus` changes. |

(Volume / shuffle / repeat / mute are intentionally NOT published in v1. They can be added later if a consumer asks.)

**`userInfo` payload (rich, all three notifications share the same schema):**

```json
{
  "isPlaying": true,
  "isPaused": false,
  "position": 45.2,
  "duration": 180.0,
  "volume": 75,
  "shuffling": true,
  "repeating": "all",
  "muted": false,
  "likeStatus": "liked",
  "currentTrack": {
    "name": "Song Title",
    "artist": "Artist Name",
    "album": "Album Name",
    "duration": 180,
    "videoId": "dQw4w9WgXcQ",
    "artworkURL": "https://..."
  }
}
```

This is exactly the schema returned by `get player info`. To enforce single-source-of-truth, extract a shared snapshot helper that both `GetPlayerInfoCommand` and the notification publisher use. Suggested location: a new `PlayerStateSnapshot.swift` in `Sources/Kaset/Services/Scripting/` (or `Player/`) exposing a single `func makePlayerInfoDictionary(from: PlayerService) -> [String: Any]`. Existing `GetPlayerInfoCommand` is refactored to use it.

**Trigger points** (in `PlayerService` / its extensions). Notifications fire only when the value actually changes (compare new vs old; suppress no-op writes):
- `currentTrack` changes (videoId differs from previous, including nil ⇄ non-nil) → `notifyTrackChanged()`.
- `state` changes → `notifyPlaybackStateChanged()`.
- `currentTrackLikeStatus` changes → `notifyLikeStatusChanged()`.

Implementation may use `didSet` on stored properties, or explicit calls at existing assignment sites — whichever fits the current `PlayerService` patterns more cleanly. Implementer will pick after reading the file.

**No debounce on the publisher side.** The bridge debounces on the consumer side. This keeps `PlayerService` simple.

**Threading:** posting must be safe to call from `MainActor`. `DistributedNotificationCenter.default().postNotificationName(_:object:userInfo:options:)` is thread-safe; the snapshot read must happen on `MainActor`.

### 1.3 Documentation

- New file `docs/distributed-notifications.md`:
  - Lists notification names + payload schema.
  - Shows Swift and Objective-C subscription examples.
  - Notes that `userInfo` mirrors `get player info` JSON.
- `docs/applescript.md`: append `seek to N` row to the table; example.
- `docs/architecture.md`: 1–2 lines describing the new outbound channel (DN) if appropriate.

### 1.4 Tests

Add to `Tests/KasetTests/`:
- `seek` command:
  - Calls `PlayerService.seek(to:)` with the parameter when player is available.
  - Returns `errPlayerNotAvailable` when service is nil.
- Distributed notification publishing:
  - Subscribe to `DistributedNotificationCenter.default()` in test setup.
  - Trigger track change → assert `app.kaset.player.trackChanged` received with expected payload keys.
  - Trigger state change → assert `app.kaset.player.playbackStateChanged` received.
- `PlayerStateSnapshot.makePlayerInfoDictionary`:
  - Returns expected schema for a representative track.
  - Returns no `currentTrack` key when no track is loaded.

Use Swift Testing (`@Test`, `#expect`).

## Phase 2 — SketchyBar Integration

### 2.1 Bridge daemon `kaset-sketchybar-bridge`

New SwiftPM executable target.

| File | Change |
|---|---|
| `Package.swift` | Add `.executable(name: "kaset-sketchybar-bridge", targets: ["SketchybarBridge"])` product and matching `.executableTarget`. |
| `Sources/SketchybarBridge/main.swift` | Foundation-only daemon, ~50 lines. |

**Behavior:**
1. On launch, subscribe via `DistributedNotificationCenter.default().addObserver` to:
   `app.kaset.player.trackChanged`, `app.kaset.player.playbackStateChanged`, `app.kaset.player.likeStatusChanged`.
2. On any received notification, schedule a 100 ms debounced trigger.
3. Trigger: `Process.run("/usr/bin/env", ["sketchybar", "--trigger", "kaset_update"])`. If `sketchybar` is not on `PATH`, log to stderr and continue (no-op until next event).
4. `RunLoop.main.run()` to remain alive.
5. Logs go to stderr; `os.Logger` with subsystem `app.kaset.sketchybar-bridge`.

**Concurrency:** main-actor-only daemon; no shared state to worry about.

### 2.2 LaunchAgent

`Scripts/sketchybar/launchagent/app.kaset.sketchybar-bridge.plist`:
- `Label = app.kaset.sketchybar-bridge`
- `ProgramArguments = [<install_path>/kaset-sketchybar-bridge]`
- `KeepAlive = true`, `RunAtLoad = true`
- `StandardErrorPath = ~/.local/share/kaset/sketchybar-bridge.log`

`install.sh` performs path substitution before copying.

### 2.3 SketchyBar plugins

`Scripts/sketchybar/plugins/`:

| Script | When it runs | Job |
|---|---|---|
| `kaset_update.sh` | `kaset_update` event + `update_freq=1` (one item drives the rest) | `osascript -e 'tell application "Kaset" to get player info'` → `jq` → emit `sketchybar --set` for `kaset.title`, `kaset.time`, `kaset.progress` (percentage), `kaset.play_pause` (icon), and (when video ID changes) call `kaset_artwork.sh`. |
| `kaset_artwork.sh` | Called by `kaset_update.sh` when video ID changes | Download `artworkURL` → `~/.cache/kaset-sketchybar/artwork-<videoId>.jpg` → `--set kaset.artwork background.image=...`. Skip download if file exists. |
| `kaset_play_pause.sh` | Click on `kaset.play_pause` | `osascript -e 'tell application "Kaset" to playpause'`. |
| `kaset_next.sh` | Click on `kaset.next` | `next track`. |
| `kaset_prev.sh` | Click on `kaset.prev` | `previous track`. |
| `kaset_seek.sh` | Click on `kaset.progress` slider | Read `$PERCENTAGE`, query duration, compute target seconds, `tell application "Kaset" to seek to N`. |

**State / caching:**
- Last seen video ID stored in `/tmp/kaset-sketchybar-last-video.txt` for artwork dedupe.
- Artwork cache in `~/.cache/kaset-sketchybar/` — `kaset_artwork.sh` deletes files older than 30 days at the end of each run (one-liner with `find -mtime`).
- All scripts: `set -euo pipefail`; pass `shellcheck`.

**External dependencies:** `sketchybar`, `jq`, `curl`. `install.sh` checks and prints brew commands if missing.

### 2.4 SketchyBar config snippet

`Scripts/sketchybar/sketchybarrc.example` — a copy-pasteable block that adds:
- `kaset.artwork` (item with `background.image`, square, scale 0.15)
- `kaset.title` (label, max 30 chars, `max_label_chars` and scrolling)
- `kaset.prev`, `kaset.play_pause`, `kaset.next` (icon items with `click_script`)
- `kaset.progress` (slider; `click_script` for seek)
- `kaset.time` (label, e.g. `1:23 / 3:45`)

The driver item (`kaset.play_pause`) carries `script=$PLUGIN_DIR/kaset_update.sh` with `update_freq=1`. All other items only `--subscribe ... kaset_update`.

Two icon styles in the example, commented:
- SF Symbols Unicode (assumes user registered SF Symbols font in SketchyBar).
- Plain ASCII fallback (`<<`, `▶`, `⏸`, `>>`).

### 2.5 Install / uninstall scripts

`Scripts/sketchybar/install.sh`:
1. Check `sketchybar`, `jq`, `curl` on `PATH`. Print `brew install` commands and exit if missing.
2. `swift build -c release --product kaset-sketchybar-bridge`.
3. Copy `.build/release/kaset-sketchybar-bridge` → `~/.local/bin/kaset-sketchybar-bridge` (mkdir as needed).
4. Copy `Scripts/sketchybar/plugins/*` → `~/.config/sketchybar/plugins/kaset/`. Set `+x`.
5. Render LaunchAgent plist (substitute `<install_path>`) → `~/Library/LaunchAgents/app.kaset.sketchybar-bridge.plist`. `launchctl bootstrap gui/$(id -u)` it.
6. Print next steps: how to add the example block to user's `sketchybarrc`, and `sketchybar --reload`.

`Scripts/sketchybar/uninstall.sh`: reverse of the above (`launchctl bootout`, remove files). Leaves user's `sketchybarrc` alone with a printed reminder.

### 2.6 Documentation

`docs/sketchybar.md`:
- Screenshot.
- Prerequisites (brew installs).
- Install: `./Scripts/sketchybar/install.sh`.
- How to add the snippet to existing `sketchybarrc`.
- Customization tips (colors, position, max title chars, icon style).
- Troubleshooting:
  - `tail -f ~/.local/share/kaset/sketchybar-bridge.log`
  - `launchctl kickstart -k gui/$(id -u)/app.kaset.sketchybar-bridge`
  - `osascript -e 'tell application "Kaset" to get player info'` to sanity-check the data source.

Update top-level `README.md` with a one-line link to `docs/sketchybar.md`.

### 2.7 Tests / verification

- Unit test (`Tests/SketchybarBridgeTests/`): debounce coalesces 5 notifications within 100 ms into a single trigger call (use a mock executor so we don't actually invoke sketchybar). Single test, kept lean.
- `shellcheck` over `Scripts/sketchybar/plugins/*.sh` and `install.sh` / `uninstall.sh` in CI (or add to a Make/Just target).
- Manual end-to-end check on a developer machine, recorded in PR description: track change, play/pause, next/prev, seek by clicking progress bar.

## Open Decisions Captured

| Decision | Choice | Reasoning |
|---|---|---|
| Mirror everything in DN? | No — DN events only; AppleScript stays. | DN is push-only; queries (`get player info`) need request/response, only AppleScript can do that cleanly. Also keeps Raycast / Alfred / Shortcuts compatibility. |
| DN payload | Rich (full snapshot, same schema as `get player info`) | Cheap to publish; helps non-SketchyBar consumers (e.g., Discord rich presence) avoid an extra `osascript` call. |
| Notification scope v1 | track / playback state / like — 3 events | Covers the SketchyBar widget needs. Volume / shuffle / repeat / mute can be added later without breaking the schema. |
| Bridge location | New SwiftPM executable target in this repo (`Sources/SketchybarBridge`). | Mirrors `APIExplorer` pattern. Keeps notification names and bridge in sync via shared repo. |
| Install method | `install.sh` shell script + LaunchAgent. | Lightweight, no brew formula or external repo; users can read the script. |
| Polling interval | 1 s on the driver item; bridge debounce 100 ms for events. | 1 Hz is smooth enough for a status bar progress; debounce kills duplicate-notification flurries. |
| Bridge knows what changed? | No — bridge always issues the same `kaset_update` trigger; SketchyBar plugin re-fetches full state. | Single code path, no state in the bridge. The cost is one `osascript` call per event, which is fine. |

## Phasing & Deliverables

Two PRs (or two commits, sequential):

1. **PR 1 — Kaset app changes:** seek command, DN publishing, snapshot helper extraction, tests, docs (`distributed-notifications.md`, updated `applescript.md`). Self-contained; can ship without Phase 2.
2. **PR 2 — SketchyBar integration:** bridge daemon target, plugin scripts, install/uninstall scripts, `sketchybarrc.example`, `docs/sketchybar.md`, optional shellcheck CI hook.

Each PR will get its own implementation plan via the `writing-plans` skill once this design is approved.
