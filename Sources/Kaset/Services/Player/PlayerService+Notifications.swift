import Foundation

extension PlayerService {
    /// Distributed notification names broadcast when player state mutates.
    /// External subscribers (e.g. SketchyBar bridge) listen on
    /// `DistributedNotificationCenter.default()`.
    enum PlayerNotification {
        /// Posted when `currentTrack` changes (videoId differs, including nil ⇄ non-nil).
        static let trackChanged = Notification.Name("app.kaset.player.trackChanged")

        /// Posted when `state` transitions (loading / playing / paused / etc.).
        static let playbackStateChanged = Notification.Name("app.kaset.player.playbackStateChanged")

        /// Posted when `currentTrackLikeStatus` changes.
        static let likeStatusChanged = Notification.Name("app.kaset.player.likeStatusChanged")
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
