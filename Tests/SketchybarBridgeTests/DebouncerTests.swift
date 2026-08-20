import Foundation
import Testing
@testable import SketchybarBridge

@Suite(.serialized)
struct DebouncerTests {
    actor Counter {
        private(set) var value = 0
        func increment() {
            self.value += 1
        }
    }

    /// Polls until `condition` holds, or gives up after `timeout`.
    ///
    /// The positive assertions below must not depend on a fixed sleep being
    /// longer than the debounce interval: on a loaded CI runner a 50 ms
    /// debounce plus task scheduling routinely exceeds the 150 ms these tests
    /// used to wait, which failed the run with `count == 0`.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(10),
        _ condition: () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while await !condition() {
            guard clock.now < deadline else { return await condition() }
            try? await Task.sleep(for: pollInterval)
        }

        return true
    }

    @Test("Multiple rapid bumps within the window collapse to one action")
    func collapsesRapidBumps() async throws {
        let counter = Counter()
        let debouncer = NotificationDebouncer(interval: .milliseconds(50)) {
            await counter.increment()
        }

        for _ in 0 ..< 5 {
            await debouncer.bump()
        }

        let fired = await self.waitUntil { await counter.value >= 1 }
        #expect(fired)

        // Quiet window: a failure to collapse would land the extra calls here.
        try await Task.sleep(for: .milliseconds(200))
        let count = await counter.value
        #expect(count == 1)
    }

    @Test("Bumps further apart than the interval each fire the action")
    func separateBumpsFireSeparately() async {
        let counter = Counter()
        let debouncer = NotificationDebouncer(interval: .milliseconds(50)) {
            await counter.increment()
        }

        await debouncer.bump()
        let firstFired = await self.waitUntil { await counter.value >= 1 }
        #expect(firstFired)

        await debouncer.bump()
        let secondFired = await self.waitUntil { await counter.value >= 2 }
        #expect(secondFired)

        let count = await counter.value
        #expect(count == 2)
    }

    @Test("Cancel before the window expires suppresses the action")
    func cancelSuppressesAction() async throws {
        let counter = Counter()
        let debouncer = NotificationDebouncer(interval: .milliseconds(50)) {
            await counter.increment()
        }

        await debouncer.bump()
        await debouncer.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let count = await counter.value
        #expect(count == 0)
    }
}
