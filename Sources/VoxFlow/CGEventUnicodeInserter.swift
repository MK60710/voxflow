import AppKit
import os.log
import VoxFlowCore

private let cgEventLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "CGEventInsert")

/// FALLBACK text-insertion strategy (blueprint Step 4, task 2): types text
/// directly via CGEvent unicode keyboard events instead of touching the
/// pasteboard at all. Used only if the pasteboard-swap strategy's write
/// fails outright.
///
/// `keyboardSetUnicodeString` only reliably carries a limited number of
/// UTF-16 units per event (the reference survey put this at ~20 —
/// `VoxFlowCore.UTF16Chunker`), so longer strings — and any string
/// containing emoji/astral-plane characters, which are surrogate PAIRS in
/// UTF-16 — are split into multiple key-down/key-up event pairs, never
/// splitting a surrogate pair across two events. S10 (command mode) reuses
/// this same CGEvent machinery for key-combo commands, per the blueprint.
@MainActor
final class CGEventUnicodeInserter {
    private static let maxUnitsPerChunk = UTF16Chunker.defaultMaxUnitsPerChunk

    /// Virtual key code used for every synthetic event here. Its value is
    /// irrelevant to what gets typed — `keyboardSetUnicodeString` overrides
    /// the character entirely — so `0` is fine as an arbitrary valid code.
    private static let dummyVirtualKeyCode: CGKeyCode = 0

    func insert(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else {
            os_log(.error, log: cgEventLog, "Couldn't create CGEventSource for unicode typing")
            return false
        }

        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: Self.maxUnitsPerChunk)
        guard !chunks.isEmpty else { return true }

        for chunk in chunks {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.dummyVirtualKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.dummyVirtualKeyCode, keyDown: false) else {
                os_log(.error, log: cgEventLog, "Couldn't create synthetic unicode key events")
                return false
            }
            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        }
        return true
    }
}
