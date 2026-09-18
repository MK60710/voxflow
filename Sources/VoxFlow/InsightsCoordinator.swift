import Combine
import VoxFlowCore
import os.log

private let insightsLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "Insights")

/// Wraps `InsightsStore`/`InsightsAggregator` (VoxFlowCore) for
/// `InsightsScreen` (the main window's Insights screen, Step 5 of
/// plans/voxflow-windowed-ui.md) — mirrors `DictionaryCoordinator`'s exact
/// wrapping shape: this layer owns the `ObservableObject`/`@MainActor`
/// glue and failure logging; Core owns persistence and the actual stat
/// math. Previously also owned a standalone `NSWindow` — removed in Step 5
/// now that `InsightsScreen` lives in the shared main window instead.
@MainActor
final class InsightsCoordinator: ObservableObject {
    static let shared = InsightsCoordinator()

    @Published private(set) var entries: [InsightsEntry] = []
    @Published private(set) var loadError: String?

    private let store: InsightsStore?

    private init() {
        do {
            let store = try InsightsStore()
            self.store = store
            self.entries = store.entries
        } catch {
            self.store = nil
            self.loadError = "Insights unavailable: \(error.localizedDescription)"
            os_log(.error, log: insightsLog, "InsightsStore init failed: %{public}@", error.localizedDescription)
        }
    }

    func append(wordCount: Int, audioDurationSeconds: Double, bundleIdentifier: String?, wasCleanedUp: Bool) {
        guard let store else { return }
        do {
            try store.append(
                wordCount: wordCount,
                audioDurationSeconds: audioDurationSeconds,
                bundleIdentifier: bundleIdentifier,
                wasCleanedUp: wasCleanedUp
            )
            entries = store.entries
        } catch {
            os_log(.error, log: insightsLog, "Append failed: %{public}@", error.localizedDescription)
        }
    }
}
