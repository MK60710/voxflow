import Foundation

/// Pure aggregation over `[InsightsEntry]` — no I/O, fully offline-testable,
/// same "split decision logic out of the App-layer coordinator" pattern
/// this codebase uses everywhere (`EngineStatusResolver`,
/// `ContentPreservationGuard`, etc.).
public enum InsightsAggregator {
    public static func totalWords(in entries: [InsightsEntry]) -> Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    /// `nil` when there's no audio time to divide by (empty history) —
    /// avoids a divide-by-zero rather than returning a misleading 0.
    public static func wordsPerMinute(in entries: [InsightsEntry]) -> Double? {
        let totalSeconds = entries.reduce(0.0) { $0 + $1.audioDurationSeconds }
        guard totalSeconds > 0 else { return nil }
        let totalMinutes = totalSeconds / 60.0
        return Double(totalWords(in: entries)) / totalMinutes
    }

    /// How many dictations `CleanupCoordinator` actually cleaned (vs. fell
    /// back to raw, for any reason) — Wispr's "fixes made by Flow" number.
    public static func fixesCount(in entries: [InsightsEntry]) -> Int {
        entries.filter(\.wasCleanedUp).count
    }

    /// Consecutive calendar days with at least one dictation, counting
    /// backward from `referenceDate`. If `referenceDate`'s own day has no
    /// activity yet, the streak isn't considered broken — today just
    /// hasn't happened yet — so counting starts from yesterday instead.
    public static func currentStreak(
        in entries: [InsightsEntry],
        asOf referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let daysWithActivity = Set(entries.map { calendar.startOfDay(for: $0.timestamp) })
        guard !daysWithActivity.isEmpty else { return 0 }

        var day = calendar.startOfDay(for: referenceDate)
        if !daysWithActivity.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }

        var streak = 0
        while daysWithActivity.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }
        return streak
    }

    /// The longest run of consecutive-day activity anywhere in the history,
    /// not just the current streak — Wispr's "longest streak" figure.
    public static func longestStreak(in entries: [InsightsEntry], calendar: Calendar = .current) -> Int {
        let days = Set(entries.map { calendar.startOfDay(for: $0.timestamp) }).sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for index in 1..<days.count {
            if let expectedNext = calendar.date(byAdding: .day, value: 1, to: days[index - 1]),
               calendar.isDate(expectedNext, inSameDayAs: days[index]) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    /// Per-app word counts, descending. `bundleIdentifier == nil` entries
    /// (frontmost app couldn't be determined) are grouped under `nil`'s own
    /// key so their words aren't silently dropped from the total, but are
    /// still distinguishable from a real app in the UI.
    public struct AppUsage: Equatable, Sendable {
        public let bundleIdentifier: String?
        public let wordCount: Int
    }

    public static func appUsageBreakdown(in entries: [InsightsEntry]) -> [AppUsage] {
        var totals: [String?: Int] = [:]
        for entry in entries {
            totals[entry.bundleIdentifier, default: 0] += entry.wordCount
        }
        return totals
            .map { AppUsage(bundleIdentifier: $0.key, wordCount: $0.value) }
            .sorted { $0.wordCount > $1.wordCount }
    }
}
