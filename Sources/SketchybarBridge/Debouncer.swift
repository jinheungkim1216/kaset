import Foundation

/// Trailing-edge debouncer: every `bump()` resets a timer; when the timer
/// expires without further bumps, the configured `action` runs once.
/// Multiple rapid bumps within `interval` collapse to a single action call.
actor NotificationDebouncer {
    private let interval: Duration
    private let action: @Sendable () async -> Void
    private var pendingTask: Task<Void, Never>?
    /// Monotonic counter incremented on every `bump()` and `cancel()`. The
    /// inner task captures the generation observed at scheduling time and
    /// only fires `action` if it still matches when the actor re-enters
    /// after sleep — closes the race where the previous task finishes its
    /// sleep just as a new `bump()` arrives.
    private var generation: UInt64 = 0

    init(interval: Duration, action: @escaping @Sendable () async -> Void) {
        self.interval = interval
        self.action = action
    }

    /// Resets the debounce window. The action will run after one full
    /// `interval` of quiet (no further bumps).
    func bump() {
        self.pendingTask?.cancel()
        self.generation &+= 1
        let scheduledGeneration = self.generation
        let interval = self.interval
        self.pendingTask = Task { [self] in
            try? await Task.sleep(for: interval)
            await self.fireIfCurrent(generation: scheduledGeneration)
        }
    }

    /// Cancels any pending action.
    func cancel() {
        self.pendingTask?.cancel()
        self.pendingTask = nil
        // Invalidate any in-flight task that is past sleep but waiting
        // to re-enter the actor in `fireIfCurrent`.
        self.generation &+= 1
    }

    /// Invoked by the inner task after its sleep completes. Only fires
    /// `action` when no later `bump()` or `cancel()` has changed the
    /// generation since this task was scheduled.
    private func fireIfCurrent(generation scheduledGeneration: UInt64) async {
        guard scheduledGeneration == self.generation else { return }
        await self.action()
    }
}
