import Foundation
import VoxFlowCore

/// Step 11a task 2's hotkey picker: the single source of truth for which
/// `HotkeyOption` is currently configured, persisted like every other
/// Settings choice (`UserDefaults`, mirroring `CommandModeCoordinator`'s
/// exact pattern). Both the Settings UI (binds directly) and `HotkeyManager`
/// (reads `selectedHotkey` on every `flagsChanged` event) reference this one
/// instance — no second, potentially-stale copy of the selection anywhere.
@MainActor
final class HotkeyCoordinator: ObservableObject {
    static let shared = HotkeyCoordinator()

    private static let selectedHotkeyDefaultsKey = "voxflow.selectedHotkey"

    @Published var selectedHotkey: HotkeyOption {
        didSet {
            UserDefaults.standard.set(selectedHotkey.rawValue, forKey: Self.selectedHotkeyDefaultsKey)
            onSelectionChanged?()
        }
    }

    /// `HotkeyManager` sets this to reset any in-progress hold the moment
    /// the selection changes — without it, switching hotkeys mid-hold would
    /// leave the OLD key's release event permanently unmatched (the decoder
    /// only checks the NEWLY selected key's keycode), stranding
    /// `DictationCoordinator` in a "still recording" state with no event
    /// left that can ever end it.
    var onSelectionChanged: (() -> Void)?

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.selectedHotkeyDefaultsKey),
           let option = HotkeyOption(rawValue: raw) {
            selectedHotkey = option
        } else {
            selectedHotkey = .rightOption
        }
    }
}
