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
