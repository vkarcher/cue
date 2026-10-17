import Synchronization
import Testing

@Suite("Timeout")
struct TimeoutTests {
    private final class Counter: Sendable {
        private let value = Mutex(0)
        var count: Int { value.withLock { $0 } }
        func increment() { value.withLock { $0 += 1 } }
    }

    @Test func operationThatFinishesInTimeReturnsItsValue() async throws {
        let cancellations = Counter()
        let value = try await withTimeout(seconds: 2, onTimeout: { cancellations.increment() }) { 42 }
        #expect(value == 42)
        #expect(cancellations.count == 0)
    }

    @Test func slowOperationTimesOutAndIsCancelled() async {
        let cancellations = Counter()
        await #expect(throws: TelevisionError.notResponding) {
            try await withTimeout(seconds: 0.1, onTimeout: { cancellations.increment() }) {
                try await Task.sleep(for: .seconds(5))
                return 0
            }
        }
        #expect(cancellations.count == 1)
    }

    @Test func operationFailingBecauseOfTheCancellationReportsTheTimeout() async {
        // A cancelled websocket makes receive() throw its own error, which must not hide the timeout.
        struct SocketClosed: Error {}
        let closed = Mutex(false)
        await #expect(throws: TelevisionError.notResponding) {
            try await withTimeout(seconds: 0.1, onTimeout: { closed.withLock { $0 = true } }) {
                while !closed.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
                throw SocketClosed()
            }
        }
    }

    @Test func operationErrorBeforeTheTimeoutIsKept() async {
        await #expect(throws: TelevisionError.refused("busy")) {
            try await withTimeout(seconds: 2, onTimeout: {}) { throw TelevisionError.refused("busy") }
        }
    }
}
