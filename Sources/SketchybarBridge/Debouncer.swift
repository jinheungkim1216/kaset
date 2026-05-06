import Foundation

/// Trailing-edge debouncer: every `bump()` resets a timer; when the timer
/// expires without further bumps, the configured `action` runs once.
/// Multiple rapid bumps within `interval` collapse to a single action call.
actor NotificationDebouncer {
    private let interval: Duration
    private let action: @Sendable () async -> Void
    private var pendingTask: Task<Void, Never>?

    init(interval: Duration, action: @escaping @Sendable () async -> Void) {
        self.interval = interval
        self.action = action
    }

    /// Resets the debounce window. The action will run after one full
    /// `interval` of quiet (no further bumps).
    func bump() {
        self.pendingTask?.cancel()
        let interval = self.interval
        let action = self.action
        self.pendingTask = Task {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return // cancelled
            }
            await action()
        }
    }

    /// Cancels any pending action.
    func cancel() {
        self.pendingTask?.cancel()
        self.pendingTask = nil
    }
}
