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
