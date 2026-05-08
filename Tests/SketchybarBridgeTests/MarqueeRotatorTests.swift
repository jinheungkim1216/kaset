import Foundation
import Testing
@testable import SketchybarBridge

@Suite(.serialized)
struct MarqueeRotatorTests {
    /// Helper: makes an isolated rotator pointed at a fresh tmp dir,
    /// returns the rotator + the dir for cleanup.
    private func makeRotator(window: Int = 6, step: Int = 1) -> (MarqueeRotator, URL) {
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stash = dir.appendingPathComponent("title.txt").path
        let offset = dir.appendingPathComponent("offset").path
        return (MarqueeRotator(titleStashPath: stash, offsetPath: offset, window: window, step: step), dir)
    }

    @Test("Returns nil when no title stash exists yet")
    func returnsNilOnColdStart() {
        let (rotator, dir) = self.makeRotator()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(rotator.nextFrame() == nil)
    }

    @Test("Title shorter than window is returned as-is, no offset file written")
    func shortTitleNoRotation() throws {
        let (rotator, dir) = self.makeRotator(window: 10)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "abc".write(toFile: rotator.titleStashPath, atomically: true, encoding: .utf8)

        let frame = rotator.nextFrame()
        #expect(frame == "abc")
        #expect(!FileManager.default.fileExists(atPath: rotator.offsetPath))
    }

    @Test("Title longer than window rotates one character per call")
    func longTitleRotates() throws {
        let (rotator, dir) = self.makeRotator(window: 6, step: 1)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 13-char title → padded with "   •   " → 20-char loop.
        try "abcdefghijklm".write(toFile: rotator.titleStashPath, atomically: true, encoding: .utf8)

        let frame0 = rotator.nextFrame()
        let frame1 = rotator.nextFrame()
        let frame2 = rotator.nextFrame()

        #expect(frame0 == "abcdef")
        #expect(frame1 == "bcdefg")
        #expect(frame2 == "cdefgh")
    }

    @Test("Rotation wraps cleanly through the separator")
    func wrappingThroughSeparator() throws {
        let (rotator, dir) = self.makeRotator(window: 4, step: 1)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "abcde".write(toFile: rotator.titleStashPath, atomically: true, encoding: .utf8)

        // 5-char title + 7-char separator = 12-char loop. After 12 calls
        // we should be back at offset 0.
        var frames: [String] = []
        for _ in 0 ..< 13 {
            if let f = rotator.nextFrame() { frames.append(f) }
        }
        #expect(frames.count == 13)
        #expect(frames[0] == frames[12])
    }

    @Test("Title shrinking back below window deletes the offset file")
    func shrinkingTitleResetsOffset() throws {
        let (rotator, dir) = self.makeRotator(window: 6)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "abcdefghijklm".write(toFile: rotator.titleStashPath, atomically: true, encoding: .utf8)
        _ = rotator.nextFrame()
        _ = rotator.nextFrame()
        #expect(FileManager.default.fileExists(atPath: rotator.offsetPath))

        try "abc".write(toFile: rotator.titleStashPath, atomically: true, encoding: .utf8)
        let frame = rotator.nextFrame()

        #expect(frame == "abc")
        #expect(!FileManager.default.fileExists(atPath: rotator.offsetPath))
    }
}
