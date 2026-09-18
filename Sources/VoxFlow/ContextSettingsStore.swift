import AppKit
import Foundation
import VoxFlowCore

/// Persisted app→tone assignments (blueprint Step 7 task 3: "Settings UI:
/// view/edit app→tone assignments — a list view plus a 'currently running
/// apps' picker"). Seeded from `ContextDetector.defaultAssignments()`; user
/// edits persist as JSON in `UserDefaults`, same storage convention as
/// `CleanupCoordinator.cleanupEnabled` (docs/architecture.md's "Settings
/// storage" section: "UserDefaults for toggles/hotkey/tone map").
///
/// Lives in `Sources/VoxFlow` (not `VoxFlowCore`) for the same reason
/// `KeychainCredentialStore`/`CleanupCoordinator` do: `UserDefaults`
/// persistence is a system side effect, and the "currently running apps"
/// picker needs `NSWorkspace.shared.runningApplications`, which is AppKit.
/// `ContextDetector` itself (the pure bundle-ID → tone logic this store
/// wraps) stays AppKit-free in `VoxFlowCore`.
@MainActor
final class ContextSettingsStore: ObservableObject {
    static let shared = ContextSettingsStore()

    private static let assignmentsDefaultsKey = "voxflow.contextToneAssignments"

    /// bundle identifier → tone. Published so the Settings list view updates
    /// live on add/remove/edit/reset.
    @Published private(set) var assignments: [String: ToneProfile]

    private init() {
        self.assignments = Self.loadPersistedOrDefaults()
    }

    // MARK: - Reads

    /// `TranscriptionCoordinator` calls this to resolve the tone for the
    /// dictation currently in flight — pure delegation to
    /// `ContextDetector.toneProfile`, just supplying this store's current
    /// (defaults + user overrides) map instead of the bare defaults.
    func toneProfile(forBundleIdentifier bundleIdentifier: String?) -> ToneProfile {
        ContextDetector.toneProfile(forBundleIdentifier: bundleIdentifier, assignments: assignments)
    }

    // MARK: - Edits (Settings UI)

    func setTone(_ tone: ToneProfile, forBundleIdentifier bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty else { return }
        assignments[bundleIdentifier] = tone
        persist()
    }

    func removeAssignment(forBundleIdentifier bundleIdentifier: String) {
        assignments.removeValue(forKey: bundleIdentifier)
        persist()
    }

    /// Restores `ContextDetector`'s built-in map, discarding every user
    /// override. Not destructive of anything Mihir can't get back — the
    /// defaults are a pure function, always reproducible.
    func resetToDefaults() {
        assignments = ContextDetector.defaultAssignments()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(assignments) else { return }
        UserDefaults.standard.set(data, forKey: Self.assignmentsDefaultsKey)
    }

    private static func loadPersistedOrDefaults() -> [String: ToneProfile] {
        guard let data = UserDefaults.standard.data(forKey: assignmentsDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: ToneProfile].self, from: data) else {
            return ContextDetector.defaultAssignments()
        }
        return decoded
    }

    // MARK: - "Currently running apps" picker (blueprint task 3)

    struct RunningAppOption: Identifiable, Equatable {
        let bundleIdentifier: String
        let displayName: String
        var id: String { bundleIdentifier }
    }

    /// Enumerates `NSWorkspace.shared.runningApplications`, filtered to
    /// regular apps with a UI (`activationPolicy == .regular` — excludes
    /// background/agent processes and menu-bar-only apps like VoxFlow
    /// itself, which never has a Dock icon per `LSUIElement`), deduplicated
    /// by bundle ID, sorted by display name. This is the picker's data
    /// source; assigning a tone to one of these options just calls
    /// `setTone(_:forBundleIdentifier:)` above with its bundle ID.
    func runningApplicationOptions() -> [RunningAppOption] {
        var seen = Set<String>()
        var options: [RunningAppOption] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleIdentifier = app.bundleIdentifier,
                  !seen.contains(bundleIdentifier) else { continue }
            seen.insert(bundleIdentifier)
            let name = app.localizedName ?? bundleIdentifier
            options.append(RunningAppOption(bundleIdentifier: bundleIdentifier, displayName: name))
        }
        return options.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
