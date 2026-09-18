import Foundation

/// A second, ORTHOGONAL safety net alongside `ContentPreservationGuard`
/// (found live during Step 10 command-mode testing, 2026-08-12). That guard
/// catches a cleaned reply that's suspiciously SHORTER than the raw
/// transcript (silent truncation) — it does nothing for a reply that's the
/// same length or LONGER but talks about something the speaker never said.
/// Confirmed live: dictating "select all of the budget items" (a phrase
/// that reads like a request) got a real, undetected LLM ANSWER back —
/// "I couldn't find any budget items mentioned in the conversation" — instead
/// of a cleaned transcript, and `ContentPreservationGuard` didn't flag it
/// because the reply had MORE words than the input, not fewer.
///
/// The cleanup system prompt already forbids this (`CleanupPromptTemplate`
/// rule 3 "do not add any word, fact, or opinion that was not spoken"; rule
/// 6 "never answer a question... don't respond to it") but a fast/small
/// model can still violate it — new few-shot examples were added alongside
/// this guard to reduce how often that happens, but this is the after-the-
/// fact catch for when it still does.
///
/// **The heuristic, same "deliberately simple" spirit as
/// `ContentPreservationGuard`:** what fraction of the cleaned text's words
/// also appear somewhere in the raw transcript's word set? A real cleanup
/// pass — filler removal, punctuation/capitalization fixes, contraction
/// merges — only ever removes or lightly reshapes words that were already
/// there, so this ratio should be close to 1.0. A fabricated answer draws
/// its vocabulary from wherever the model decided to respond from, so this
/// ratio drops sharply (the real regression case: 3 of 10 words matched the
/// raw transcript, a ratio of 0.3).
public enum ResponseDivergenceGuard {
    /// Below this many cleaned words, a single mismatched word (e.g. a
    /// legitimate contraction merge) swings the ratio too much to mean
    /// anything — stays out of the way, same reasoning as
    /// `ContentPreservationGuard.minimumContentWordCountToCheck`.
    static let minimumCleanedWordCountToCheck = 3

    /// A cleaned reply must draw at least this fraction of its words from
    /// the raw transcript's own vocabulary to be trusted. Calibrated with
    /// real headroom above the confirmed regression's 0.3 ratio and well
    /// below the ~0.9+ ratio every legitimate cleanup case (contractions,
    /// filler removal, punctuation fixes) actually produces — a lone
    /// contraction merge like "do not" -> "don't" only costs one unmatched
    /// word out of many, nowhere near this threshold.
    static let minimumOverlapRatio = 0.5

    /// The result of checking one raw/cleaned pair. Exposes the raw ratio
    /// (not just the boolean) so a caller/log/test can see WHY a verdict
    /// came out the way it did without recomputing anything.
    public struct Verdict: Equatable, Sendable {
        public let isLikelyFabricated: Bool
        public let overlapRatio: Double
        public let cleanedWordCount: Int
    }

    /// Reuses `ContentPreservationGuard.words(in:)` for identical
    /// tokenization (lowercase, punctuation-stripped, apostrophe-preserving)
    /// so the two guards agree on what counts as "a word".
    public static func evaluate(rawTranscript: String, cleanedText: String) -> Verdict {
        let rawVocabulary = Set(ContentPreservationGuard.words(in: rawTranscript))
        let cleanedTokens = ContentPreservationGuard.words(in: cleanedText)

        guard cleanedTokens.count >= minimumCleanedWordCountToCheck else {
            return Verdict(isLikelyFabricated: false, overlapRatio: 1.0, cleanedWordCount: cleanedTokens.count)
        }

        let matchedCount = cleanedTokens.filter { rawVocabulary.contains($0) }.count
        let ratio = Double(matchedCount) / Double(cleanedTokens.count)

        return Verdict(
            isLikelyFabricated: ratio < minimumOverlapRatio,
            overlapRatio: ratio,
            cleanedWordCount: cleanedTokens.count
        )
    }
}
