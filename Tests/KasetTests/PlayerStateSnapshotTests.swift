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
    func dictionaryWithTrack() throws {
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
        let track = try #require(dict["currentTrack"] as? [String: Any])

        #expect(track["name"] as? String == "Test Song")
        #expect(track["artist"] as? String == "Test Artist")
        #expect(track["album"] as? String == "Test Album")
        #expect(track["videoId"] as? String == "test-video-id")
        #expect(track["duration"] as? TimeInterval == 180)
        #expect(track["artworkURL"] as? String == "https://example.com/thumb.jpg")
    }

    @Test("JSON output is valid and round-trips to the dictionary")
    func jsonRoundTrip() throws {
        let service = PlayerService()
        let json = PlayerStateSnapshot.makePlayerInfoJSON(from: service)

        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(parsed["repeating"] as? String == "off")
        #expect(parsed["likeStatus"] as? String == "none")
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
