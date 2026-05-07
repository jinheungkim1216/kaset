import Foundation

/// Names of distributed notifications that should trigger a SketchyBar refresh.
private let kasetNotificationNames = [
    "app.kaset.player.trackChanged",
    "app.kaset.player.playbackStateChanged",
    "app.kaset.player.likeStatusChanged",
]

/// Custom event name posted to SketchyBar for full state refreshes.
private let sketchybarEventName = "kaset_update"

/// Custom event name posted to SketchyBar for the lightweight marquee tick.
/// Subscribers can do title-only rotation without re-querying player state,
/// giving the scroll motion a smoother sub-second cadence than what
/// SketchyBar's integer `update_freq` allows.
private let marqueeEventName = "kaset_marquee_tick"

/// Quiet window after the last received notification before we emit the trigger.
private let debounceInterval: Duration = .milliseconds(100)

/// Cadence of the marquee trigger. SketchyBar's `update_freq` is integer
/// seconds, so we emit a separate fast event from here to keep long-title
/// scrolling smooth. 200 ms ≈ 5 Hz — visibly smoother than 1 Hz without
/// flooding `sketchybar --trigger`.
private let marqueeTickInterval: Duration = .milliseconds(200)

private func logStderr(_ line: String) {
    let payload = "[\(Date.now.ISO8601Format())] \(line)\n"
    FileHandle.standardError.write(Data(payload.utf8))
}

@Sendable private func runSketchybarTrigger(event: String) async {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = ["sketchybar", "--trigger", event]
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            logStderr("sketchybar exited with status \(process.terminationStatus) for \(event) (is sketchybar installed and running?)")
        }
    } catch {
        logStderr("failed to invoke sketchybar for \(event): \(error)")
    }
}

let debouncer = NotificationDebouncer(interval: debounceInterval) {
    await runSketchybarTrigger(event: sketchybarEventName)
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

/// Marquee tick loop. Runs detached for the lifetime of the daemon and
/// fires `kaset_marquee_tick` at a steady cadence. The script-bearing
/// item subscribes and branches on `$SENDER` to rotate the cached title
/// by one step — no AppleScript poll, just a `--set` on the info item's
/// icon.
let marqueeTicker = Task.detached {
    while !Task.isCancelled {
        await runSketchybarTrigger(event: marqueeEventName)
        try? await Task.sleep(for: marqueeTickInterval)
    }
}

logStderr("kaset-sketchybar-bridge ready, listening for \(kasetNotificationNames.count) notifications, marquee ticking every \(marqueeTickInterval)")

// Keep the ticker alive for the process's lifetime — RunLoop.main.run()
// never returns under normal operation, so this just silences the
// unused-variable warning while making the dependency explicit.
withExtendedLifetime(marqueeTicker) {
    RunLoop.main.run()
}
