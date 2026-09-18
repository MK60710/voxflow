import Foundation
import os.log
import VoxFlowCore

private let snippetLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "Snippet")

/// Wraps `SnippetStore` (VoxFlowCore) for the Settings UI — mirrors
/// `DictionaryCoordinator`'s exact shape (Core owns persistence, this layer
/// owns `ObservableObject`/`@MainActor` glue and failure logging).
///
/// **Seeded EMPTY, always**, same privacy rule `DictionaryCoordinator`
/// follows — nothing here ever adds a default/starter/example snippet.
@MainActor
final class SnippetCoordinator: ObservableObject {
    static let shared = SnippetCoordinator()

    @Published private(set) var entries: [SnippetEntry] = []
    @Published private(set) var loadError: String?

    private let store: SnippetStore?

    private init() {
        do {
            let store = try SnippetStore()
            self.store = store
            self.entries = store.entries
        } catch {
            self.store = nil
            self.loadError = "Snippets unavailable: \(error.localizedDescription)"
            os_log(.error, log: snippetLog, "SnippetStore init failed: %{public}@", error.localizedDescription)
        }
    }

    func add(trigger: String, expansion: String) {
        guard let store else { return }
        do {
            _ = try store.add(trigger: trigger, expansion: expansion)
            entries = store.entries
        } catch {
            os_log(.error, log: snippetLog, "Add failed: %{public}@", error.localizedDescription)
        }
    }

    func remove(id: UUID) {
        guard let store else { return }
        do {
            try store.remove(id: id)
            entries = store.entries
        } catch {
            os_log(.error, log: snippetLog, "Remove failed: %{public}@", error.localizedDescription)
        }
    }

    func update(id: UUID, trigger: String, expansion: String) {
        guard let store else { return }
        do {
            try store.update(id: id, trigger: trigger, expansion: expansion)
            entries = store.entries
        } catch {
            os_log(.error, log: snippetLog, "Update failed: %{public}@", error.localizedDescription)
        }
    }
}
