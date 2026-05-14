import Foundation

/// Computes the visible character window for a scrolling marquee.
///
/// Title text is supplied out-of-band via a small file the 1-Hz shell
/// driver (`kaset_update.sh`) writes on every full update. Rotation
/// state (the current offset) is also persisted to disk, but only so
/// the value survives bridge restarts — within a single run it is
/// effectively in-memory.
///
/// The Swift implementation replaces the old per-tick chain of
/// `sketchybar --trigger → bash → python3 → sketchybar --set` (~4
/// short-lived processes per 200 ms tick) with a single
/// `sketchybar --set` call. That removes ~75% of the marquee's
/// process spawn pressure.
struct MarqueeRotator {
    let titleStashPath: String
    let offsetPath: String
    let window: Int
    let step: Int
    private let separator: [Character] = Array("   •   ")

    init(window: Int = 10, step: Int = 1) {
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        let base = (tmp as NSString)
        self.titleStashPath = base.appendingPathComponent("kaset-sketchybar-title.txt")
        self.offsetPath = base.appendingPathComponent("kaset-sketchybar-marquee-offset")
        self.window = window
        self.step = step
    }

    /// Test seam: lets unit tests pin the file paths into a temp dir
    /// instead of `$TMPDIR` (which is the real shell's stash path).
    init(titleStashPath: String, offsetPath: String, window: Int = 10, step: Int = 1) {
        self.titleStashPath = titleStashPath
        self.offsetPath = offsetPath
        self.window = window
        self.step = step
    }

    /// Reads the latest stashed title, advances the marquee offset by
    /// `step`, and returns the visible character window. Returns `nil`
    /// when no stash file exists yet (cold start, before the first
    /// 1-Hz tick has run).
    func nextFrame() -> String? {
        guard let raw = try? String(contentsOfFile: self.titleStashPath, encoding: .utf8) else {
            return nil
        }
        let title = raw.trimmingCharacters(in: .newlines)
        let chars = Array(title)

        // Title fits in the window — no scrolling, no offset to track.
        guard chars.count > self.window else {
            try? FileManager.default.removeItem(atPath: self.offsetPath)
            return title
        }

        let padded = chars + self.separator
        let modulus = padded.count

        var offset = 0
        if let raw = try? String(contentsOfFile: self.offsetPath, encoding: .utf8),
           let parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            // Defensive normalization — file content can disappear or
            // be corrupted by a concurrent shell write between ticks.
            offset = ((parsed % modulus) + modulus) % modulus
        }

        let next = (offset + self.step) % modulus
        try? "\(next)".write(toFile: self.offsetPath, atomically: true, encoding: .utf8)

        let doubled = padded + padded
        let frame = doubled[offset ..< (offset + self.window)]
        return String(frame)
    }
}
