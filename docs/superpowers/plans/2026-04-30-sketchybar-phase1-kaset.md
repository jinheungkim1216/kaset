# Phase 1 — Kaset App Changes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `seek to N` AppleScript command and broadcast `NSDistributedNotification` events on player track / playback-state / like-status changes, with a payload schema identical to `get player info`.

**Architecture:** Extract a `PlayerStateSnapshot` helper (single source of truth for the JSON shape) used by both `GetPlayerInfoCommand` and the new notification publisher. Add three `Notification.Name` constants (`app.kaset.player.trackChanged`, `app.kaset.player.playbackStateChanged`, `app.kaset.player.likeStatusChanged`) and an injectable static `notificationCenter` (defaults to `DistributedNotificationCenter.default()`, swapped to a fresh `NotificationCenter()` in tests). Trigger notifications via `didSet` on the three observed properties. AppleScript `seek to N` wraps the existing internal `PlayerService.seek(to:)`.

**Tech Stack:** Swift 6, NSScriptCommand (AppleScript), DistributedNotificationCenter, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-04-30-sketchybar-integration-design.md` (Phase 1 sections only).

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Kaset/Services/Scripting/PlayerStateSnapshot.swift` | `@MainActor enum PlayerStateSnapshot` exposing `makePlayerInfoDictionary(from:)` and `makePlayerInfoJSON(from:)`. |
| Modify | `Sources/Kaset/Services/Scripting/ScriptCommands.swift` | (a) Refactor `GetPlayerInfoCommand` to use the helper. (b) Add new `KasetSeekCommand`. |
| Modify | `Sources/Kaset/Resources/Kaset.sdef` | Add `<command name="seek to" code="Kastseek">` entry. |
| Create | `Sources/Kaset/Services/Player/PlayerService+Notifications.swift` | Notification names, injectable `notificationCenter` static, `notifyTrackChanged()` / `notifyPlaybackStateChanged()` / `notifyLikeStatusChanged()` helpers. |
| Modify | `Sources/Kaset/Services/Player/PlayerService.swift` | Add `didSet` observers to `state`, `currentTrack`, `currentTrackLikeStatus` that call the notify helpers when value actually changes. |
| Create | `Tests/KasetTests/PlayerStateSnapshotTests.swift` | Unit tests for the snapshot helper. |
| Modify | `Tests/KasetTests/ScriptCommandsTests.swift` | Add tests for `KasetSeekCommand`. |
| Create | `Tests/KasetTests/PlayerServiceNotificationsTests.swift` | Unit tests for notification publishing (uses a fresh `NotificationCenter()`). |
| Create | `docs/distributed-notifications.md` | Reference doc: notification names, payload schema, Swift / Objective-C / shell subscription examples. |
| Modify | `docs/applescript.md` | Add `seek to N` row + example; add link to `distributed-notifications.md`. |

---

## Task 1: Extract `PlayerStateSnapshot` helper

Pure refactor. `GetPlayerInfoCommand` currently builds its dictionary inline (`Sources/Kaset/Services/Scripting/ScriptCommands.swift:255-318`). We pull that out so the future notification publisher can reuse the exact same schema.

**Files:**
- Create: `Sources/Kaset/Services/Scripting/PlayerStateSnapshot.swift`
- Modify: `Sources/Kaset/Services/Scripting/ScriptCommands.swift` (lines 249-319)
- Test: `Tests/KasetTests/PlayerStateSnapshotTests.swift`

- [ ] **Step 1: Write the failing test for `PlayerStateSnapshot`**

Create `Tests/KasetTests/PlayerStateSnapshotTests.swift`:

```swift
import Foundation
import Testing
@testable import Kaset

@Suite(.serialized, .tags(.service))
@MainActor
struct PlayerStateSnapshotTests {
    @Test("Dictionary has expected top-level keys when no track is loaded")
    func dictionaryWithoutTrack() {
        let service = PlayerService()
        let dict = PlayerStateSnapshot.makePlayerInfoDictionary(from: service)

        #expect(dict["isPlaying"] as? Bool == false)
        #expect(dict["isPaused"] as? Bool == false)
        #expect(dict["position"] as? Double == 0)
        #expect(dict["duration"] as? Double == 0)
        #expect(dict["volume"] as? Int != nil)
        #expect(dict["shuffling"] as? Bool == false)
        #expect(dict["repeating"] as? String == "off")
        #expect(dict["muted"] as? Bool != nil)
        #expect(dict["likeStatus"] as? String == "none")
        #expect(dict["currentTrack"] == nil)
    }

    @Test("Dictionary includes track sub-dictionary when track is set")
    func dictionaryWithTrack() {
        let service = PlayerService()
        service.currentTrack = Song(
            id: "test-id",
            title: "Test Song",
            artists: [Artist(id: "artist-1", name: "Test Artist")],
            album: Album(id: "album-1", title: "Test Album", artists: nil, thumbnailURL: nil, year: nil, trackCount: nil),
            duration: 180,
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            videoId: "test-video-id"
        )

        let dict = PlayerStateSnapshot.makePlayerInfoDictionary(from: service)
        let track = try? #require(dict["currentTrack"] as? [String: Any])

        #expect(track?["name"] as? String == "Test Song")
        #expect(track?["artist"] as? String == "Test Artist")
        #expect(track?["album"] as? String == "Test Album")
        #expect(track?["videoId"] as? String == "test-video-id")
        #expect(track?["duration"] as? TimeInterval == 180)
        #expect(track?["artworkURL"] as? String == "https://example.com/thumb.jpg")
    }

    @Test("JSON output is valid and round-trips to the dictionary")
    func jsonRoundTrip() {
        let service = PlayerService()
        let json = PlayerStateSnapshot.makePlayerInfoJSON(from: service)

        let data = try? #require(json.data(using: .utf8))
        let parsed = try? #require(JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])
        #expect(parsed?["repeating"] as? String == "off")
        #expect(parsed?["likeStatus"] as? String == "none")
    }

    @Test("Repeat mode mapping covers every case")
    func repeatModeMapping() {
        let service = PlayerService()

        let stateAfter: [(advance: Int, expected: String)] = [
            (0, "off"),
            (1, "all"),
            (2, "one"),
            (3, "off"),
        ]

        for (i, expected) in stateAfter {
            // Reset and advance i times
            while service.repeatMode != .off {
                service.cycleRepeatMode()
            }
            for _ in 0..<i { service.cycleRepeatMode() }
            let dict = PlayerStateSnapshot.makePlayerInfoDictionary(from: service)
            #expect(dict["repeating"] as? String == expected, "after \(i) advances")
        }
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
swift test --skip KasetUITests --filter PlayerStateSnapshotTests
```
Expected: build error — `cannot find 'PlayerStateSnapshot' in scope`.

- [ ] **Step 3: Create `PlayerStateSnapshot.swift`**

Create `Sources/Kaset/Services/Scripting/PlayerStateSnapshot.swift`:

```swift
import Foundation

/// Builds JSON-serializable snapshots of the current `PlayerService` state.
///
/// Single source of truth for the schema returned by the `get player info`
/// AppleScript command and used as the `userInfo` payload of player-related
/// distributed notifications. Keeping both producers on the same helper
/// guarantees external consumers see one consistent shape.
@MainActor
enum PlayerStateSnapshot {
    /// Dictionary form. Suitable for `Notification.userInfo` or as input to
    /// `JSONSerialization.data(withJSONObject:)`.
    static func makePlayerInfoDictionary(from playerService: PlayerService) -> [String: Any] {
        let repeatMode = switch playerService.repeatMode {
        case .off: "off"
        case .all: "all"
        case .one: "one"
        }

        let likeStatus = switch playerService.currentTrackLikeStatus {
        case .like: "liked"
        case .dislike: "disliked"
        case .indifferent: "none"
        }

        var info: [String: Any] = [
            "isPlaying": playerService.isPlaying,
            "isPaused": playerService.state == .paused,
            "position": playerService.progress,
            "duration": playerService.duration,
            "volume": Int(playerService.volume * 100),
            "shuffling": playerService.shuffleEnabled,
            "repeating": repeatMode,
            "muted": playerService.isMuted,
            "likeStatus": likeStatus,
        ]

        if let track = playerService.currentTrack {
            info["currentTrack"] = [
                "name": track.title,
                "artist": track.artistsDisplay,
                "album": track.album?.title ?? "",
                "duration": track.duration ?? 0,
                "videoId": track.videoId,
                "artworkURL": track.thumbnailURL?.absoluteString ?? "",
            ]
        }

        return info
    }

    /// JSON-string form. Returns `"{}"` if serialization fails (non-fatal fallback
    /// matching prior `GetPlayerInfoCommand` behavior).
    static func makePlayerInfoJSON(from playerService: PlayerService) -> String {
        let info = Self.makePlayerInfoDictionary(from: playerService)
        guard let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }
}
```

- [ ] **Step 4: Refactor `GetPlayerInfoCommand` to use the helper**

In `Sources/Kaset/Services/Scripting/ScriptCommands.swift`, replace the entire body of `GetPlayerInfoCommand` (the class block starting at the `// MARK: - GetPlayerInfoCommand` section) with:

```swift
// MARK: - GetPlayerInfoCommand

/// GetPlayerInfo command: returns current player state as JSON.
/// Synchronous; returns immediately.
@objc(KasetGetPlayerInfoCommand)
final class GetPlayerInfoCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // AppleScript runs on main thread, so we can assume MainActor isolation.
        let json = MainActor.assumeIsolated { () -> String? in
            guard let playerService = getPlayerService() else {
                logger.error("GetPlayerInfo command failed: PlayerService.shared is nil")
                return nil
            }
            logger.info("Executing getPlayerInfo command")
            return PlayerStateSnapshot.makePlayerInfoJSON(from: playerService)
        }

        guard let json else {
            self.scriptErrorNumber = errPlayerNotAvailable
            self.scriptErrorString = playerNotAvailableMessage
            return "{\"error\": \"Player not available\"}"
        }
        return json
    }
}
```

This preserves the prior public behavior (error JSON + script error code when service is nil) while delegating schema construction to the helper.

- [ ] **Step 5: Run all tests**

```bash
swift test --skip KasetUITests
```
Expected: existing `ScriptCommandsTests` (`getPlayerInfoReturnsErrorWhenNil`, `getPlayerInfoReturnsValidJSON`, `getPlayerInfoIncludesTrackInfo`, `getPlayerInfoReturnsCorrectRepeatMode`) AND the new `PlayerStateSnapshotTests` PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Kaset/Services/Scripting/PlayerStateSnapshot.swift \
        Sources/Kaset/Services/Scripting/ScriptCommands.swift \
        Tests/KasetTests/PlayerStateSnapshotTests.swift
git commit -m "$(cat <<'EOF'
refactor(scripting): extract PlayerStateSnapshot helper

Pulls the dictionary/JSON construction out of GetPlayerInfoCommand so
the upcoming distributed-notification publisher can reuse the same
schema.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `seek to N` AppleScript command

**Files:**
- Modify: `Sources/Kaset/Resources/Kaset.sdef`
- Modify: `Sources/Kaset/Services/Scripting/ScriptCommands.swift` (append new class at the end of the Kaset Suite section, after `DislikeTrackCommand`)
- Modify: `Tests/KasetTests/ScriptCommandsTests.swift`
- Modify: `docs/applescript.md`

- [ ] **Step 1: Write failing tests for `KasetSeekCommand`**

Append to `Tests/KasetTests/ScriptCommandsTests.swift` (inside the existing struct, before its closing brace):

```swift
    // MARK: - SeekCommand Tests

    @Test("Seek sets error when PlayerService is nil")
    func seekSetsErrorWhenNil() {
        PlayerService.shared = nil

        let command = SeekCommand()
        command.directParameter = 30 as NSNumber
        _ = command.performDefaultImplementation()

        #expect(command.scriptErrorNumber == -1728)
        #expect(command.scriptErrorString?.contains("Player service not initialized") == true)
    }

    @Test("Seek sets error for invalid parameter type")
    func seekSetsErrorForInvalidParameter() {
        let playerService = PlayerService()
        PlayerService.shared = playerService

        let command = SeekCommand()
        command.directParameter = "not a number" as NSString
        _ = command.performDefaultImplementation()

        #expect(command.scriptErrorNumber == errAECoercionFail)
        #expect(command.scriptErrorString?.contains("must be a number") == true)

        PlayerService.shared = nil
    }

    @Test("Seek forwards integer parameter to PlayerService.seek(to:)")
    func seekForwardsIntegerParameter() async {
        let playerService = PlayerService()
        // The deferred-restore branch of seek(to:) writes progress synchronously
        // and returns without touching the WebView, which is exactly the path
        // we want to exercise from a unit test.
        playerService.isPendingRestoredLoadDeferred = true
        PlayerService.shared = playerService

        let command = SeekCommand()
        command.directParameter = 42 as NSNumber
        _ = command.performDefaultImplementation()

        let updated = await self.waitUntil { playerService.progress == 42 }
        #expect(updated)
        #expect(playerService.progress == 42)
        #expect(playerService.pendingRestoredSeek == 42)

        PlayerService.shared = nil
    }

    @Test("Seek accepts floating-point parameters")
    func seekAcceptsDoubleParameter() async {
        let playerService = PlayerService()
        playerService.isPendingRestoredLoadDeferred = true
        PlayerService.shared = playerService

        let command = SeekCommand()
        command.directParameter = 12.5 as NSNumber
        _ = command.performDefaultImplementation()

        let updated = await self.waitUntil { playerService.progress == 12.5 }
        #expect(updated)
        #expect(playerService.progress == 12.5)

        PlayerService.shared = nil
    }
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --skip KasetUITests --filter ScriptCommandsTests
```
Expected: build error — `cannot find 'SeekCommand' in scope`.

- [ ] **Step 3: Add the sdef entry**

In `Sources/Kaset/Resources/Kaset.sdef`, insert this command inside the `<suite name="Kaset Suite" code="Kast" ...>` block, immediately after the `set volume` command (line 46) and before `toggle shuffle`:

```xml
        <command name="seek to" code="Kastseek" description="Seek the current track to a specific position in seconds.">
            <cocoa class="KasetSeekCommand"/>
            <direct-parameter type="number" description="Target position in seconds (0 to track duration)."/>
        </command>
```

Note the four-character `code` `Kastseek` follows the existing `Kast<verb>` convention.

- [ ] **Step 4: Add `SeekCommand` to `ScriptCommands.swift`**

Append at the very end of `Sources/Kaset/Services/Scripting/ScriptCommands.swift`:

```swift
// MARK: - SeekCommand

/// Seek command: jumps the current track to a specific position in seconds.
@objc(KasetSeekCommand)
final class SeekCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let number = self.directParameter as? NSNumber else {
            logger.error("Seek command failed: invalid position parameter")
            self.scriptErrorNumber = errAECoercionFail
            self.scriptErrorString = "Position must be a number (seconds)."
            return nil
        }

        let position = number.doubleValue

        guard let playerService = MainActor.assumeIsolated({ getPlayerService() }) else {
            logger.error("Seek command failed: PlayerService.shared is nil")
            self.scriptErrorNumber = errPlayerNotAvailable
            self.scriptErrorString = playerNotAvailableMessage
            return nil
        }
        logger.info("Executing seek command to \(position)s")
        Task { @MainActor in
            await playerService.seek(to: position)
        }
        return nil
    }
}
```

`as? NSNumber` accepts both integer and floating-point AppleScript numerics, matching the `<direct-parameter type="number">` declaration. Clamping is handled inside `PlayerService.seek(to:)`.

- [ ] **Step 5: Run tests to confirm they pass**

```bash
swift test --skip KasetUITests --filter ScriptCommandsTests
```
Expected: PASS for the four new test cases plus all pre-existing ScriptCommands tests.

- [ ] **Step 6: Update `docs/applescript.md`**

In `docs/applescript.md`, find the commands table (lines 7-20) and insert this row after the `previous track` row:

```markdown
| `seek to N` | Seek to position N (seconds) |
```

Then add an example under `## Examples`, after the existing "Basic Playback Control" block:

````markdown
### Seek to a Position

```applescript
tell application "Kaset"
    seek to 90
end tell
```

```bash
osascript -e 'tell application "Kaset" to seek to 90'
```

The position is clamped to `[0, duration]`. Floating-point seconds are accepted.
````

- [ ] **Step 7: Commit**

```bash
git add Sources/Kaset/Resources/Kaset.sdef \
        Sources/Kaset/Services/Scripting/ScriptCommands.swift \
        Tests/KasetTests/ScriptCommandsTests.swift \
        docs/applescript.md
git commit -m "$(cat <<'EOF'
feat(scripting): add `seek to N` AppleScript command

Wraps PlayerService.seek(to:) so external callers (Raycast, Alfred,
Shortcuts, SketchyBar plugins) can jump to a specific position in
seconds. Position is clamped inside PlayerService.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Distributed Notifications publishing

Add three notification names + helpers, and trigger them from `didSet` on the three observed `PlayerService` properties.

**Files:**
- Create: `Sources/Kaset/Services/Player/PlayerService+Notifications.swift`
- Modify: `Sources/Kaset/Services/Player/PlayerService.swift` (lines 46, 49, 131 — convert plain `var` to `var ... { didSet { ... } }`)
- Test: `Tests/KasetTests/PlayerServiceNotificationsTests.swift`

- [ ] **Step 1: Write failing notification tests**

Create `Tests/KasetTests/PlayerServiceNotificationsTests.swift`:

```swift
import Foundation
import Testing
@testable import Kaset

@Suite(.serialized, .tags(.service))
@MainActor
struct PlayerServiceNotificationsTests {
    /// Each test gets its own in-process NotificationCenter so we don't depend on
    /// the system distnoted daemon and so observers from sibling tests can't leak.
    init() {
        PlayerService.shared = nil
        PlayerService.notificationCenter = NotificationCenter()
    }

    // MARK: - trackChanged

    @Test("Setting a different track posts trackChanged with rich userInfo")
    func trackChangedFiresOnNewTrack() {
        let service = PlayerService()
        var received: Notification?

        let observer = PlayerService.notificationCenter.addObserver(
            forName: PlayerService.PlayerNotification.trackChanged,
            object: nil,
            queue: nil
        ) { received = $0 }
        defer { PlayerService.notificationCenter.removeObserver(observer) }

        service.currentTrack = Song(
            id: "id-1",
            title: "Song A",
            artists: [Artist(id: "a", name: "Artist A")],
            album: nil,
            duration: 200,
            thumbnailURL: URL(string: "https://example.com/a.jpg"),
            videoId: "video-a"
        )

        let info = try? #require(received?.userInfo as? [String: Any])
        let track = try? #require(info?["currentTrack"] as? [String: Any])
        #expect(track?["videoId"] as? String == "video-a")
        #expect(track?["name"] as? String == "Song A")
        #expect(info?["isPlaying"] as? Bool == false)
    }

    @Test("Setting same videoId does not re-post trackChanged")
    func trackChangedSuppressesIdenticalTrack() {
        let service = PlayerService()
        let song = Song(
            id: "id-1",
            title: "Song A",
            artists: [],
            album: nil,
            duration: 200,
            thumbnailURL: nil,
            videoId: "video-a"
        )
        service.currentTrack = song

        var count = 0
        let observer = PlayerService.notificationCenter.addObserver(
            forName: PlayerService.PlayerNotification.trackChanged,
            object: nil,
            queue: nil
        ) { _ in count += 1 }
        defer { PlayerService.notificationCenter.removeObserver(observer) }

        // Re-assign with same videoId -> should be a no-op.
        service.currentTrack = song
        #expect(count == 0)

        // Different videoId -> should fire.
        service.currentTrack = Song(
            id: "id-2",
            title: "Song B",
            artists: [],
            album: nil,
            duration: 200,
            thumbnailURL: nil,
            videoId: "video-b"
        )
        #expect(count == 1)

        // Going back to nil -> should fire (nil ⇄ non-nil counts as a change).
        service.currentTrack = nil
        #expect(count == 2)
    }

    // MARK: - playbackStateChanged

    @Test("Changing state posts playbackStateChanged with current snapshot")
    func playbackStateChangedFires() {
        let service = PlayerService()
        var received: Notification?

        let observer = PlayerService.notificationCenter.addObserver(
            forName: PlayerService.PlayerNotification.playbackStateChanged,
            object: nil,
            queue: nil
        ) { received = $0 }
        defer { PlayerService.notificationCenter.removeObserver(observer) }

        service.state = .playing

        let info = try? #require(received?.userInfo as? [String: Any])
        #expect(info?["isPlaying"] as? Bool == true)
        #expect(info?["isPaused"] as? Bool == false)
    }

    @Test("Reassigning the same state does not re-post")
    func playbackStateChangedSuppressesNoOp() {
        let service = PlayerService()
        service.state = .playing

        var count = 0
        let observer = PlayerService.notificationCenter.addObserver(
            forName: PlayerService.PlayerNotification.playbackStateChanged,
            object: nil,
            queue: nil
        ) { _ in count += 1 }
        defer { PlayerService.notificationCenter.removeObserver(observer) }

        service.state = .playing
        #expect(count == 0)
        service.state = .paused
        #expect(count == 1)
    }

    // MARK: - likeStatusChanged

    @Test("Changing like status posts likeStatusChanged")
    func likeStatusChangedFires() {
        let service = PlayerService()
        var received: Notification?

        let observer = PlayerService.notificationCenter.addObserver(
            forName: PlayerService.PlayerNotification.likeStatusChanged,
            object: nil,
            queue: nil
        ) { received = $0 }
        defer { PlayerService.notificationCenter.removeObserver(observer) }

        service.currentTrackLikeStatus = .like

        let info = try? #require(received?.userInfo as? [String: Any])
        #expect(info?["likeStatus"] as? String == "liked")
    }

    @Test("Reassigning same like status does not re-post")
    func likeStatusChangedSuppressesNoOp() {
        let service = PlayerService()
        service.currentTrackLikeStatus = .like

        var count = 0
        let observer = PlayerService.notificationCenter.addObserver(
            forName: PlayerService.PlayerNotification.likeStatusChanged,
            object: nil,
            queue: nil
        ) { _ in count += 1 }
        defer { PlayerService.notificationCenter.removeObserver(observer) }

        service.currentTrackLikeStatus = .like
        #expect(count == 0)
        service.currentTrackLikeStatus = .indifferent
        #expect(count == 1)
    }

    // MARK: - default center

    @Test("Default notificationCenter is the distributed one")
    func defaultNotificationCenterIsDistributed() {
        // Reset to default to verify the production wiring.
        PlayerService.notificationCenter = DistributedNotificationCenter.default()
        #expect(PlayerService.notificationCenter is DistributedNotificationCenter)
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
swift test --skip KasetUITests --filter PlayerServiceNotificationsTests
```
Expected: build error — `cannot find 'PlayerNotification' in scope` and `'notificationCenter' is not a member of PlayerService`.

- [ ] **Step 3: Create `PlayerService+Notifications.swift`**

Create `Sources/Kaset/Services/Player/PlayerService+Notifications.swift`:

```swift
import Foundation

extension PlayerService {
    /// Distributed notification names broadcast when player state mutates.
    /// External subscribers (e.g. SketchyBar bridge) listen on
    /// `DistributedNotificationCenter.default()`.
    enum PlayerNotification {
        /// Posted when `currentTrack` changes (videoId differs, including nil ⇄ non-nil).
        public static let trackChanged = Notification.Name("app.kaset.player.trackChanged")

        /// Posted when `state` transitions (loading / playing / paused / etc.).
        public static let playbackStateChanged = Notification.Name("app.kaset.player.playbackStateChanged")

        /// Posted when `currentTrackLikeStatus` changes.
        public static let likeStatusChanged = Notification.Name("app.kaset.player.likeStatusChanged")
    }

    /// Notification center used to broadcast player events.
    /// Defaults to `DistributedNotificationCenter.default()` so external
    /// processes can subscribe. Tests replace with a fresh `NotificationCenter()`
    /// to avoid crossing process boundaries via distnoted.
    static var notificationCenter: NotificationCenter = DistributedNotificationCenter.default()

    func notifyTrackChanged() {
        let userInfo = PlayerStateSnapshot.makePlayerInfoDictionary(from: self)
        Self.notificationCenter.post(
            name: PlayerNotification.trackChanged,
            object: nil,
            userInfo: userInfo
        )
    }

    func notifyPlaybackStateChanged() {
        let userInfo = PlayerStateSnapshot.makePlayerInfoDictionary(from: self)
        Self.notificationCenter.post(
            name: PlayerNotification.playbackStateChanged,
            object: nil,
            userInfo: userInfo
        )
    }

    func notifyLikeStatusChanged() {
        let userInfo = PlayerStateSnapshot.makePlayerInfoDictionary(from: self)
        Self.notificationCenter.post(
            name: PlayerNotification.likeStatusChanged,
            object: nil,
            userInfo: userInfo
        )
    }
}
```

> If Swift 6 strict concurrency rejects the `static var notificationCenter` declaration as "global mutable state", make it `nonisolated(unsafe) static var notificationCenter`. Access in production and tests is always serialized through `MainActor` (PlayerService is `@MainActor`-isolated and tests are `@MainActor`), so the `unsafe` annotation is justified.

- [ ] **Step 4: Add `didSet` observers in `PlayerService.swift`**

In `Sources/Kaset/Services/Player/PlayerService.swift`, replace the three plain stored declarations with versions that have a `didSet` body. They live alongside the existing `currentIndex`, `showLyrics`, `showQueue` declarations that already use the same `didSet` pattern, so this fits the file conventions.

Replace line 46:

```swift
    var state: PlaybackState = .idle
```

with:

```swift
    var state: PlaybackState = .idle {
        didSet {
            if oldValue != self.state {
                self.notifyPlaybackStateChanged()
            }
        }
    }
```

Replace line 49:

```swift
    var currentTrack: Song?
```

with:

```swift
    var currentTrack: Song? {
        didSet {
            if oldValue?.videoId != self.currentTrack?.videoId {
                self.notifyTrackChanged()
            }
        }
    }
```

Replace line 131:

```swift
    var currentTrackLikeStatus: LikeStatus = .indifferent
```

with:

```swift
    var currentTrackLikeStatus: LikeStatus = .indifferent {
        didSet {
            if oldValue != self.currentTrackLikeStatus {
                self.notifyLikeStatusChanged()
            }
        }
    }
```

> Comparing `videoId` (not full `Song` equality) for `currentTrack` avoids spurious notifications when metadata enrichment re-assigns the same logical track with newly fetched fields. `PlaybackState` and `LikeStatus` are both `Equatable`, so `oldValue != self.<prop>` is straightforward.

- [ ] **Step 5: Run all tests**

```bash
swift test --skip KasetUITests
```
Expected: PASS for the new `PlayerServiceNotificationsTests` plus all existing tests (existing tests do not subscribe to the static notification center, so swapping it has no side-effects on them; but verify by running the full suite).

- [ ] **Step 6: Commit**

```bash
git add Sources/Kaset/Services/Player/PlayerService+Notifications.swift \
        Sources/Kaset/Services/Player/PlayerService.swift \
        Tests/KasetTests/PlayerServiceNotificationsTests.swift
git commit -m "$(cat <<'EOF'
feat(player): broadcast distributed notifications on player events

Adds three Notification.Name constants (app.kaset.player.{trackChanged,
playbackStateChanged,likeStatusChanged}) posted via
DistributedNotificationCenter when the corresponding PlayerService
property changes. userInfo carries the same payload schema as the
`get player info` AppleScript command (PlayerStateSnapshot helper).

A swappable static notificationCenter lets tests intercept events
without crossing process boundaries.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Documentation — `distributed-notifications.md`

**Files:**
- Create: `docs/distributed-notifications.md`
- Modify: `docs/applescript.md` (footer cross-link)

- [ ] **Step 1: Write `docs/distributed-notifications.md`**

Create `docs/distributed-notifications.md`:

````markdown
# Distributed Notifications

Kaset broadcasts player-state events on `DistributedNotificationCenter.default()`,
so other processes (status-bar widgets, rich-presence integrations, custom
scripts) can react in real time without polling AppleScript.

## Notification Names

| Name | Posted when |
| ---- | ----------- |
| `app.kaset.player.trackChanged` | `currentTrack` becomes a different track (videoId differs, including nil ⇄ non-nil). |
| `app.kaset.player.playbackStateChanged` | Playback state transitions (loading / playing / paused / buffering / ended / idle / error). |
| `app.kaset.player.likeStatusChanged` | Like status of the current track changes. |

All three notifications carry a `userInfo` dictionary whose schema matches the
JSON returned by the AppleScript `get player info` command. See
[applescript.md](applescript.md) for the schema.

## Subscribing — Swift

```swift
import Foundation

let center = DistributedNotificationCenter.default()
center.addObserver(
    forName: Notification.Name("app.kaset.player.trackChanged"),
    object: nil,
    queue: .main
) { notification in
    guard let info = notification.userInfo,
          let track = info["currentTrack"] as? [String: Any]
    else { return }
    print("Now playing: \(track["name"] ?? "")")
}

RunLoop.main.run()
```

## Subscribing — Objective-C

```objective-c
[[NSDistributedNotificationCenter defaultCenter]
    addObserverForName:@"app.kaset.player.trackChanged"
                object:nil
                 queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
    NSDictionary *track = note.userInfo[@"currentTrack"];
    NSLog(@"Now playing: %@", track[@"name"]);
}];
```

## Subscribing — Shell (one-off, blocking)

There is no built-in macOS CLI tool for subscribing to distributed
notifications, but a tiny Swift script works as a daemon:

```bash
cat > /tmp/kaset-watch.swift <<'EOF'
import Foundation

let center = DistributedNotificationCenter.default()
for name in [
    "app.kaset.player.trackChanged",
    "app.kaset.player.playbackStateChanged",
    "app.kaset.player.likeStatusChanged",
] {
    center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { n in
        let info = n.userInfo ?? [:]
        let data = try? JSONSerialization.data(withJSONObject: info)
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        print("\(name) \(json)")
    }
}
RunLoop.main.run()
EOF
swift /tmp/kaset-watch.swift
```

## Notes

- Notifications fire only when the value actually changes (no-op writes are suppressed).
- Volume / shuffle / repeat / mute are NOT broadcast — query `get player info` if you need them.
- Distributed notifications are best-effort and may be coalesced under load. Treat them as "something changed; re-read state" rather than as a reliable event log.
- The `userInfo` payload is identical to the JSON returned by `tell application "Kaset" to get player info`.

## See Also

- [AppleScript Support](applescript.md) — commands and the `get player info` schema.
````

- [ ] **Step 2: Add a cross-link in `applescript.md`**

Append at the very end of `docs/applescript.md`:

```markdown

## See Also

- [Distributed Notifications](distributed-notifications.md) — push-style player events for processes that want to react without polling.
```

- [ ] **Step 3: Commit**

```bash
git add docs/distributed-notifications.md docs/applescript.md
git commit -m "$(cat <<'EOF'
docs: add distributed notifications reference

Documents the three player-event Notification.Names, the userInfo
schema (mirrors `get player info`), and Swift / Objective-C / shell
subscription examples.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Final QA pass

- [ ] **Step 1: Run SwiftLint**

```bash
swiftlint --strict
```
Expected: no violations. If any new file triggers warnings, fix them in the corresponding file before continuing.

- [ ] **Step 2: Run SwiftFormat**

```bash
swiftformat .
```
Expected: minimal or no changes (the project's `--self insert` rule may rewrite calls inside the new files; commit any cleanup it produces).

- [ ] **Step 3: Build**

```bash
swift build
```
Expected: success with no warnings about strict concurrency.

- [ ] **Step 4: Full unit test run**

```bash
swift test --skip KasetUITests
```
Expected: every existing test still PASSes; new tests PASS.

- [ ] **Step 5: Commit any formatter-induced changes (if needed)**

```bash
git status
# If swiftformat produced changes:
git add -u
git commit -m "$(cat <<'EOF'
style: swiftformat on Phase 1 sketchybar files

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Manual smoke test (optional but recommended)**

Build and launch the app, then in another terminal:

```bash
osascript -e 'tell application "Kaset" to seek to 30'
osascript -e 'tell application "Kaset" to get player info'
```

Expected: position jumps to 30s; `get player info` shows `position` near 30.

To verify notifications, run the watcher snippet from `docs/distributed-notifications.md` in a terminal, then change tracks / pause / resume in Kaset. Each user action should print a JSON line.

---

## Out of scope (deferred to Phase 2)

- The `kaset-sketchybar-bridge` SwiftPM target.
- SketchyBar plugin shell scripts and `sketchybarrc.example`.
- `install.sh` / `uninstall.sh` / LaunchAgent plist.
- `docs/sketchybar.md`.

These will be addressed in `docs/superpowers/plans/2026-04-30-sketchybar-phase2-bridge.md` once Phase 1 ships.
