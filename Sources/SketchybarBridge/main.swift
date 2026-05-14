import Foundation

/// Names of distributed notifications that should trigger a SketchyBar refresh.
private let kasetNotificationNames = [
    "app.kaset.player.trackChanged",
    "app.kaset.player.playbackStateChanged",
    "app.kaset.player.likeStatusChanged",
]

/// Custom event name posted to SketchyBar for full state refreshes.
private let sketchybarEventName = "kaset_update"

/// SketchyBar item the marquee rotator updates on each tick.
private let marqueeItemName = "kaset.info"

/// Quiet window after the last received notification before we emit the trigger.
private let debounceInterval: Duration = .milliseconds(100)

/// Cadence of the marquee frame update. SketchyBar's `update_freq` is
/// integer seconds, so we drive the title rotation from here to keep
/// the scroll smooth. 200 ms ≈ 5 Hz — visibly smoother than 1 Hz
/// without flooding sketchybar.
private let marqueeTickInterval: Duration = .milliseconds(200)

private func logStderr(_ line: String) {
    let payload = "[\(Date.now.ISO8601Format())] \(line)\n"
    FileHandle.standardError.write(Data(payload.utf8))
}

@Sendable private func runSketchybar(_ args: [String]) async {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = ["sketchybar"] + args
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let summary = args.prefix(2).joined(separator: " ")
            logStderr("sketchybar \(summary) exited with status \(process.terminationStatus) (is sketchybar installed and running?)")
        }
    } catch {
        let summary = args.prefix(2).joined(separator: " ")
        logStderr("failed to invoke sketchybar \(summary): \(error)")
    }
}

let debouncer = NotificationDebouncer(interval: debounceInterval) {
    await runSketchybar(["--trigger", sketchybarEventName])
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

/// Marquee tick loop. Rotates the title icon directly via
/// `sketchybar --set` instead of firing a custom event that a shell
/// script then handles — collapses 4 short-lived processes per tick
/// (trigger → bash → python3 → set) down to 1 (set).
private let marqueeWindow = ProcessInfo.processInfo.environment["KASET_MARQUEE_WINDOW"]
    .flatMap(Int.init) ?? 10
private let marqueeStep = ProcessInfo.processInfo.environment["KASET_MARQUEE_STEP"]
    .flatMap(Int.init) ?? 1
let rotator = MarqueeRotator(window: marqueeWindow, step: marqueeStep)

let marqueeTicker = Task.detached {
    while !Task.isCancelled {
        if let frame = rotator.nextFrame() {
            await runSketchybar(["--set", marqueeItemName, "icon=\(frame)"])
        }
        try? await Task.sleep(for: marqueeTickInterval)
    }
}

logStderr("kaset-sketchybar-bridge ready, listening for \(kasetNotificationNames.count) notifications, marquee ticking every \(marqueeTickInterval) (window=\(marqueeWindow), step=\(marqueeStep))")

// Keep the ticker alive for the process's lifetime — RunLoop.main.run()
// never returns under normal operation, so this just silences the
// unused-variable warning while making the dependency explicit.
withExtendedLifetime(marqueeTicker) {
    RunLoop.main.run()
}
