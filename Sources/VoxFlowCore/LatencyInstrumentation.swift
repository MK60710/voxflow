import Foundation

/// Tiny pure helper for the blueprint's latency instrumentation requirement
/// (Step 5a task 2: "log timestamps at key-release, transcription-received,
/// and insertion-triggered, so a total can be computed against the 900ms
/// budget"). Split out from the coordinator purely so the arithmetic itself
/// has an offline test, independent of any live Date()/os_log call.
public enum LatencyInstrumentation {
    public static func milliseconds(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) * 1000).rounded())
    }
}
