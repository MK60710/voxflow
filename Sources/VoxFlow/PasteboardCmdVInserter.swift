import AppKit
import os.log
import VoxFlowCore

private let pasteboardLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "PasteboardInsert")

/// PRIMARY text-insertion strategy (blueprint Step 4, task 1): save the
/// current pasteboard (all types, all items), write the text marked as
/// transient (`org.nspasteboard.TransientType` — clipboard managers like
/// Maccy are supposed to skip capturing anything carrying this type per the
/// nspasteboard.org convention), synthesize Cmd-V, then restore the
/// original clipboard once `NSPasteboard.changeCount` polling says it's
/// safe. `VoxFlowCore.ClipboardRestoreDecision` owns that timing/ownership
/// logic (see its doc comment for why "polling for consumption" really
/// means an ownership check, not a literal read-detection signal).
@MainActor
final class PasteboardCmdVInserter {
    /// UTI the org.nspasteboard convention uses to mark pasteboard writes as
    /// transient/internal, so well-behaved clipboard managers skip
    /// recording them. See https://nspasteboard.org.
    static let transientTypeIdentifier = "org.nspasteboard.TransientType"

    /// Cmd-V's virtual key code under a US/ANSI layout (physical key
    /// position 9). NOTE — reused by S10's command-mode CGEvent work, and
    /// documented per the blueprint's own caveat: this code identifies a
    /// PHYSICAL key position, which types "V" only under US-like layouts.
    /// Under AZERTY/Dvorak/etc. the physical key at this position may not
    /// be "V" at all, so a synthetic Cmd+(code 9) may not trigger Paste on
    /// those layouts. VoiceInk's surveyed workaround (docs/reference-report.md)
    /// resorts to AppleScript's keystroke-by-character for a
    /// layout-independent path; VoxFlow does not implement that fallback
    /// yet — flagged here as a known limitation, not silently assumed away.
    private static let cmdVVirtualKeyCode: CGKeyCode = 9

    /// Command's own virtual key code (physical key position 55) — used to
    /// post a real, separate Cmd-down/Cmd-up pair around the V key events
    /// (see `synthesizeCmdV`'s doc comment for why), instead of folding
    /// `.maskCommand` onto V's own two events and calling that "Cmd-V".
    private static let commandVirtualKeyCode: CGKeyCode = 55

    /// Delay between each of the four posted key events in `synthesizeCmdV`
    /// — matches VoiceInk's own `pasteShortcutEventDelay` (10ms), found by
    /// reading `references/VoiceInk/VoiceInk/Paste/CursorPaster.swift`
    /// directly (GPL-3.0 — pattern only, not copied).
    private static let interEventDelayNanoseconds: UInt64 = 10_000_000

    private static let pollInterval: UInt64 = 20_000_000 // 20ms, in nanoseconds

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Returns `true` if the transient write + synthetic Cmd-V were
    /// dispatched successfully. This does NOT guarantee the target app
    /// accepted the paste — there's no OS signal for that (see
    /// `ClipboardRestoreDecision`'s doc comment) — only that VoxFlow
    /// successfully took over the pasteboard and posted the key events.
    /// Returns `false` only if writing our own transient content failed
    /// outright, which tells `SystemTextInserter` to fall back to the
    /// CGEvent-unicode path instead.
    func insert(_ text: String) async -> Bool {
        let originalItems = Self.snapshot(pasteboard)

        pasteboard.clearContents()
        let transientItem = NSPasteboardItem()
        transientItem.setString(text, forType: .string)
        transientItem.setData(Data(), forType: NSPasteboard.PasteboardType(Self.transientTypeIdentifier))
        guard pasteboard.writeObjects([transientItem]) else {
            os_log(.error, log: pasteboardLog, "Failed to write transient clipboard content — falling back to CGEvent unicode")
            return false
        }
        let postWriteChangeCount = pasteboard.changeCount

        await Self.synthesizeCmdV()

        // Scaled to the pasted text's length, not a flat constant — see
        // `PasteboardDwellTiming`'s doc comment for why a fixed short dwell
        // silently truncated long pastes.
        let timing = PasteboardDwellTiming.timing(forCharacterCount: text.count)
        await pollAndRestore(originalItems: originalItems, postWriteChangeCount: postWriteChangeCount, timing: timing)
        return true
    }

    private func pollAndRestore(
        originalItems: [PasteboardItemSnapshot],
        postWriteChangeCount: Int,
        timing: PasteboardDwellTiming.Timing
    ) async {
        let start = Date()
        while true {
            try? await Task.sleep(nanoseconds: Self.pollInterval)
            let elapsed = Date().timeIntervalSince(start)
            let decision = ClipboardRestoreDecision.evaluate(
                postWriteChangeCount: postWriteChangeCount,
                currentChangeCount: pasteboard.changeCount,
                elapsed: elapsed,
                minimumDwell: timing.minimumDwell,
                maxWait: timing.maxWait
            )
            switch decision {
            case .keepPolling:
                continue
            case .restore:
                Self.restore(originalItems, into: pasteboard)
                return
            case .restoreTimedOut:
                os_log(.info, log: pasteboardLog, "Clipboard restore timed out waiting for a clean poll window — restoring anyway")
                Self.restore(originalItems, into: pasteboard)
                return
            case .abort:
                os_log(.info, log: pasteboardLog, "Pasteboard changed since our write (new copy, or a clipboard manager) — leaving it as-is, not restoring")
                return
            }
        }
    }

    /// Posts four discrete events — Cmd-down, V-down, V-up, Cmd-up, each
    /// `interEventDelayNanoseconds` apart — instead of two V events with
    /// `.maskCommand` baked onto their flags and fired back-to-back with no
    /// pacing at all. The old approach (2026-07-23 through 2026-07-24) never
    /// posted an actual Command key-down/key-up transition, only a modifier
    /// *bit* on V's own events; most apps accept that, but it's a less
    /// faithful simulation of a real keypress than an app watching for
    /// genuine modifier-key transitions (rather than just reading flags on
    /// the letter event) would see. Paced to match VoiceInk's own proven
    /// sequence — read directly from
    /// `references/VoiceInk/VoiceInk/Paste/CursorPaster.swift`
    /// (`postPasteCommand`/`pasteShortcutEventDelay`, GPL-3.0, pattern only).
    private static func synthesizeCmdV() async {
        guard let source = CGEventSource(stateID: .privateState) else {
            os_log(.error, log: pasteboardLog, "Couldn't create CGEventSource for synthetic Cmd-V")
            return
        }
        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandVirtualKeyCode, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: cmdVVirtualKeyCode, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: cmdVVirtualKeyCode, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandVirtualKeyCode, keyDown: false)
        else {
            os_log(.error, log: pasteboardLog, "Couldn't create synthetic Cmd-V key events")
            return
        }
        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        // Command is still physically held at the moment V releases — a
        // real keyboard would report .maskCommand on this event too.
        vUp.flags = .maskCommand
        // No modifier is held once Command itself releases.
        commandUp.flags = []

        for event in [commandDown, vDown, vUp, commandUp] {
            event.post(tap: .cgSessionEventTap)
            try? await Task.sleep(nanoseconds: interEventDelayNanoseconds)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [PasteboardItemSnapshot] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type.rawValue] = data
                }
            }
            return PasteboardItemSnapshot(representations: representations)
        }
    }

    private static func restore(_ snapshots: [PasteboardItemSnapshot], into pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshots.isEmpty else { return }
        let items = snapshots.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (typeIdentifier, data) in snapshot.representations {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
