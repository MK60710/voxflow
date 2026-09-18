import Foundation

/// A real, confirmed bug (see PROGRESS.md's "Bug fix: cleanup silently
/// truncates long transcripts" entry): `CleanupPromptTemplate`'s own system
/// prompt says "Do not paraphrase. Do not rewrite for style. Do not
/// summarize. Do not add or drop content" (rule 3), but the model can still
/// violate that instruction and simply stop partway through a long,
/// multi-clause transcript — silently dropping the back half of what the
/// user actually said. That is NOT the same failure shape
/// `CleanupOutcomeResolver`'s existing empty-string check catches (rule 5's
/// legitimate "the whole thing was filler, correctly return empty" case) —
/// this is a *partial*, *silent* loss of real content in an otherwise
/// non-empty reply.
///
/// This guard is the same "raw text with a reason" pattern `CleanupLatencyGuard`
/// already uses for the 600ms timeout: pure, offline-testable decision logic
/// that `CleanupOutcomeResolver` consults before trusting a non-empty cleaned
/// result, with zero networking/AppKit dependencies (same house style as
/// `SilenceDetector`/`EngineStatusResolver`/`CleanupLatencyGuard`).
///
/// **The heuristic, deliberately simple (per the task's own "don't
/// overengineer this" instruction) — word-count retention, not semantic
/// diffing:**
/// 1. Estimate how many of the RAW transcript's words are "real content"
///    vs. filler, using a filler word/phrase list that's intentionally
///    BROADER than `CleanupPromptTemplate`'s own strict rule-1 list
///    (um/uh/like/you-know/I-mean). This list exists only to make this
///    guard's own estimate realistic — words like "so"/"yeah"/"okay" are
///    exactly the kind of loose interstitial word a legitimate cleanup pass
///    might also drop, and undercounting them would make ordinary light
///    cleanup look like a false-positive truncation.
/// 2. If that content estimate is small (below `minimumContentWordCountToCheck`),
///    skip the check entirely — this is what protects rule 5's legitimate
///    "entirely filler, correctly cleans to empty" case (e.g.
///    "um uh so yeah um" -> ""): there's too little real content for a
///    retention ratio to mean anything, so the guard stays out of the way.
/// 3. Otherwise, compare the CLEANED text's word count against that content
///    estimate. If the cleaned text retains less than `minimumRetentionRatio`
///    of the estimated content, treat it as suspected silent truncation.
///
/// **Calibration, against the real bug's actual numbers** (see
/// `ContentPreservationGuardTests.realBugRegressionCase` for the exact
/// strings): the raw transcript had 28 words, of which only "yeah"/"so"/
/// "okay" are arguably fillerish by this guard's own (loose) list — a
/// content estimate of 25. The cleaned reply that actually came back from
/// Groq had 14 words: a retention ratio of 14/25 ≈ 0.56. An ordinary light
/// cleanup pass (dropping one or two genuine filler words, tightening
/// punctuation, maybe merging "do not" into "don't") should retain close to
/// 100% of this guard's own content estimate, since that estimate ALREADY
/// discounted the filler being removed — so `minimumRetentionRatio = 0.7`
/// leaves real headroom (up to a 30% loss beyond what's already been
/// counted as filler) for that kind of minor, legitimate tightening,
/// while still catching the real bug's 0.56 ratio with margin to spare.
public enum ContentPreservationGuard {
    /// Multi-word filler phrases, checked as consecutive-token matches
    /// before single-word filler counting (kept separate from
    /// `fillerWords` since they're two tokens, not one).
    static let fillerPhrases: [[String]] = [
        ["you", "know"],
        ["i", "mean"],
        ["kind", "of"],
        ["sort", "of"]
    ]

    /// Single-word filler/interstitial tokens counted ONLY for this guard's
    /// own content-estimate — deliberately broader than
    /// `CleanupPromptTemplate.systemPrompt`'s strict rule-1 list. This
    /// guard isn't deciding what SHOULD be removed (the LLM/prompt owns
    /// that); it's sanity-checking how much COULD plausibly have been
    /// removed, so it needs to be generous about what counts as filler.
    static let fillerWords: Set<String> = [
        "um", "umm", "uh", "uhh", "er", "ah", "hm", "hmm",
        "like", "so", "well", "okay", "ok",
        "yeah", "yep", "yup", "right", "actually", "basically",
        "literally", "honestly", "just"
    ]

    /// Below this many estimated content words, the raw transcript is
    /// short/fillery enough that no retention-ratio check applies — this is
    /// what keeps rule 5's legitimate all-filler-to-empty case (and other
    /// very short utterances) from ever being flagged, no matter how much
    /// of it cleanup dropped.
    static let minimumContentWordCountToCheck = 6

    /// A cleaned reply must retain at least this fraction of the raw
    /// transcript's estimated content-word-count to be trusted. See the
    /// type-level doc comment above for the real-bug calibration this
    /// number is chosen against.
    static let minimumRetentionRatio = 0.7

    /// The result of checking one raw/cleaned pair. Exposes the raw
    /// numbers (not just the boolean) so a caller/log/test can see WHY a
    /// verdict came out the way it did without recomputing anything.
    public struct Verdict: Equatable, Sendable {
        public let droppedTooMuchContent: Bool
        public let rawContentWordEstimate: Int
        public let cleanedWordCount: Int
    }

    /// Splits text into lowercase word tokens on any non-letter/non-digit
    /// character except an internal apostrophe (so contractions like
    /// "don't" stay one token). Punctuation, casing and whitespace are
    /// otherwise irrelevant to this guard's purely-quantitative estimate.
    static func words(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { character in
                !(character.isLetter || character.isNumber || character == "'")
            })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// How many of `tokens` are consumed by filler phrase/word matches —
    /// phrases first (so e.g. "you know" is counted once as a 2-word
    /// phrase, not skipped because neither "you" nor "know" alone is in
    /// `fillerWords`), then remaining single-word filler tokens.
    static func fillerTokenCount(in tokens: [String]) -> Int {
        var consumed = [Bool](repeating: false, count: tokens.count)
        var count = 0

        for phrase in fillerPhrases where phrase.count <= tokens.count {
            var index = 0
            while index <= tokens.count - phrase.count {
                if !consumed[index], Array(tokens[index..<(index + phrase.count)]) == phrase {
                    for offset in 0..<phrase.count { consumed[index + offset] = true }
                    count += phrase.count
                    index += phrase.count
                } else {
                    index += 1
                }
            }
        }

        for (index, token) in tokens.enumerated() where !consumed[index] && fillerWords.contains(token) {
            count += 1
        }

        return count
    }

    /// The core check `CleanupOutcomeResolver` calls before trusting a
    /// non-empty cleaned result: does the cleaned text look like it kept
    /// most of what the raw transcript actually said?
    public static func evaluate(rawTranscript: String, cleanedText: String) -> Verdict {
        let rawTokens = words(in: rawTranscript)
        let cleanedWordCount = words(in: cleanedText).count
        let fillerCount = fillerTokenCount(in: rawTokens)
        let contentEstimate = max(0, rawTokens.count - fillerCount)

        guard contentEstimate >= minimumContentWordCountToCheck else {
            return Verdict(droppedTooMuchContent: false, rawContentWordEstimate: contentEstimate, cleanedWordCount: cleanedWordCount)
        }

        let retentionRatio = Double(cleanedWordCount) / Double(contentEstimate)
        return Verdict(
            droppedTooMuchContent: retentionRatio < minimumRetentionRatio,
            rawContentWordEstimate: contentEstimate,
            cleanedWordCount: cleanedWordCount
        )
    }
}
