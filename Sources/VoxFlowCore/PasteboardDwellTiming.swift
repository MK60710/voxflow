import Foundation

/// How long `PasteboardCmdVInserter` should wait before restoring the
/// user's original clipboard after a synthetic Cmd-V, as a function of how
/// much text was pasted.
///
/// **Why this exists (2026-07-25 truncation-on-insertion bug fix).** The
/// previous fixed `minimumDwell = 0.12s` assumed every paste — three words
/// or ninety — reaches the target app and finishes being inserted within
/// the same short window. A live bug showed a ~90-word cleaned transcript
/// pasted into Terminal landing only partially before VoxFlow restored the
/// original clipboard mid-insertion: `ClipboardRestoreDecision`'s ownership
/// check only proves nothing else has WRITTEN to the pasteboard since our
/// write, not that the target app has finished READING/inserting it — and
/// for pty/terminal-backed apps in particular, a long paste can be fed into
/// the shell in chunks rather than consumed in one synchronous read.
/// VoiceInk (a mature open-source competitor, GPL-3.0 — pattern only, not
/// copied, per this repo's licensing rule; see
/// `references/VoiceInk/VoiceInk/Paste/CursorPaster.swift`) sidesteps this
/// with a flat 2.0s dwell for every paste, proven in real-world use. This
/// scales toward that same ceiling for longer text — rather than taxing
/// every paste with a flat 2s wait — while keeping the common case (a few
/// words) close to the original fast 0.12s baseline.
public enum PasteboardDwellTiming {
    /// Floor: the shortest dwell any paste gets, regardless of length —
    /// close to the original constant, since short insertions are the
    /// overwhelming majority of real usage and should stay snappy.
    static let baselineDwell: TimeInterval = 0.15

    /// Extra dwell added per character of the pasted text.
    static let perCharacterDwell: TimeInterval = 0.0035

    /// Ceiling: matches VoiceInk's own flat default for every paste — the
    /// real-world-proven number this scaling asymptotes toward for long
    /// dictations, not an arbitrary round number.
    static let maximumDwell: TimeInterval = 2.0

    /// How much longer `maxWait` allows beyond `minimumDwell` — genuine
    /// slack for the "ownership never breaks, but we're still polling"
    /// case, so the `restoreTimedOut` safety net stays a rare path rather
    /// than routinely firing right as `minimumDwell` is reached.
    static let maxWaitBuffer: TimeInterval = 1.0

    /// Absolute ceiling on `maxWait`, independent of text length — VoxFlow
    /// must never hold the user's clipboard hostage indefinitely.
    static let maximumMaxWait: TimeInterval = 3.5

    public struct Timing: Equatable {
        public let minimumDwell: TimeInterval
        public let maxWait: TimeInterval
    }

    /// - Parameter characterCount: length of the text being pasted
    ///   (`text.count`, Swift's grapheme-cluster count — close enough for a
    ///   timing heuristic; this doesn't need UTF-16-precise accounting the
    ///   way `UTF16Chunker`'s CGEvent-unicode fallback does).
    public static func timing(forCharacterCount characterCount: Int) -> Timing {
        let scaled = baselineDwell + Double(characterCount) * perCharacterDwell
        let dwell = min(maximumDwell, max(baselineDwell, scaled))
        let wait = min(maximumMaxWait, dwell + maxWaitBuffer)
        return Timing(minimumDwell: dwell, maxWait: wait)
    }
}
