import Foundation
import os.log
import VoxFlowCore

private let dictionaryLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "Dictionary")

/// Owns the Step 8 personal dictionary: wraps `DictionaryStore`
/// (VoxFlowCore) for the Settings UI, and exposes the two bias hooks the
/// blueprint names —
///   - `sttBiasPrompt`, fed into `TranscriptionEngine`'s EXISTING
///     `biasPrompt` parameter (`TranscriptionCoordinator`), and
///   - `termsForCleanup`, fed into `CleanupEngine`'s new `dictionaryTerms`
///     parameter (`CleanupCoordinator`; see `CleanupEngine.swift`'s Step 8
///     addition).
///
/// Lives in `Sources/VoxFlow` (App layer), not `VoxFlowCore` — mirrors
/// `CleanupCoordinator`/`TranscriptionCoordinator`'s split: Core owns pure
/// model/persistence/prompt-assembly logic (`DictionaryStore`,
/// `DictionaryPromptAssembly`), this layer owns the `ObservableObject`/
/// `@MainActor` glue for SwiftUI plus failure logging.
///
/// **Seeded EMPTY, always** (blueprint task 2's explicit privacy rule): a
/// fresh `DictionaryStore()` with no file on disk starts with zero entries,
/// and nothing here ever adds a default/starter/example entry. Mihir adds
/// his own real terms through the Settings UI — no contacts, no names, no
/// real jargon are preloaded by this session.
@MainActor
final class DictionaryCoordinator: ObservableObject {
    static let shared = DictionaryCoordinator()

    @Published private(set) var entries: [DictionaryEntry] = []
    /// Set only if `DictionaryStore.init()` itself failed (e.g. Application
    /// Support genuinely unavailable) — surfaced in Settings so Mihir isn't
    /// left wondering why Add silently does nothing.
    @Published private(set) var loadError: String?

    private let store: DictionaryStore?

    private init() {
        do {
            let store = try DictionaryStore()
            self.store = store
            self.entries = store.entries
        } catch {
            // Degrade gracefully: the dictionary feature becomes a no-op
            // for this session (biasPrompt/dictionaryTerms are simply
            // empty) rather than crashing the whole app over a Step 8
            // feature failing to find a directory that should always
            // exist on a normal macOS install.
            self.store = nil
            self.loadError = "Dictionary unavailable: \(error.localizedDescription)"
            os_log(.error, log: dictionaryLog, "DictionaryStore init failed: %{public}@", error.localizedDescription)
        }
    }

    func add(term: String, soundsLike: String?) {
        guard let store else { return }
        do {
            _ = try store.add(term: term, soundsLike: soundsLike)
            entries = store.entries
        } catch {
            os_log(.error, log: dictionaryLog, "Add failed: %{public}@", error.localizedDescription)
        }
    }

    func remove(id: UUID) {
        guard let store else { return }
        do {
            try store.remove(id: id)
            entries = store.entries
        } catch {
            os_log(.error, log: dictionaryLog, "Remove failed: %{public}@", error.localizedDescription)
        }
    }

    func update(id: UUID, term: String, soundsLike: String?) {
        guard let store else { return }
        do {
            try store.update(id: id, term: term, soundsLike: soundsLike)
            entries = store.entries
        } catch {
            os_log(.error, log: dictionaryLog, "Update failed: %{public}@", error.localizedDescription)
        }
    }

    /// Step 8 task 3, bias point 1: fed straight into
    /// `TranscriptionEngine.transcribe(audioFileURL:biasPrompt:)` — the
    /// EXISTING parameter Step 5a's protocol already defined, per the
    /// blueprint's explicit instruction not to invent a new one. `nil` when
    /// the dictionary is empty, matching S5a's original always-nil
    /// behavior exactly.
    var sttBiasPrompt: String? {
        DictionaryPromptAssembly.sttBiasPrompt(forEntries: entries)
    }

    /// Step 8 task 3, bias point 2: fed into `CleanupEngine`'s new
    /// `dictionaryTerms` parameter, which `CleanupPromptTemplate`'s new
    /// dictionary-aware `messages` overload turns into "these terms are
    /// spelled exactly: …".
    var termsForCleanup: [String] {
        entries.map { $0.term }
    }
}
