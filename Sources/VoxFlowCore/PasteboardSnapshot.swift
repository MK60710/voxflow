import Foundation

/// A pure, AppKit-free snapshot of one pasteboard item's type→data
/// representations — enough to restore it exactly. The AppKit glue
/// (`Sources/VoxFlow/PasteboardCmdVInserter.swift`) converts real
/// `NSPasteboardItem`s to/from this type at the boundary, so the
/// save/restore data model is testable without a live NSPasteboard
/// (blueprint Step 4, task 6).
public struct PasteboardItemSnapshot: Equatable, Sendable {
    public var representations: [String: Data]

    public init(representations: [String: Data]) {
        self.representations = representations
    }
}

/// Outcome of polling the pasteboard's `changeCount` while deciding when
/// it's safe to restore the user's original clipboard contents after a
/// synthetic Cmd-V (blueprint Step 4, task 1: "restore ONLY after
/// NSPasteboard.changeCount polling confirms consumption — no blind fixed
/// delay").
///
/// Why polling instead of a fixed sleep: pasting doesn't itself change the
/// pasteboard (the receiving app only *reads* it), so there's no OS signal
/// for "the paste finished". What CAN be detected is whether anything ELSE
/// changed the pasteboard while we waited — another app, or critically, a
/// clipboard-manager race. So the real safety property isn't "did the app
/// consume it" but "is our written content still the untouched, current
/// pasteboard owner" — VoiceInk calls this an ownership-checked restore
/// (see docs/reference-report.md). This combines that ownership check with
/// a short minimum dwell (time for the synthetic key events to actually
/// reach the focused app) instead of one blind `sleep()`.
public enum ClipboardRestoreDecision: Equatable {
    /// Keep polling — not yet past the minimum dwell, and nothing has
    /// changed the pasteboard since our write.
    case keepPolling
    /// Safe to restore the original clipboard now: our write is still the
    /// pasteboard's current content (ownership intact) and enough time has
    /// passed for the paste to plausibly have reached the target app.
    case restore
    /// Hit `maxWait` without ever seeing the ownership check fail — restore
    /// anyway (best effort) so VoxFlow doesn't hold the user's clipboard
    /// hostage forever, but this path should be logged as a timeout, not
    /// treated as the routine case.
    case restoreTimedOut
    /// The pasteboard's `changeCount` no longer matches what we set it to —
    /// something else (a new user copy, a clipboard manager) now owns the
    /// clipboard. Restoring our stale snapshot over that would clobber
    /// content the user cares about more than VoxFlow's undo, so the
    /// restore is aborted and the pasteboard is left as-is.
    case abort

    /// - Parameters:
    ///   - postWriteChangeCount: `NSPasteboard.changeCount` read immediately
    ///     after VoxFlow wrote its transient content.
    ///   - currentChangeCount: `NSPasteboard.changeCount` read at this poll.
    ///   - elapsed: seconds since the transient write.
    ///   - minimumDwell: minimum time to wait before restoring even if
    ///     nothing has changed (gives the synthetic Cmd-V time to land).
    ///   - maxWait: hard ceiling — restore unconditionally past this point.
    public static func evaluate(
        postWriteChangeCount: Int,
        currentChangeCount: Int,
        elapsed: TimeInterval,
        minimumDwell: TimeInterval,
        maxWait: TimeInterval
    ) -> ClipboardRestoreDecision {
        guard currentChangeCount == postWriteChangeCount else {
            return .abort
        }
        if elapsed >= maxWait {
            return .restoreTimedOut
        }
        if elapsed >= minimumDwell {
            return .restore
        }
        return .keepPolling
    }
}
