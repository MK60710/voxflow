import Foundation

/// Pure decoding of a `flagsChanged` CGEvent's raw keycode + flags bits into
/// a Right-Option press/release transition — no CoreGraphics/AppKit import,
/// so it's unit-testable offline (see HotkeyFlagsDecoderTests) independent
/// of a live CGEventTap, matching this repo's existing pattern of splitting
/// pure logic out of `Sources/VoxFlow`'s live system-integration types (see
/// `LatencyInstrumentation`, `RecordingIndicatorState`).
///
/// **Why this exists (2026-07-23 tap-disable bug fix):** `HotkeyManager`'s
/// CGEventTap callback used to construct an `NSEvent` from every single
/// system-wide `flagsChanged` CGEvent (every Shift-for-a-capital, every
/// Cmd-shortcut, anywhere on the system — not just Right Option) purely to
/// read `.keyCode`/`.modifierFlags`. Measured cost of that construction:
/// ~16us per call vs ~0.09us for reading the same information directly off
/// the raw `CGEvent` (`getIntegerValueField(.keyboardEventKeycode)` +
/// `.flags.rawValue`) — see PROGRESS.md for the exact benchmark. Apple's own
/// `CGEventTapCallBack` docs warn that a slow callback risks the OS
/// disabling the tap; this is the single most avoidable cost in a callback
/// that's expected to run essentially immediately, on every modifier-key
/// event system-wide, not just VoxFlow's own hotkey.
public enum HotkeyFlagsDecoder {
    /// NX_DEVICERALTKEYMASK — the device-specific bit macOS sets in a real
    /// `flagsChanged` event's raw flags word to distinguish Right Option
    /// from Left Option (which sets `deviceLeftOptionMask`, 0x20, instead).
    /// `NSEvent.modifierFlags` exposes the exact same underlying bit via its
    /// device-specific NX masks (see freeflow's `ModifierKeyEventState.swift`,
    /// MIT-licensed, referenced from `HotkeyManager.swift`) — this is that
    /// same bit read directly off `CGEventFlags.rawValue`, confirmed to
    /// match NSEvent's own interpretation bit-for-bit (see
    /// HotkeyFlagsDecoderTests' parity cases).
    public static let deviceRightOptionMask: UInt64 = 0x40

    /// NX_DEVICELALTKEYMASK — Left Option's equivalent bit. Only used here
    /// to prove Left Option does NOT set the right-option bit (negative test
    /// coverage); VoxFlow's hotkey is Right Option only.
    public static let deviceLeftOptionMask: UInt64 = 0x20

    /// Device-independent Shift bit (`kCGEventFlagMaskShift`) — read only to
    /// report whether Shift was ALSO down at the moment the hotkey's
    /// transition is reported (Step 6's raw-mode modifier), not to identify
    /// the hotkey itself.
    public static let shiftMask: UInt64 = 0x20000

    /// A decoded hotkey transition.
    public struct Transition: Equatable {
        public let isDown: Bool
        public let shiftHeld: Bool

        public init(isDown: Bool, shiftHeld: Bool) {
            self.isDown = isDown
            self.shiftHeld = shiftHeld
        }
    }

    /// - Parameters:
    ///   - keyCode: raw CGEvent keyboard-event keycode field
    ///     (`event.getIntegerValueField(.keyboardEventKeycode)`).
    ///   - flags: raw `CGEventFlags.rawValue` off the same event.
    ///   - hotkey: VoxFlow's currently-configured hotkey (Step 11a task 2 —
    ///     previously always `.rightOption`; now user-selectable).
    /// - Returns: `nil` if `keyCode` isn't the hotkey's keycode — this is
    ///   the hot path for the ~99% of real-world system-wide `flagsChanged`
    ///   events that aren't the hotkey at all, and costs nothing beyond this
    ///   one integer compare. Otherwise the decoded down/up + shift state,
    ///   computed with one more bitmask check against `hotkey`'s own device
    ///   mask.
    public static func decode(keyCode: Int64, flags: UInt64, hotkey: HotkeyOption) -> Transition? {
        guard keyCode == hotkey.virtualKeyCode else { return nil }
        let isDown = flags & hotkey.deviceMask != 0
        let shiftHeld = flags & shiftMask != 0
        return Transition(isDown: isDown, shiftHeld: shiftHeld)
    }
}

/// The modifier keys VoxFlow can be configured to hold-to-talk with.
/// Deliberately modifier-only, not an arbitrary key/chord — the whole
/// hold-to-talk mechanism is built on `flagsChanged` events (see
/// `HotkeyManager`'s doc comment), which only modifier keys generate, and
/// a chord doesn't map naturally onto a "hold" gesture the way a single
/// modifier does.
///
/// **Narrowed 2026-08-24 (Mihir's direct request, live smoke-test
/// feedback) from {Right Option, Right Command, Right Control, Fn} to
/// exactly these 4 — Right Control and Fn dropped, Left Option/Left
/// Command added.** Two real problems drove this: (1) many Mac keyboards
/// (MacBooks especially) have no physical Right Control key at all, so
/// offering it as a picker option was broken for a chunk of users out of
/// the gate; (2) Option and Command are the pair most people already
/// associate with a left/right hand-dominance choice, and offering all
/// four Option/Command combinations (not just the right-side ones) is
/// what Mihir actually wants — Control and Fn don't fit that same
/// left/right mental model and add option-picker clutter for a case
/// (Fn/Control as a hold-to-talk key) nobody asked for.
///
/// `virtualKeyCode` values are Apple's own public Carbon constants
/// (`Carbon/HIToolbox/Events.h`'s `kVK_*`), not private API — safe to
/// state without the same "confirmed against this machine's real SDK
/// header" caveat the device-mask bits below need, since these are
/// documented. `deviceMask` values ARE private/undocumented
/// (`IOKit/hidsystem/IOLLEvent.h`'s `NX_DEVICE*KEYMASK` bits) — the
/// right-side pair was confirmed 2026-08-12 directly against this
/// machine's real SDK header; the left-side pair added here
/// (`NX_DEVICELALTKEYMASK`/`NX_DEVICELCMDKEYMASK`) is the same
/// documented-nowhere-but-verified-on-device bit family, and
/// `NX_DEVICELALTKEYMASK` (0x20) was ALREADY present and verified in this
/// file as `deviceLeftOptionMask` above (used there only for a negative
/// test) before this rework needed it as a real, live option.
public enum HotkeyOption: String, CaseIterable, Equatable, Sendable, Codable {
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand

    /// kVK_* virtual key code identifying which physical key generated the
    /// `flagsChanged` event.
    public var virtualKeyCode: Int64 {
        switch self {
        case .leftOption: return 58    // kVK_Option       (0x3A)
        case .rightOption: return 61   // kVK_RightOption  (0x3D)
        case .leftCommand: return 55   // kVK_Command      (0x37)
        case .rightCommand: return 54  // kVK_RightCommand (0x36)
        }
    }

    /// The device-specific bit set in a `flagsChanged` event's raw flags
    /// word while THIS specific key is held.
    public var deviceMask: UInt64 {
        switch self {
        case .leftOption: return 0x20       // NX_DEVICELALTKEYMASK
        case .rightOption: return 0x40      // NX_DEVICERALTKEYMASK
        case .leftCommand: return 0x08      // NX_DEVICELCMDKEYMASK
        case .rightCommand: return 0x10     // NX_DEVICERCMDKEYMASK
        }
    }

    public var displayName: String {
        switch self {
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        }
    }

    /// Tap-to-toggle's chord companion — the other Option/Command key on
    /// the SAME side as this one. Replaces the old hardcoded
    /// `.rightCommand` companion, which silently disabled tap-to-toggle
    /// entirely whenever Right Command itself was picked as the primary
    /// hotkey (see `HotkeyManager.handleFlagsChanged`'s old guard, removed
    /// in the same change that added this). Computed, not stored, so it's
    /// impossible for a primary hotkey to ever equal its own companion.
    public var tapToggleCompanion: HotkeyOption {
        switch self {
        case .leftOption: return .leftCommand
        case .rightOption: return .rightCommand
        case .leftCommand: return .leftOption
        case .rightCommand: return .rightOption
        }
    }
}
