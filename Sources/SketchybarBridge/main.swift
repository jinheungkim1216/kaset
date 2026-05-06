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
