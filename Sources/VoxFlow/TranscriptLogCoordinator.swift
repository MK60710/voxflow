import Combine
import VoxFlowCore
import os.log

private let transcriptLogLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "TranscriptLog")

/// A safety-net window: every dictation's final text (post-cleanup, the
/// exact string handed to `TextInsertionCoordinator`) is logged HERE too,
/// regardless of whether insertion into the target app actually succeeds —
/// so if a paste silently fails for any reason (an app CGEvent can't type
/// into, focus stolen mid-flight, a permission gap, anything), the text is
/// never actually lost, just sitting here to manually copy.
///
/// **Persisted (2026-08-13, Mihir's explicit request)** — wraps
/// `TranscriptLogStore` (VoxFlowCore), mirroring `DictionaryCoordinator`'s
/// exact wrapping shape: this layer owns the `ObservableObject`/`@MainActor`
/// glue and failure logging, the Core store owns the actual JSON
/// persistence in `~/Library/Application Support/VoxFlow/transcript-log.json`.
@MainActor
final class TranscriptLogCoordinator: ObservableObject {
    static let shared = TranscriptLogCoordinator()

    @Published private(set) var entries: [TranscriptLogEntry] = []
    /// Set only if `TranscriptLogStore.init()` itself failed — surfaced in
    /// the log window so Mihir isn't left wondering why nothing's showing
    /// up, same reasoning as `DictionaryCoordinator.loadError`.
    @Published private(set) var loadError: String?

    private let store: TranscriptLogStore?

    private init() {
        do {
            let store = try TranscriptLogStore()
            self.store = store
            self.entries = store.entries
        } catch {
            self.store = nil
            self.loadError = "Transcript log unavailable: \(error.localizedDescription)"
            os_log(.error, log: transcriptLogLog, "TranscriptLogStore init failed: %{public}@", error.localizedDescription)
        }
    }

    func append(_ text: String) {
        guard let store else { return }
        do {
            try store.append(text)
            entries = store.entries
        } catch {
            os_log(.error, log: transcriptLogLog, "Append failed: %{public}@", error.localizedDescription)
        }
    }

    func clear() {
        guard let store else { return }
        do {
            try store.clear()
            entries = store.entries
        } catch {
            os_log(.error, log: transcriptLogLog, "Clear failed: %{public}@", error.localizedDescription)
        }
    }
}
