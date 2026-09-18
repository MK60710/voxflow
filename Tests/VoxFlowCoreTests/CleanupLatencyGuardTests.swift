import Foundation
import Testing
@testable import VoxFlowCore

/// Tests the 600ms-guard's race logic deterministically with short
/// (tens-of-ms) budgets/delays — per the blueprint's own instruction, this
/// does NOT need a real 600ms wall-clock sleep to be a faithful test of the
/// race itself. The numbers are chosen with enough separation (an order of
/// magnitude apart) that timing jitter on a loaded CI/dev machine won't
/// flip which task wins.
@Suite("CleanupLatencyGuard")
struct CleanupLatencyGuardTests {

    @Test("an operation that finishes well within budget returns its result")
    func fastOperationReturnsResult() async throws {
        let result = try await CleanupLatencyGuard.run(budgetMilliseconds: 200) {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return "fast result"
        }
        #expect(result == "fast result")
    }

    @Test("an operation that exceeds the budget throws timedOut, not the operation's eventual result")
    func slowOperationThrowsTimedOut() async throws {
        do {
            _ = try await CleanupLatencyGuard.run(budgetMilliseconds: 20) {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms — far past a 20ms budget
                return "too slow"
            }
            Issue.record("expected timedOut to be thrown")
        } catch let error as CleanupEngineError {
            #expect(error == .timedOut)
        }
    }

    @Test("an operation that throws its own error before the timeout propagates that error, not timedOut")
    func fastFailureOperationPropagatesItsOwnError() async throws {
        do {
            _ = try await CleanupLatencyGuard.run(budgetMilliseconds: 200) {
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms — well within budget
                throw CleanupEngineError.offline
            }
            Issue.record("expected offline to be thrown")
        } catch let error as CleanupEngineError {
            #expect(error == .offline)
        }
    }

    @Test("a zero-millisecond budget times out immediately rather than hanging")
    func zeroBudgetTimesOutImmediately() async throws {
        do {
            _ = try await CleanupLatencyGuard.run(budgetMilliseconds: 0) {
                try await Task.sleep(nanoseconds: 50_000_000)
                return "never gets here in time"
            }
            Issue.record("expected timedOut to be thrown")
        } catch let error as CleanupEngineError {
            #expect(error == .timedOut)
        }
    }

    @Test("the operation actually runs concurrently with the timeout, not sequentially after it")
    func operationRunsConcurrentlyWithTimeout() async throws {
        // If this were sequential (run the timeout THEN the operation, or
        // vice versa) this test would either always time out or always take
        // the full budget. Running them as a real race means a fast
        // operation under a generous budget returns near-instantly.
        let start = Date()
        _ = try await CleanupLatencyGuard.run(budgetMilliseconds: 5_000) {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return "done"
        }
        let elapsedMs = LatencyInstrumentation.milliseconds(from: start, to: Date())
        #expect(elapsedMs < 500, "expected the race to resolve near-instantly on the fast path, took \(elapsedMs)ms")
    }
}
