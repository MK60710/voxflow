import Foundation
import Testing
@testable import VoxFlowCore

@Suite("InsightsAggregator")
struct InsightsAggregatorTests {

    private func entry(
        daysAgo: Int,
        wordCount: Int = 10,
        audioDurationSeconds: Double = 5,
        bundleIdentifier: String? = "com.apple.Terminal",
        wasCleanedUp: Bool = true,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> InsightsEntry {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: referenceDate))!
        return InsightsEntry(
            timestamp: day,
            wordCount: wordCount,
            audioDurationSeconds: audioDurationSeconds,
            bundleIdentifier: bundleIdentifier,
            wasCleanedUp: wasCleanedUp
        )
    }

    @Test("totalWords sums every entry's word count")
    func totalWordsSums() {
        let entries = [entry(daysAgo: 0, wordCount: 10), entry(daysAgo: 1, wordCount: 25)]
        #expect(InsightsAggregator.totalWords(in: entries) == 35)
    }

    @Test("totalWords is 0 for an empty history")
    func totalWordsEmptyIsZero() {
        #expect(InsightsAggregator.totalWords(in: []) == 0)
    }

    @Test("wordsPerMinute divides total words by total minutes across the whole history")
    func wordsPerMinuteComputesCorrectly() {
        // 100 words over 60 seconds (1 minute) -> 100 wpm.
        let entries = [entry(daysAgo: 0, wordCount: 60, audioDurationSeconds: 30), entry(daysAgo: 0, wordCount: 40, audioDurationSeconds: 30)]
        let wpm = InsightsAggregator.wordsPerMinute(in: entries)
        #expect(wpm != nil)
        #expect(abs(wpm! - 100.0) < 0.001)
    }

    @Test("wordsPerMinute is nil for an empty history, not a divide-by-zero crash or misleading 0")
    func wordsPerMinuteEmptyIsNil() {
        #expect(InsightsAggregator.wordsPerMinute(in: []) == nil)
    }

    @Test("fixesCount counts only wasCleanedUp entries")
    func fixesCountCountsOnlyCleaned() {
        let entries = [
            entry(daysAgo: 0, wasCleanedUp: true),
            entry(daysAgo: 1, wasCleanedUp: false),
            entry(daysAgo: 2, wasCleanedUp: true)
        ]
        #expect(InsightsAggregator.fixesCount(in: entries) == 2)
    }

    @Test("currentStreak counts consecutive days ending today")
    func currentStreakEndingToday() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 1), entry(daysAgo: 2)]
        #expect(InsightsAggregator.currentStreak(in: entries) == 3)
    }

    @Test("currentStreak still counts if today has no activity yet, starting from yesterday")
    func currentStreakNotBrokenByEmptyToday() {
        let entries = [entry(daysAgo: 1), entry(daysAgo: 2), entry(daysAgo: 3)]
        #expect(InsightsAggregator.currentStreak(in: entries) == 3)
    }

    @Test("currentStreak stops at the first gap")
    func currentStreakStopsAtGap() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 1), entry(daysAgo: 3)]
        #expect(InsightsAggregator.currentStreak(in: entries) == 2)
    }

    @Test("currentStreak is 0 for an empty history")
    func currentStreakEmptyIsZero() {
        #expect(InsightsAggregator.currentStreak(in: []) == 0)
    }

    @Test("currentStreak is 0 if the most recent activity was more than a day before today")
    func currentStreakStaleActivityIsZero() {
        let entries = [entry(daysAgo: 5)]
        #expect(InsightsAggregator.currentStreak(in: entries) == 0)
    }

    @Test("longestStreak finds the longest run anywhere in history, not just the current one")
    func longestStreakFindsBestRun() {
        // A 4-day run (10,9,8,7 days ago) followed by a gap, then today only.
        let entries = [
            entry(daysAgo: 0),
            entry(daysAgo: 7), entry(daysAgo: 8), entry(daysAgo: 9), entry(daysAgo: 10)
        ]
        #expect(InsightsAggregator.longestStreak(in: entries) == 4)
        #expect(InsightsAggregator.currentStreak(in: entries) == 1)
    }

    @Test("longestStreak is 0 for an empty history")
    func longestStreakEmptyIsZero() {
        #expect(InsightsAggregator.longestStreak(in: []) == 0)
    }

    @Test("multiple dictations on the same day count as one streak day, not zero or double")
    func sameDayMultipleDictationsCountAsOneStreakDay() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 0), entry(daysAgo: 1)]
        #expect(InsightsAggregator.currentStreak(in: entries) == 2)
    }

    @Test("appUsageBreakdown sums word counts per app and sorts descending")
    func appUsageBreakdownSortsDescending() {
        let entries = [
            entry(daysAgo: 0, wordCount: 10, bundleIdentifier: "com.apple.Terminal"),
            entry(daysAgo: 1, wordCount: 50, bundleIdentifier: "com.apple.mail"),
            entry(daysAgo: 2, wordCount: 5, bundleIdentifier: "com.apple.Terminal")
        ]
        let breakdown = InsightsAggregator.appUsageBreakdown(in: entries)
        #expect(breakdown.first?.bundleIdentifier == "com.apple.mail")
        #expect(breakdown.first?.wordCount == 50)
        #expect(breakdown[1].bundleIdentifier == "com.apple.Terminal")
        #expect(breakdown[1].wordCount == 15)
    }

    @Test("appUsageBreakdown groups nil bundleIdentifier entries together rather than dropping them")
    func appUsageBreakdownGroupsNilBundleIdentifier() {
        let entries = [entry(daysAgo: 0, wordCount: 10, bundleIdentifier: nil)]
        let breakdown = InsightsAggregator.appUsageBreakdown(in: entries)
        #expect(breakdown.count == 1)
        #expect(breakdown.first?.bundleIdentifier == nil)
        #expect(breakdown.first?.wordCount == 10)
    }
}
