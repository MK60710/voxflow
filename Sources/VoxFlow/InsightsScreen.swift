import SwiftUI
import VoxFlowCore

/// Step 5 (plans/voxflow-windowed-ui.md): `InsightsCoordinator`'s content,
/// ported verbatim in behavior into the new window's sidebar — replaces
/// its old standalone `NSWindow`-hosted view (that window-management code
/// is removed from `InsightsCoordinator` itself as part of this step; the
/// `@Published`/store logic there is untouched).
struct InsightsScreen: View {
    @ObservedObject private var insights = InsightsCoordinator.shared

    private var wordsPerMinute: Double? {
        InsightsAggregator.wordsPerMinute(in: insights.entries)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Insights")
                    .font(VoxFlowTheme.heading())
                    .foregroundStyle(VoxFlowTheme.primaryText)

                if let loadError = insights.loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if insights.entries.isEmpty {
                    Text("Nothing dictated yet — Insights fills in as you use VoxFlow.")
                        .foregroundStyle(VoxFlowTheme.secondaryText)
                        .padding(.top, 40)
                } else {
                    statGrid
                    streakSection
                    appUsageSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(VoxFlowTheme.contentBackground)
    }

    @ViewBuilder
    private var statGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            statCard(
                value: InsightsAggregator.totalWords(in: insights.entries).formatted(),
                label: "Total words"
            )
            statCard(
                value: wordsPerMinute.map { String(format: "%.0f", $0) } ?? "—",
                label: "Words / min"
            )
            statCard(
                value: InsightsAggregator.fixesCount(in: insights.entries).formatted(),
                label: "Fixes made"
            )
        }
    }

    /// Same soft filled card treatment as `DictationHomeScreen`'s cards —
    /// the mockup's stat-card look, replacing the old flat gray-opacity
    /// background.
    @ViewBuilder
    private func statCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(VoxFlowTheme.heading(27))
                .foregroundStyle(VoxFlowTheme.primaryText)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.2)
                .foregroundStyle(VoxFlowTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(VoxFlowTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VoxFlowTheme.cardCornerRadius))
    }

    /// The mockup's accent-filled highlight block — day streak is the one
    /// number on this screen worth making unmissable, so it gets a filled
    /// background instead of another outline card.
    @ViewBuilder
    private var streakSection: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(InsightsAggregator.currentStreak(in: insights.entries))")
                    .font(VoxFlowTheme.heading(23))
                    .foregroundStyle(VoxFlowTheme.onAccentText)
                Text("day streak")
                    .font(.system(size: 12.5))
                    .foregroundStyle(VoxFlowTheme.onAccentText.opacity(0.85))
            }
            Spacer()
            Text("longest \(InsightsAggregator.longestStreak(in: insights.entries))")
                .font(.system(size: 12))
                .foregroundStyle(VoxFlowTheme.onAccentText.opacity(0.75))
        }
        .padding(16)
        .background(VoxFlowTheme.streakBackground)
        .clipShape(RoundedRectangle(cornerRadius: VoxFlowTheme.cardCornerRadius))
    }

    @ViewBuilder
    private var appUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App usage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VoxFlowTheme.primaryText)
            ForEach(InsightsAggregator.appUsageBreakdown(in: insights.entries).prefix(8), id: \.bundleIdentifier) { usage in
                HStack {
                    Text(usage.bundleIdentifier ?? "Unknown app")
                        .font(.caption)
                        .foregroundStyle(VoxFlowTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(usage.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(VoxFlowTheme.secondaryText)
                }
            }
        }
    }
}
