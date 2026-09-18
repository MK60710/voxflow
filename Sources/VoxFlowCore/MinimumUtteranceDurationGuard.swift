import Foundation

/// A second, ORTHOGONAL pre-network guard alongside `SilenceDetector` —
/// confirmed live 2026-08-13: rapidly tapping the hotkey (testing
/// tap-to-toggle's stop mechanism) produced 20+ back-to-back recordings
/// under ~1.6s each, most under 1s, nearly all landing on Whisper's known
/// hallucination pattern ("Thank you." in several languages — the exact
/// phenomenon `SilenceDetector`'s own doc comment already documents from
/// Step 5a's original discovery). `SilenceDetector` didn't catch these: a
/// quick tap still picks up SOME real signal (room noise, a breath, mic
/// self-noise crossing the amplitude threshold), just no actual words —
/// amplitude alone can't tell those apart. Duration can: no real utterance
/// happens in a fraction of a second, so this is a second, independent
/// signal `DictationCoordinator` checks before ever reaching
/// `SilenceDetector` or the network.
public enum MinimumUtteranceDurationGuard {
    /// Below this, a recording is treated as an accidental tap rather than
    /// real speech.
    ///
    /// **Revised down from an original 1.0s (2026-08-13, same session,
    /// Mihir's direct correction):** 1.0s safely covered the multi-word
    /// commands measured live ("undo that"/"select all", 1.19s-1.39s), but
    /// Mihir pointed out a real, legitimate use case that threshold broke —
    /// a single short word like "Okay" is real content he wants inserted,
    /// and duration alone genuinely cannot distinguish a fast real word
    /// from an accidental noise-only tap; both can be equally short. Given
    /// that direct conflict, this now favors NOT silently dropping real
    /// short speech over catching every possible accidental-tap
    /// hallucination — 0.3s only rejects the clearest degenerate case (a
    /// near-instantaneous tap too fast for any word at all), well below
    /// what any real single-word utterance takes to say. This means some
    /// of the original incident's shortest garbage clips (0.29s was right
    /// at this line; 0.39s-0.99s will now pass through) will occasionally
    /// still reach Whisper and could still hallucinate — an accepted,
    /// explicit tradeoff, not an oversight.
    public static let minimumDurationSeconds: TimeInterval = 0.3

    public static func isTooShortForRealSpeech(_ duration: TimeInterval) -> Bool {
        duration < minimumDurationSeconds
    }
}
