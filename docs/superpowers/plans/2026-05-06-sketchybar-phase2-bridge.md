# Phase 2 — SketchyBar Bridge & Plugins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a [SketchyBar](https://github.com/FelixKratz/SketchyBar) widget that displays Kaset's current track artwork, title, position/duration, transport controls (prev / play-pause / next), and a click-to-seek progress bar — driven by Phase 1's distributed notifications and existing AppleScript surface.

**Architecture:** A small Swift daemon (`kaset-sketchybar-bridge`, run as a LaunchAgent) subscribes to `app.kaset.player.{trackChanged,playbackStateChanged,likeStatusChanged}` distributed notifications, debounces them (100 ms), and invokes `sketchybar --trigger kaset_update`. SketchyBar's plugin scripts re-fetch the current state via `osascript ... get player info` and update each item. A 1-Hz `update_freq` on one driver item keeps the progress bar / time advancing between events. Click handlers send AppleScript commands.

**Tech Stack:** Swift 6 (Foundation only), shell scripts (bash + jq + curl), SketchyBar, launchd.

**Spec:** `docs/superpowers/specs/2026-04-30-sketchybar-integration-design.md` (Phase 2 sections).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `Package.swift` | Add `kaset-sketchybar-bridge` executable product, plus `SketchybarBridge` and `SketchybarBridgeTests` targets. |
| Create | `Sources/SketchybarBridge/Debouncer.swift` | A `NotificationDebouncer` actor that coalesces calls within a window and fires its closure once when the window expires. |
| Create | `Sources/SketchybarBridge/main.swift` | Wires `DistributedNotificationCenter` observers → `NotificationDebouncer` → `Process.run("sketchybar", "--trigger", "kaset_update")`. |
| Create | `Tests/SketchybarBridgeTests/DebouncerTests.swift` | Verifies that N rapid bumps within the window collapse to a single underlying invocation, and bumps further apart fire separately. |
| Create | `Scripts/sketchybar/plugins/kaset_update.sh` | Reads `osascript ... get player info`, parses with `jq`, sets `kaset.title`, `kaset.time`, `kaset.progress`, `kaset.play_pause` icon. Triggers artwork update when video ID changes. |
| Create | `Scripts/sketchybar/plugins/kaset_artwork.sh` | Downloads `artworkURL` to `~/.cache/kaset-sketchybar/artwork-<videoId>.jpg` (skips if already present), sets `kaset.artwork background.image`, expires files older than 30 days. |
| Create | `Scripts/sketchybar/plugins/kaset_play_pause.sh` | Click handler — `osascript -e 'tell application "Kaset" to playpause'`. |
| Create | `Scripts/sketchybar/plugins/kaset_next.sh` | Click handler — `next track`. |
| Create | `Scripts/sketchybar/plugins/kaset_prev.sh` | Click handler — `previous track`. |
| Create | `Scripts/sketchybar/plugins/kaset_seek.sh` | Slider click — reads `$PERCENTAGE`, queries duration, dispatches `seek to N`. |
| Create | `Scripts/sketchybar/sketchybarrc.example` | Copy-pasteable item definitions for the user's `sketchybarrc`. |
| Create | `Scripts/sketchybar/launchagent/app.kaset.sketchybar-bridge.plist` | LaunchAgent template (paths substituted by `install.sh`). |
| Create | `Scripts/sketchybar/install.sh` | Builds bridge, copies binary + plugins, writes LaunchAgent plist, `launchctl bootstrap`s it. |
| Create | `Scripts/sketchybar/uninstall.sh` | Reverses `install.sh`. |
| Create | `docs/sketchybar.md` | User-facing doc: prerequisites, install, customize, troubleshoot. |
| Modify | `README.md` | One-line link to `docs/sketchybar.md`. |

---

## Task 1: Bridge SwiftPM target + `NotificationDebouncer` (TDD)

The debouncer is the only piece of bridge logic with non-trivial behavior; we extract it so we can test it in isolation. Production wires it to a closure that runs `sketchybar --trigger`; tests wire it to a counter.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SketchybarBridge/Debouncer.swift`
- Test: `Tests/SketchybarBridgeTests/DebouncerTests.swift`

- [ ] **Step 1: Add the executable product, target, and test target to `Package.swift`**

In `Package.swift`, locate the `products: [...]` array and append a new `.executable(...)` product after the existing `api-explorer` entry. The new entry sits inside the same array:

```swift
        .executable(
            name: "kaset-sketchybar-bridge",
            targets: ["SketchybarBridge"]
        ),
```

Then locate the `targets: [...]` array and append two new entries after the existing `KasetTests` test target:

```swift
        // SketchyBar bridge daemon
        .executableTarget(
            name: "SketchybarBridge",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        // Bridge daemon tests
        .testTarget(
            name: "SketchybarBridgeTests",
            dependencies: ["SketchybarBridge"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
```

- [ ] **Step 2: Write the failing test**

Create `Tests/SketchybarBridgeTests/DebouncerTests.swift`:

```swift
import Foundation
import Testing
@testable import SketchybarBridge

@Suite(.serialized)
struct DebouncerTests {
    actor Counter {
        private(set) var value = 0
        func increment() { self.value += 1 }
    }

    @Test("Multiple rapid bumps within the window collapse to one action")
    func collapsesRapidBumps() async throws {
        let counter = Counter()
        let debouncer = NotificationDebouncer(interval: .milliseconds(50)) {
            await counter.increment()
        }

        for _ in 0 ..< 5 {
            await debouncer.bump()
        }

        try await Task.sleep(for: .milliseconds(150))
        let count = await counter.value
        #expect(count == 1)
    }

    @Test("Bumps further apart than the interval each fire the action")
    func separateBumpsFireSeparately() async throws {
        let counter = Counter()
        let debouncer = NotificationDebouncer(interval: .milliseconds(50)) {
            await counter.increment()
        }

        await debouncer.bump()
        try await Task.sleep(for: .milliseconds(120))
        await debouncer.bump()
        try await Task.sleep(for: .milliseconds(120))

        let count = await counter.value
        #expect(count == 2)
    }

    @Test("Cancel before the window expires suppresses the action")
    func cancelSuppressesAction() async throws {
        let counter = Counter()
        let debouncer = NotificationDebouncer(interval: .milliseconds(50)) {
            await counter.increment()
        }

        await debouncer.bump()
        await debouncer.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let count = await counter.value
        #expect(count == 0)
    }
}
```

- [ ] **Step 3: Run the test to confirm it fails**

```bash
swift test --skip KasetUITests --filter DebouncerTests
```
Expected: build error — `cannot find 'NotificationDebouncer' in scope`.

- [ ] **Step 4: Implement `NotificationDebouncer`**

Create `Sources/SketchybarBridge/Debouncer.swift`:

```swift
import Foundation

/// Trailing-edge debouncer: every `bump()` resets a timer; when the timer
/// expires without further bumps, the configured `action` runs once.
/// Multiple rapid bumps within `interval` collapse to a single action call.
actor NotificationDebouncer {
    private let interval: Duration
    private let action: @Sendable () async -> Void
    private var pendingTask: Task<Void, Never>?

    init(interval: Duration, action: @escaping @Sendable () async -> Void) {
        self.interval = interval
        self.action = action
    }

    /// Resets the debounce window. The action will run after one full
    /// `interval` of quiet (no further bumps).
    func bump() {
        self.pendingTask?.cancel()
        let interval = self.interval
        let action = self.action
        self.pendingTask = Task {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return // cancelled
            }
            await action()
        }
    }

    /// Cancels any pending action.
    func cancel() {
        self.pendingTask?.cancel()
        self.pendingTask = nil
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
swift test --skip KasetUITests --filter DebouncerTests
```
Expected: PASS for all three test cases.

- [ ] **Step 6: Run the full unit suite to make sure nothing else broke**

```bash
swift test --skip KasetUITests
```
Expected: previous test count plus 3 new tests, all passing.

- [ ] **Step 7: Commit**

```bash
git add Package.swift \
        Sources/SketchybarBridge/Debouncer.swift \
        Tests/SketchybarBridgeTests/DebouncerTests.swift
git commit -m "$(cat <<'EOF'
feat(sketchybar-bridge): add SwiftPM target with NotificationDebouncer

Adds a new kaset-sketchybar-bridge executable target and matching
test target. Introduces NotificationDebouncer — a trailing-edge
debouncer actor that coalesces rapid bumps within a window and fires
its closure once. The bridge will use this to collapse bursts of
distributed notifications into a single sketchybar trigger.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Bridge `main.swift` (subscribe + invoke `sketchybar`)

Wires the three Phase 1 distributed notifications to a single `sketchybar --trigger kaset_update` exec, debounced through the helper from Task 1.

**Files:**
- Create: `Sources/SketchybarBridge/main.swift`

There is no clean unit test for the wiring — `DistributedNotificationCenter` and `Process.run` are integration concerns. The debouncer itself is already covered by Task 1. We verify this task by manual smoke test (Step 4 below) and the end-to-end smoke in Task 7.

- [ ] **Step 1: Implement `main.swift`**

Create `Sources/SketchybarBridge/main.swift`:

```swift
import Foundation

/// Names of distributed notifications that should trigger a SketchyBar refresh.
private let kasetNotificationNames = [
    "app.kaset.player.trackChanged",
    "app.kaset.player.playbackStateChanged",
    "app.kaset.player.likeStatusChanged",
]

/// Custom event name posted to SketchyBar.
private let sketchybarEventName = "kaset_update"

/// Quiet window after the last received notification before we emit the trigger.
private let debounceInterval: Duration = .milliseconds(100)

private func logStderr(_ line: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let payload = "[\(stamp)] \(line)\n"
    if let data = payload.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

@Sendable private func runSketchybarTrigger() async {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = ["sketchybar", "--trigger", sketchybarEventName]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        logStderr("failed to invoke sketchybar: \(error)")
    }
}

let debouncer = NotificationDebouncer(interval: debounceInterval) {
    await runSketchybarTrigger()
}

let center = DistributedNotificationCenter.default()
for name in kasetNotificationNames {
    center.addObserver(
        forName: Notification.Name(name),
        object: nil,
        queue: nil
    ) { _ in
        Task { await debouncer.bump() }
    }
}

logStderr("kaset-sketchybar-bridge ready, listening for \(kasetNotificationNames.count) notifications")

RunLoop.main.run()
```

- [ ] **Step 2: Build the bridge product**

```bash
swift build --product kaset-sketchybar-bridge
```
Expected: `Build complete!` with no warnings about strict concurrency.

- [ ] **Step 3: Run the full unit suite**

```bash
swift test --skip KasetUITests
```
Expected: same green result as Task 1 — the new wiring code adds no tests but should not regress existing ones.

- [ ] **Step 4: Manual smoke test**

In one terminal:

```bash
.build/debug/kaset-sketchybar-bridge
```

You should see the timestamped `ready, listening...` line on stderr, and the process should remain alive. The `sketchybar --trigger` invocations will fail (assuming sketchybar is not running yet) but that's expected — the bridge logs the failure and continues. End the test with Ctrl-C.

If Kaset is running and a track changes during the smoke test, the bridge will attempt the trigger; sketchybar will accept or reject silently depending on whether it knows the `kaset_update` event yet (Task 4 wires that up).

- [ ] **Step 5: Commit**

```bash
git add Sources/SketchybarBridge/main.swift
git commit -m "$(cat <<'EOF'
feat(sketchybar-bridge): wire distributed notifications to sketchybar trigger

The daemon subscribes to the three Phase 1 player notifications
(app.kaset.player.{trackChanged,playbackStateChanged,likeStatusChanged}),
debounces them through NotificationDebouncer (100 ms quiet window),
and emits `sketchybar --trigger kaset_update` once per quiet window.

Logs to stderr so the LaunchAgent's StandardErrorPath captures
operator-readable diagnostics.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: SketchyBar plugin scripts

Six bash scripts. They share a common dependency contract: `osascript`, `jq`, and `curl` must be on `PATH`. `install.sh` (Task 5) checks for these.

**Files:**
- Create: `Scripts/sketchybar/plugins/kaset_update.sh`
- Create: `Scripts/sketchybar/plugins/kaset_artwork.sh`
- Create: `Scripts/sketchybar/plugins/kaset_play_pause.sh`
- Create: `Scripts/sketchybar/plugins/kaset_next.sh`
- Create: `Scripts/sketchybar/plugins/kaset_prev.sh`
- Create: `Scripts/sketchybar/plugins/kaset_seek.sh`

- [ ] **Step 1: Create `kaset_update.sh` (driver)**

This is the script that runs on the `kaset_update` custom event AND on a 1-Hz `update_freq` (so the progress bar advances between events). It pulls full state from Kaset and pushes it into every item in one batch. It also delegates to `kaset_artwork.sh` when the video ID changes.

Create `Scripts/sketchybar/plugins/kaset_update.sh`:

```bash
#!/usr/bin/env bash
# Reads Kaset's current player state and pushes it to every kaset.* item.
# Triggered by the kaset_update custom event AND by a 1-Hz update_freq.
set -euo pipefail

PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins/kaset"
LAST_VIDEO_FILE="${TMPDIR:-/tmp}/kaset-sketchybar-last-video.txt"

INFO=$(osascript -e 'tell application "Kaset" to get player info' 2>/dev/null) || INFO='{}'

# Parse JSON. `// empty` falls back to empty string for missing keys.
NAME=$(printf '%s' "$INFO"      | jq -r '.currentTrack.name      // ""')
ARTIST=$(printf '%s' "$INFO"    | jq -r '.currentTrack.artist    // ""')
VIDEO_ID=$(printf '%s' "$INFO"  | jq -r '.currentTrack.videoId   // ""')
ARTWORK_URL=$(printf '%s' "$INFO" | jq -r '.currentTrack.artworkURL // ""')
DURATION=$(printf '%s' "$INFO"  | jq -r '.duration               // 0')
POSITION=$(printf '%s' "$INFO"  | jq -r '.position               // 0')
IS_PLAYING=$(printf '%s' "$INFO" | jq -r '.isPlaying             // false')

# Format seconds → "M:SS".
fmt_time() {
    local secs=${1%.*}                 # drop fractional part
    [[ -z "$secs" || "$secs" == "null" ]] && secs=0
    printf '%d:%02d' $((secs/60)) $((secs%60))
}

TIME_LABEL="$(fmt_time "$POSITION") / $(fmt_time "$DURATION")"

# Progress percentage 0..100. awk handles floats safely.
if [[ "$DURATION" != "0" && "$DURATION" != "null" && -n "$DURATION" ]]; then
    PCT=$(awk -v p="$POSITION" -v d="$DURATION" 'BEGIN { printf "%d", (p / d) * 100 }')
else
    PCT=0
fi

# Play/pause icon. SF Symbols glyphs by default; ASCII fallback via env vars.
if [[ "$IS_PLAYING" == "true" ]]; then
    PLAY_ICON="${KASET_ICON_PAUSE:-⏸}"
else
    PLAY_ICON="${KASET_ICON_PLAY:-▶}"
fi

# Title — empty string when no track is loaded.
if [[ -z "$NAME" ]]; then
    TITLE="—"
elif [[ -n "$ARTIST" ]]; then
    TITLE="$NAME — $ARTIST"
else
    TITLE="$NAME"
fi

sketchybar --set kaset.title       label="$TITLE" \
           --set kaset.time        label="$TIME_LABEL" \
           --set kaset.progress    slider.percentage="$PCT" \
           --set kaset.play_pause  icon="$PLAY_ICON"

# Refresh artwork only when the video ID actually changes.
LAST_VIDEO=""
[[ -f "$LAST_VIDEO_FILE" ]] && LAST_VIDEO=$(cat "$LAST_VIDEO_FILE")

if [[ "$VIDEO_ID" != "$LAST_VIDEO" ]]; then
    printf '%s' "$VIDEO_ID" > "$LAST_VIDEO_FILE"
    if [[ -n "$VIDEO_ID" && -n "$ARTWORK_URL" ]]; then
        "$PLUGIN_DIR/kaset_artwork.sh" "$VIDEO_ID" "$ARTWORK_URL" || true
    else
        sketchybar --set kaset.artwork background.image=
    fi
fi
```

- [ ] **Step 2: Create `kaset_artwork.sh`**

```bash
#!/usr/bin/env bash
# Downloads artworkURL → ~/.cache/kaset-sketchybar/artwork-<videoId>.jpg
# (skipping the download if the file already exists), then sets the
# kaset.artwork item's background image. Called by kaset_update.sh
# only when the video ID changes.
set -euo pipefail

VIDEO_ID="${1:-}"
ARTWORK_URL="${2:-}"

if [[ -z "$VIDEO_ID" || -z "$ARTWORK_URL" ]]; then
    exit 0
fi

CACHE_DIR="$HOME/.cache/kaset-sketchybar"
mkdir -p "$CACHE_DIR"

# Evict files older than 30 days. Best effort — failure is non-fatal.
find "$CACHE_DIR" -type f -mtime +30 -delete 2>/dev/null || true

ARTWORK_FILE="$CACHE_DIR/artwork-${VIDEO_ID}.jpg"

if [[ ! -f "$ARTWORK_FILE" ]]; then
    if ! curl -fsSL --max-time 5 -o "$ARTWORK_FILE" "$ARTWORK_URL"; then
        rm -f "$ARTWORK_FILE"
        exit 0
    fi
fi

sketchybar --set kaset.artwork background.image="$ARTWORK_FILE" \
                                background.image.scale=0.15
```

- [ ] **Step 3: Create the click-handler one-liners**

`Scripts/sketchybar/plugins/kaset_play_pause.sh`:

```bash
#!/usr/bin/env bash
osascript -e 'tell application "Kaset" to playpause'
```

`Scripts/sketchybar/plugins/kaset_next.sh`:

```bash
#!/usr/bin/env bash
osascript -e 'tell application "Kaset" to next track'
```

`Scripts/sketchybar/plugins/kaset_prev.sh`:

```bash
#!/usr/bin/env bash
osascript -e 'tell application "Kaset" to previous track'
```

- [ ] **Step 4: Create `kaset_seek.sh`**

```bash
#!/usr/bin/env bash
# Slider click handler. SketchyBar passes the click position as
# $PERCENTAGE (0..100). We compute the target seconds from the current
# duration and dispatch it via the AppleScript `seek to N` command.
set -euo pipefail

PERCENTAGE="${PERCENTAGE:-0}"

DURATION=$(osascript -e 'tell application "Kaset" to get player info' 2>/dev/null \
    | jq -r '.duration // 0')

if [[ "$DURATION" == "0" || "$DURATION" == "null" || -z "$DURATION" ]]; then
    exit 0
fi

TARGET=$(awk -v p="$PERCENTAGE" -v d="$DURATION" 'BEGIN { printf "%d", (p / 100.0) * d }')

osascript -e "tell application \"Kaset\" to seek to $TARGET"
```

- [ ] **Step 5: Make all six scripts executable**

```bash
chmod +x Scripts/sketchybar/plugins/*.sh
```

- [ ] **Step 6: Run shellcheck on all six**

```bash
shellcheck Scripts/sketchybar/plugins/*.sh
```
Expected: no warnings. If `shellcheck` is not on the local PATH, install it (`brew install shellcheck`) — or skip and rely on CI to lint. Do not silence shellcheck warnings without a comment explaining why.

- [ ] **Step 7: Commit**

```bash
git add Scripts/sketchybar/plugins/
git commit -m "$(cat <<'EOF'
feat(sketchybar): add plugin scripts for kaset widget

Six bash scripts wire SketchyBar items to Kaset via osascript:

- kaset_update.sh: driver — runs on kaset_update event and at 1Hz,
  reads `get player info` JSON, updates title/time/progress/play-pause
  icon in one batch, delegates to kaset_artwork.sh on track change
- kaset_artwork.sh: downloads artworkURL to ~/.cache/kaset-sketchybar
  (cached by videoId, evicts files older than 30 days), sets the
  kaset.artwork item's background image
- kaset_play_pause.sh / kaset_next.sh / kaset_prev.sh: button click
  handlers
- kaset_seek.sh: slider click handler — converts $PERCENTAGE to
  seconds via duration and dispatches the new `seek to N` command

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: SketchyBar config example (`sketchybarrc.example`)

A copy-pasteable block users add to their `sketchybarrc` (or `source` from it). Defines all six items, subscribes them to the `kaset_update` custom event, and assigns the 1-Hz driver script to one item.

**Files:**
- Create: `Scripts/sketchybar/sketchybarrc.example`

- [ ] **Step 1: Write the example**

Create `Scripts/sketchybar/sketchybarrc.example`:

```bash
# ─── Kaset music widget ──────────────────────────────────────────────
# Source this from your sketchybarrc, or paste these lines into it.
# Plugins are expected at $PLUGIN_DIR (default: ~/.config/sketchybar/plugins/kaset).
# Customize colors/positions/widths to taste.

KASET_PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins/kaset"

# Album art (background-image item; set by kaset_artwork.sh when track changes)
sketchybar --add item kaset.artwork right \
           --set kaset.artwork \
                 background.image.scale=0.15 \
                 background.color=0x00000000 \
                 padding_left=4 padding_right=4

# Track + artist label
sketchybar --add item kaset.title right \
           --set kaset.title \
                 label.font="SF Pro:Semibold:13.0" \
                 max_label_chars=30 \
                 padding_left=4 padding_right=8 \
           --subscribe kaset.title kaset_update

# Previous-track button
sketchybar --add item kaset.prev right \
           --set kaset.prev \
                 icon="⏮" \
                 click_script="$KASET_PLUGIN_DIR/kaset_prev.sh" \
                 padding_left=2 padding_right=2

# Play / pause button — also acts as the 1-Hz driver that re-fetches state.
# Every other kaset.* item re-renders on the kaset_update event this
# script publishes via `sketchybar --set` calls.
sketchybar --add item kaset.play_pause right \
           --set kaset.play_pause \
                 icon="▶" \
                 click_script="$KASET_PLUGIN_DIR/kaset_play_pause.sh" \
                 script="$KASET_PLUGIN_DIR/kaset_update.sh" \
                 update_freq=1 \
                 padding_left=2 padding_right=2 \
           --subscribe kaset.play_pause kaset_update

# Next-track button
sketchybar --add item kaset.next right \
           --set kaset.next \
                 icon="⏭" \
                 click_script="$KASET_PLUGIN_DIR/kaset_next.sh" \
                 padding_left=2 padding_right=2

# Progress slider — clicking sets the target via kaset_seek.sh
sketchybar --add slider kaset.progress right 100 \
           --set kaset.progress \
                 slider.percentage=0 \
                 slider.background.height=2 \
                 click_script="$KASET_PLUGIN_DIR/kaset_seek.sh" \
                 padding_left=4 padding_right=4 \
           --subscribe kaset.progress kaset_update

# Position / duration label, e.g. "1:23 / 3:45"
sketchybar --add item kaset.time right \
           --set kaset.time \
                 label="—:— / —:—" \
                 label.font="SF Mono:Regular:11.0" \
                 padding_left=4 padding_right=8 \
           --subscribe kaset.time kaset_update

# ─── ASCII fallback icons ────────────────────────────────────────────
# If you don't have SF Pro installed in SketchyBar, override with:
#   sketchybar --set kaset.prev       icon="<<"
#   sketchybar --set kaset.next       icon=">>"
#   export KASET_ICON_PLAY="|>"   # picked up by kaset_update.sh
#   export KASET_ICON_PAUSE="||"
```

- [ ] **Step 2: Commit**

```bash
git add Scripts/sketchybar/sketchybarrc.example
git commit -m "$(cat <<'EOF'
feat(sketchybar): add sketchybarrc.example with kaset widget items

Copy-pasteable item definitions for the user's sketchybarrc — six
items (artwork, title, prev, play_pause, next, progress, time), all
subscribed to the kaset_update custom event. The play_pause item
carries the 1-Hz driver script that re-fetches state and pushes
updates to every sibling.

Includes commented ASCII-fallback overrides for users who don't have
SF Pro registered in SketchyBar.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: LaunchAgent + install/uninstall scripts

Wires everything together: builds the bridge, copies binary + plugins to standard locations, registers the LaunchAgent so the bridge starts at login.

**Files:**
- Create: `Scripts/sketchybar/launchagent/app.kaset.sketchybar-bridge.plist`
- Create: `Scripts/sketchybar/install.sh`
- Create: `Scripts/sketchybar/uninstall.sh`

- [ ] **Step 1: Create the LaunchAgent plist template**

Create `Scripts/sketchybar/launchagent/app.kaset.sketchybar-bridge.plist`. The two `__PLACEHOLDER__` strings are substituted by `install.sh`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>app.kaset.sketchybar-bridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>__INSTALL_PATH__</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>__LOG_PATH__</string>
    <key>StandardErrorPath</key>
    <string>__LOG_PATH__</string>
</dict>
</plist>
```

- [ ] **Step 2: Create `install.sh`**

```bash
#!/usr/bin/env bash
# Installs the kaset-sketchybar-bridge daemon and SketchyBar plugin
# scripts. Builds the binary in release mode, copies files to standard
# user locations, and registers the LaunchAgent so the bridge starts at
# login.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins/kaset"
LOG_DIR="$HOME/.local/share/kaset"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCHAGENT_LABEL="app.kaset.sketchybar-bridge"
LAUNCHAGENT_PLIST="$LAUNCHAGENT_DIR/${LAUNCHAGENT_LABEL}.plist"
LOG_PATH="$LOG_DIR/sketchybar-bridge.log"
BIN_PATH="$BIN_DIR/kaset-sketchybar-bridge"

# ── Dependency check ──────────────────────────────────────────────────
missing=()
for cmd in sketchybar jq curl; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
if (( ${#missing[@]} > 0 )); then
    echo "ERROR: missing required tools: ${missing[*]}"
    echo "Install with:"
    for cmd in "${missing[@]}"; do
        case "$cmd" in
            sketchybar) echo "  brew tap FelixKratz/formulae && brew install sketchybar" ;;
            jq)         echo "  brew install jq" ;;
            curl)       echo "  curl is normally included with macOS — check your PATH." ;;
        esac
    done
    exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────
echo "🔨 Building kaset-sketchybar-bridge (release)…"
cd "$ROOT"
swift build -c release --product kaset-sketchybar-bridge

# ── Install binary ────────────────────────────────────────────────────
echo "📦 Installing binary → $BIN_PATH"
mkdir -p "$BIN_DIR"
cp ".build/release/kaset-sketchybar-bridge" "$BIN_PATH"
chmod +x "$BIN_PATH"

# ── Install plugin scripts ────────────────────────────────────────────
echo "📜 Installing plugins → $PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
cp "$ROOT/Scripts/sketchybar/plugins/"*.sh "$PLUGIN_DIR/"
chmod +x "$PLUGIN_DIR/"*.sh

# ── Log dir ───────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

# ── LaunchAgent ───────────────────────────────────────────────────────
echo "🚀 Installing LaunchAgent…"
mkdir -p "$LAUNCHAGENT_DIR"
sed -e "s|__INSTALL_PATH__|$BIN_PATH|g" \
    -e "s|__LOG_PATH__|$LOG_PATH|g" \
    "$ROOT/Scripts/sketchybar/launchagent/${LAUNCHAGENT_LABEL}.plist" \
    > "$LAUNCHAGENT_PLIST"

# Reload if already loaded (idempotent install).
launchctl bootout "gui/$(id -u)/${LAUNCHAGENT_LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCHAGENT_PLIST"

cat <<MSG

✅ Bridge installed.

Next steps:
  1. Add the kaset widget items to your sketchybarrc. Either:
       source $ROOT/Scripts/sketchybar/sketchybarrc.example
     or copy the contents into your sketchybarrc directly.
  2. Reload SketchyBar: sketchybar --reload

Logs:  tail -f $LOG_PATH
Bridge status:  launchctl print gui/\$(id -u)/${LAUNCHAGENT_LABEL}
MSG
```

- [ ] **Step 3: Create `uninstall.sh`**

```bash
#!/usr/bin/env bash
# Reverses install.sh. Leaves the user's sketchybarrc alone — they
# can remove the kaset widget items themselves.
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins/kaset"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCHAGENT_LABEL="app.kaset.sketchybar-bridge"
LAUNCHAGENT_PLIST="$LAUNCHAGENT_DIR/${LAUNCHAGENT_LABEL}.plist"

echo "🛑 Unloading LaunchAgent…"
launchctl bootout "gui/$(id -u)/${LAUNCHAGENT_LABEL}" 2>/dev/null || true
rm -f "$LAUNCHAGENT_PLIST"

echo "🧹 Removing binary…"
rm -f "$BIN_DIR/kaset-sketchybar-bridge"

echo "🧹 Removing plugin scripts…"
rm -rf "$PLUGIN_DIR"

cat <<MSG

✅ Bridge uninstalled.

Note: I did NOT touch your sketchybarrc. To fully remove the widget:
  1. Delete the kaset.* item lines (or the source line that pulls in
     sketchybarrc.example).
  2. Reload SketchyBar: sketchybar --reload

Cache (~/.cache/kaset-sketchybar) and logs (~/.local/share/kaset) were
left in place. Remove them yourself if desired.
MSG
```

- [ ] **Step 4: Make the scripts executable**

```bash
chmod +x Scripts/sketchybar/install.sh Scripts/sketchybar/uninstall.sh
```

- [ ] **Step 5: Run shellcheck on the install scripts**

```bash
shellcheck Scripts/sketchybar/install.sh Scripts/sketchybar/uninstall.sh
```
Expected: no warnings.

- [ ] **Step 6: Commit**

```bash
git add Scripts/sketchybar/launchagent/ Scripts/sketchybar/install.sh Scripts/sketchybar/uninstall.sh
git commit -m "$(cat <<'EOF'
feat(sketchybar): add LaunchAgent template + install/uninstall scripts

install.sh checks for sketchybar/jq/curl on PATH, builds the bridge
in release, copies the binary to ~/.local/bin, plugins to
~/.config/sketchybar/plugins/kaset, and renders + bootstraps the
LaunchAgent at ~/Library/LaunchAgents/app.kaset.sketchybar-bridge.plist
so the daemon starts at login.

uninstall.sh undoes those file/launchctl operations. Both scripts
deliberately leave the user's sketchybarrc, the artwork cache, and
the log directory in place.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Documentation (`docs/sketchybar.md`)

User-facing setup guide.

**Files:**
- Create: `docs/sketchybar.md`
- Modify: `README.md`

- [ ] **Step 1: Create `docs/sketchybar.md`**

Create `docs/sketchybar.md`:

````markdown
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
  support (Phase 1 — already on `main`).

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
- **ASCII fallback icons** (no SF Pro registered in SketchyBar):
  ```sh
  sketchybar --set kaset.prev icon="<<"
  sketchybar --set kaset.next icon=">>"
  export KASET_ICON_PLAY="|>"     # picked up by kaset_update.sh
  export KASET_ICON_PAUSE="||"
  ```
- **Custom polling interval**: `kaset_update.sh` is wired to the
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
  `failed to invoke sketchybar` (means `sketchybar` isn't on the
  bridge's `PATH` — log out / log back in to pick up shell config).
- **Click-to-seek doesn't work**: confirm Kaset is on a build that
  includes the `seek to N` AppleScript command (Phase 1, on `main`).

## Uninstall

```sh
./Scripts/sketchybar/uninstall.sh
```

This removes the binary, plugins, and LaunchAgent. Your `sketchybarrc`
edits, artwork cache, and logs are left in place for you to clean up
manually.
````

- [ ] **Step 2: Add a one-line link in `README.md`**

Find a section listing other docs (likely a "Documentation" or "Resources" block) and append a bullet:

```markdown
- [SketchyBar widget](docs/sketchybar.md) — Now Playing widget for the macOS status bar
```

If `README.md` does not have an existing docs section, create one with the same heading style as the surrounding sections — exact placement is fine to leave to taste, since this is primarily a navigation aid.

- [ ] **Step 3: Commit**

```bash
git add docs/sketchybar.md README.md
git commit -m "$(cat <<'EOF'
docs: add SketchyBar widget guide

User-facing setup guide: prerequisites, install steps, what the
widget shows, how it works (bridge + 1Hz driver), customization
(position, colors, fallback icons, polling interval), and
troubleshooting. README links to the new guide.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: End-to-end smoke test + final QA

Pure verification — no code changes (other than fix-ups if something fails). The earlier per-task steps each verified individual pieces; this task confirms the whole thing actually works on a real machine.

**Prerequisites:**
- `sketchybar`, `jq`, and `curl` installed.
- Kaset.app running (most recent build) with at least one playable track loaded.
- A SketchyBar config that you're willing to extend with the widget.

- [ ] **Step 1: Run the install script**

```bash
./Scripts/sketchybar/install.sh
```
Expected: green checks, ends with the "Next steps" message.

- [ ] **Step 2: Verify the LaunchAgent is loaded and the bridge is running**

```bash
launchctl print "gui/$(id -u)/app.kaset.sketchybar-bridge" | head -20
```
Expected: a `state = running` line and the configured stdout/stderr paths.

```bash
tail -n 5 ~/.local/share/kaset/sketchybar-bridge.log
```
Expected: a `kaset-sketchybar-bridge ready, listening for 3 notifications` line.

- [ ] **Step 3: Wire up the example items**

Either `source` `Scripts/sketchybar/sketchybarrc.example` from your `sketchybarrc`, or paste its contents in. Then:

```bash
sketchybar --reload
```

Expected: the six `kaset.*` items appear in the bar. Without a track loaded, they will look empty (title `—`, time `0:00 / 0:00`, no artwork).

- [ ] **Step 4: Live-fire the four user actions**

With Kaset playing a track:

| Action | Expected behavior |
|---|---|
| Click ⏭ in SketchyBar | Track changes in Kaset; SketchyBar artwork + title update within ~200 ms |
| Click ⏯ | Play / pause toggles in Kaset; the play_pause icon flips |
| Click ⏮ | Goes back; matching SketchyBar updates |
| Click anywhere on the progress bar | Kaset jumps to that position; the progress bar reflects the new position |

If any action does NOT update the bar within ~1 second, check the bridge log first:

```bash
tail -f ~/.local/share/kaset/sketchybar-bridge.log
```

- [ ] **Step 5: Verify the bridge is event-driven, not just polling**

Stop SketchyBar's 1-Hz driver temporarily by setting `update_freq=0` on `kaset.play_pause` (in your `sketchybarrc`, then `--reload`). Skip a track. The artwork + title should still update within ~200 ms — that proves the distributed-notification path is wired (since polling is disabled).

Restore `update_freq=1` afterwards so the progress bar resumes advancing.

- [ ] **Step 6: Run the full unit suite once more**

```bash
swift test --skip KasetUITests
```
Expected: all tests still pass (Phase 1 + the new `DebouncerTests`).

- [ ] **Step 7: Run shellcheck on every shell script in this PR**

```bash
shellcheck Scripts/sketchybar/install.sh \
           Scripts/sketchybar/uninstall.sh \
           Scripts/sketchybar/plugins/*.sh
```
Expected: no warnings.

- [ ] **Step 8: Sanity-check uninstall**

```bash
./Scripts/sketchybar/uninstall.sh
launchctl print "gui/$(id -u)/app.kaset.sketchybar-bridge" 2>&1 | head -1
ls ~/.local/bin/kaset-sketchybar-bridge 2>&1 | head -1
ls ~/.config/sketchybar/plugins/kaset 2>&1 | head -1
```
Expected: the `launchctl print` errors out (service unloaded), the binary is gone, the plugin dir is gone.

Re-install for daily use:

```bash
./Scripts/sketchybar/install.sh
```

- [ ] **Step 9: Commit any manual fix-ups produced by Steps 1–8**

If Steps 1–7 turned up issues, fix them in their respective task files (do not amend prior commits). Then:

```bash
git add -u
git commit -m "$(cat <<'EOF'
fix(sketchybar): smoke-test fix-ups

[describe the actual fixes here]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If Steps 1–8 all pass cleanly, no commit needed for Task 7.

---

## Out-of-scope / future work

- Volume / shuffle / repeat / mute controls (intentionally not exposed
  in this widget).
- An installer that drops the example into the user's `sketchybarrc`
  automatically (left manual to avoid clobbering existing configs).
- Discord rich-presence integration (uses the same DN payload — separate
  consumer, separate plan).
- Universal binary build of the bridge (host-arch only by default;
  `swift build --arch arm64 --arch x86_64` works for users who need it).
