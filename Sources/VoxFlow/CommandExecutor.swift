import AppKit
import os.log
import VoxFlowCore

private let commandLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "CommandExecutor")

/// Executes a recognized `VoiceCommand` (blueprint Step 10, task 2) as real
/// key events in the focused app, instead of typed text. Reuses S4's
/// `PasteboardCmdVInserter.synthesizeCmdV` four-event pattern (Command-down
/// → key-down → key-up → Command-up, each `interEventDelayNanoseconds`
/// apart) for the Cmd-combo commands, and the same pattern's plain form for
/// Return.
///
/// **Same layout-dependent-keycode caveat as S4's Cmd-V** (see
/// `PasteboardCmdVInserter.cmdVVirtualKeyCode`'s doc comment): `zVirtualKeyCode`
/// and `aVirtualKeyCode` identify PHYSICAL key positions, which type "Z" and
/// "A" only under US-like layouts — under AZERTY/Dvorak/etc. the physical
/// key at those positions may not trigger Undo/Select All. Return's virtual
/// key code is not a character key, so it doesn't carry this caveat.
@MainActor
enum CommandExecutor {
    private static let returnVirtualKeyCode: CGKeyCode = 36
    private static let zVirtualKeyCode: CGKeyCode = 6
    private static let aVirtualKeyCode: CGKeyCode = 0
    private static let commandVirtualKeyCode: CGKeyCode = 55
    private static let interEventDelayNanoseconds: UInt64 = 10_000_000

    static func execute(_ command: VoiceCommand) async {
        switch command {
        case .newLine:
            await postKey(returnVirtualKeyCode)
        case .newParagraph:
            await postKey(returnVirtualKeyCode)
            await postKey(returnVirtualKeyCode)
        case .undo:
            await postCombo(zVirtualKeyCode)
        case .selectAll:
            await postCombo(aVirtualKeyCode)
        }
    }

    /// A single key, no modifier — used for Return.
    private static func postKey(_ keyCode: CGKeyCode) async {
        guard let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            os_log(.error, log: commandLog, "Couldn't create synthetic key events for keyCode %{public}d", keyCode)
            return
        }
        keyDown.post(tap: .cgSessionEventTap)
        try? await Task.sleep(nanoseconds: interEventDelayNanoseconds)
        keyUp.post(tap: .cgSessionEventTap)
        try? await Task.sleep(nanoseconds: interEventDelayNanoseconds)
    }

    /// Command + one key, posted as four discrete events (real modifier
    /// transitions, not a flag bolted onto the letter's own events) — same
    /// shape as `PasteboardCmdVInserter.synthesizeCmdV`, generalized to any
    /// key code.
    private static func postCombo(_ keyCode: CGKeyCode) async {
        guard let source = CGEventSource(stateID: .privateState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandVirtualKeyCode, keyDown: true),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandVirtualKeyCode, keyDown: false) else {
            os_log(.error, log: commandLog, "Couldn't create synthetic Cmd-combo events for keyCode %{public}d", keyCode)
            return
        }
        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = []

        for event in [commandDown, keyDown, keyUp, commandUp] {
            event.post(tap: .cgSessionEventTap)
            try? await Task.sleep(nanoseconds: interEventDelayNanoseconds)
        }
    }
}
