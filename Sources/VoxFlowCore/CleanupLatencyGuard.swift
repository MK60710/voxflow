import Foundation

/// The 600ms cleanup budget guard (blueprint Step 6 task 4: "if cleanup
/// exceeds 600ms, insert raw transcript instead and log the overage ...
/// This should be a real timeout/race in the async cleanup call, not just a
/// comment").
///
/// Implemented as a genuine `async` race between the cleanup `operation` and
/// a `Task.sleep`-based timeout via `withThrowingTaskGroup`, not a
/// `DispatchQueue.asyncAfter` fired-and-forgotten deadline or a comment
/// promising the caller will check elapsed time after the fact — whichever
/// finishes first wins, and the loser is cancelled via `group.cancelAll()`
/// so no orphaned work (a still-running HTTP request) keeps consuming
/// resources after this function returns.
///
/// Generic over `T` so it isn't coupled to `CleanupResult` specifically —
/// tests exercise it directly with a plain `String`-returning mock operation
/// and short (tens-of-ms) budgets/delays, per the blueprint's own
/// instruction that this "doesn't need a real 600ms wall-clock sleep in the
/// test suite" to be deterministic.
public enum CleanupLatencyGuard {
    public static func run<T: Sendable>(
        budgetMilliseconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, budgetMilliseconds)) * 1_000_000)
                throw CleanupEngineError.timedOut
            }

            defer { group.cancelAll() }

            // `next()` returns/throws based on whichever child finishes
            // first — that IS the race. A `nil` return (empty group) can't
            // happen here since exactly two tasks were just added above.
            guard let firstResult = try await group.next() else {
                throw CleanupEngineError.timedOut
            }
            return firstResult
        }
    }
}
