import Foundation

/// State for the recording pill + menu bar icon. Kept AppKit-free so the
/// state machine and its display strings are unit-testable without a live
/// NSPanel/menu bar (see RecordingIndicatorStateTests).
public enum RecordingIndicatorState: Equatable {
    case idle
    case recording
    /// Tap-to-toggle mode (2026-08-13/14, Mihir's request — mirrors Wispr
    /// Flow's Fn+Space, though VoxFlow's own chord key is Right Command,
    /// not Space — see `HotkeyManager.onToggleModeRequested`'s doc comment
    /// for why): engaged by pressing the chord key while the hotkey is
    /// held, recording continues after the hotkey is released. A distinct
    /// case from `.recording` specifically so the pill can tell Mihir HOW
    /// to stop it — releasing does nothing in this mode, which would be
    /// confusing without an explicit label.
    case toggleRecording
    /// **Added 2026-09-08** (Mihir's report: multi-second dictations felt
    /// like they'd "timed out" with no visible sign anything was
    /// happening): the pill used to jump straight from `.recording` to
    /// `.idle` the instant the hotkey released, then sit on the neutral
    /// "Ready" pill for the ENTIRE STT+cleanup round trip — indistinguishable
    /// from doing nothing at all. Shown from the moment a recorded buffer is
    /// handed off to `TranscriptionCoordinator` until that pipeline
    /// concludes (`DictationCoordinator.dictationFinished()`).
    case transcribing
    case secureInputBlocked
    case permissionNeeded
    case aborted(reason: String)

    /// Text shown in the floating pill. Always non-nil now: the pill is
    /// persistent (2026-07-27, per Mihir's request for an always-visible
    /// Wispr-Flow-style indicator), showing a subtle "Ready" state when idle
    /// so there's constant visual confirmation VoxFlow is live and listening
    /// for the hotkey — and instant feedback the moment a hold-to-talk
    /// actually starts recording.
    public var pillMessage: String? {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording…"
        case .toggleRecording:
            return "Recording — tap hotkey to stop"
        case .transcribing:
            return "Transcribing…"
        case .secureInputBlocked:
            return "Blocked by secure input"
        case .permissionNeeded:
            return "Hotkey permission needed"
        case .aborted(let reason):
            return reason
        }
    }

    /// The idle "Ready" pill is rendered dimmer/quieter than active states so
    /// an always-on indicator isn't visually heavy — see PillView.
    public var isIdle: Bool { self == .idle }

    /// SF Symbol used for the menu bar icon in this state.
    public var menuBarSymbolName: String {
        switch self {
        case .idle:
            return "waveform.circle"
        case .recording, .toggleRecording, .transcribing:
            return "waveform.circle.fill"
        case .secureInputBlocked, .permissionNeeded, .aborted:
            return "exclamationmark.circle"
        }
    }

    /// Whether this state represents an error/warning condition (vs. the
    /// neutral `.idle`/`.recording` states) — drives the pill's color.
    public var isErrorState: Bool {
        switch self {
        case .idle, .recording, .toggleRecording, .transcribing:
            return false
        case .secureInputBlocked, .permissionNeeded, .aborted:
            return true
        }
    }

    public var isPillVisible: Bool { pillMessage != nil }
}
