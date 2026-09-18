import ServiceManagement

/// Step 11a task 2's launch-at-login toggle, via `SMAppService` (macOS 13+,
/// the modern replacement for the old `SMLoginItemSetEnabled`/helper-app
/// approach — no separate login-item helper target needed for a single
/// main-app registration).
///
/// Deliberately NOT a plain `@Published var` with a `didSet` (the pattern
/// every other Settings toggle in this codebase uses, e.g.
/// `CleanupCoordinator.cleanupEnabled`): those toggles only ever write to
/// `UserDefaults`, which can't fail. `SMAppService.register()`/`unregister()`
/// are real OS calls that CAN throw (e.g. a system policy blocking it), and
/// this codebase's error-surface philosophy is "never fail silently" — so
/// `isEnabled` is read-only from outside, changed only through `setEnabled`,
/// which can report failure back to the Settings UI instead of silently
/// leaving the toggle in a state that doesn't match reality.
@MainActor
final class LaunchAtLoginCoordinator: ObservableObject {
    static let shared = LaunchAtLoginCoordinator()

    @Published private(set) var isEnabled: Bool
    @Published var lastError: String?

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = enabled
            lastError = nil
        } catch {
            lastError = "Couldn't \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
    }
}
