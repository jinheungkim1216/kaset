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

    @Test("Multiple rapid bumps within the window collapse to one action")
    func collapsesRapidBumps() async throws {
        let counter = Counter()
        let debouncer = NotificationDebouncer(interval: .milliseconds(50)) {
            await counter.increment()
        }

        for _ in 0 ..< 5 {
            await debouncer.bump()
        }

        try await Task.sleep(for: .milliseconds(150))
        let count = await counter.value
        #expect(count == 1)
    }

    @Test("Bumps further apart than the interval each fire the action")
    func separateBumpsFireSeparately() async throws {
        let counter = Counter()
        let debouncer = NotificationDebouncer(interval: .milliseconds(50)) {
            await counter.increment()
        }

        await debouncer.bump()
        try await Task.sleep(for: .milliseconds(120))
        await debouncer.bump()
        try await Task.sleep(for: .milliseconds(120))

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
