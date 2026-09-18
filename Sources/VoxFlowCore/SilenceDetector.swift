import Foundation

/// A local, pre-network silence check on the recorded buffer — added during
/// Step 5a after the mandated real-API verification surfaced a concrete gap
/// in the freeflow-ported hallucination filter (see
/// `GroqTranscriptionResponseParsing`): a 1.5s all-zero-sample WAV sent to
/// Groq's real `whisper-large-v3-turbo` endpoint came back
/// `"text": " Thank you."` with `no_speech_prob: 0` — i.e. Whisper
/// confidently hallucinated a phrase from the filter's own known-phrase
/// list, but reported LOW no-speech probability while doing it, which is
/// exactly the signal the server-side filter relies on to decide whether to
/// drop it. The filter as designed (matching freeflow's pattern, per the
/// blueprint) is kept unchanged for real transcribed content; this is a
/// belt-and-suspenders local check that runs BEFORE any network call, using
/// a signal Whisper's own response can't get wrong: the actual recorded
/// samples.
///
/// Deliberately conservative (very low threshold) so quiet real speech is
/// never mistaken for silence — see PROGRESS.md for why the exact threshold
/// is a documented approximation pending Mihir's live mic verification.
public enum SilenceDetector {
    /// Peak absolute sample amplitude below which a buffer is treated as
    /// silence. Digital silence is exactly 0.0; real mic self-noise in a
    /// quiet room is typically well below this on Apple Silicon built-in
    /// mics, while even quiet speech peaks far above it — but this hasn't
    /// been verified against Mihir's actual hardware yet (flagged in
    /// PROGRESS.md as a manual-verification item, not assumed correct).
    public static let defaultPeakAmplitudeThreshold: Float = 0.002

    /// `true` if the buffer never exceeds `peakAmplitudeThreshold` in
    /// absolute value — i.e. it's silence (or near-silence) and shouldn't
    /// be sent to any STT engine at all. An empty buffer counts as silent.
    public static func isSilent(_ samples: [Float], peakAmplitudeThreshold: Float = defaultPeakAmplitudeThreshold) -> Bool {
        guard !samples.isEmpty else { return true }
        var peak: Float = 0
        for sample in samples {
            let magnitude = abs(sample)
            if magnitude > peak {
                peak = magnitude
            }
            if peak >= peakAmplitudeThreshold {
                return false
            }
        }
        return true
    }
}
