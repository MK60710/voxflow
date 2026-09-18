import Foundation

/// Step 10 task 4: command mode on/off toggle, persisted like every other
/// VoxFlow setting (`UserDefaults`, per `CleanupCoordinator`'s exact
/// pattern). Defaults to on — command mode is deliberately conservative
/// (exact-match only, `CommandRecognizer`'s own doc comment), so there's no
/// "learning curve" risk in leaving it on by default the way there might be
/// for a fuzzier feature.
@MainActor
final class CommandModeCoordinator: ObservableObject {
    static let shared = CommandModeCoordinator()

    private static let commandModeEnabledDefaultsKey = "voxflow.commandModeEnabled"

    @Published var commandModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(commandModeEnabled, forKey: Self.commandModeEnabledDefaultsKey)
        }
    }

    private init() {
        self.commandModeEnabled = (UserDefaults.standard.object(forKey: Self.commandModeEnabledDefaultsKey) as? Bool) ?? true
    }
}
