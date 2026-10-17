import Synchronization

/// `onTimeout` must unblock the operation: a task group waits for every child, and a websocket
/// receive() ignores task cancellation, so only cancelling the socket ends it.
func withTimeout<T: Sendable>(
    seconds: Double,
    onTimeout: @escaping @Sendable () -> Void,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let timedOut = TimeoutFlag()
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            timedOut.set()
            onTimeout()
            throw TelevisionError.notResponding
        }
        defer { group.cancelAll() }
        do {
            guard let result = try await group.next() else { throw TelevisionError.notResponding }
            return result
        } catch where timedOut.isSet {
            // The cancelled socket may fail before the timeout child throws: report the timeout either way.
            throw TelevisionError.notResponding
        }
    }
}

private final class TimeoutFlag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}
