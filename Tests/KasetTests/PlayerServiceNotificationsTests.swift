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
    func trackChangedFiresOnNewTrack() throws {
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

        let info = try #require(received?.userInfo as? [String: Any])
        let track = try #require(info["currentTrack"] as? [String: Any])
        #expect(track["videoId"] as? String == "video-a")
        #expect(track["name"] as? String == "Song A")
        #expect(info["isPlaying"] as? Bool == false)
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
    func playbackStateChangedFires() throws {
        let service = PlayerService()
        var received: Notification?

        let observer = PlayerService.notificationCenter.addObserver(
            forName: PlayerService.PlayerNotification.playbackStateChanged,
            object: nil,
            queue: nil
        ) { received = $0 }
        defer { PlayerService.notificationCenter.removeObserver(observer) }

        service.state = .playing

        let info = try #require(received?.userInfo as? [String: Any])
        #expect(info["isPlaying"] as? Bool == true)
        #expect(info["isPaused"] as? Bool == false)
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
    func likeStatusChangedFires() throws {
        let service = PlayerService()
        var received: Notification?

        let observer = PlayerService.notificationCenter.addObserver(
            forName: PlayerService.PlayerNotification.likeStatusChanged,
            object: nil,
            queue: nil
        ) { received = $0 }
        defer { PlayerService.notificationCenter.removeObserver(observer) }

        service.currentTrackLikeStatus = .like

        let info = try #require(received?.userInfo as? [String: Any])
        #expect(info["likeStatus"] as? String == "liked")
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
