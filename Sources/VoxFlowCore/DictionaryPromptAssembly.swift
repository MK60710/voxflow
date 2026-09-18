import Foundation

/// Turns the persisted dictionary (`DictionaryStore`) into the two prompt
/// shapes the blueprint's Step 8 names:
///
/// 1. A Whisper-style STT bias string, fed into the EXISTING
///    `TranscriptionEngine.transcribe(audioFileURL:biasPrompt:)` parameter
///    Step 5a already defined for exactly this purpose (the blueprint is
///    explicit: wire into that parameter, don't invent a new one).
/// 2. A cleanup-prompt spelling addendum ("these terms are spelled exactly:
///    …" — the blueprint's own literal wording), consumed by
///    `CleanupPromptTemplate`'s Step 8 addition.
///
/// Both share one pure, oldest-first truncation core so "mind prompt-length
/// caps; truncate oldest-first" (blueprint task 3) lives in exactly one
/// place instead of being reimplemented per call site. No networking, no
/// AppKit, no `DictionaryStore` dependency (takes plain entries/terms) —
/// fully offline-testable.
public enum DictionaryPromptAssembly {
    /// **Estimate, not independently re-verified against Groq's live docs
    /// this session** — this agent runs fully offline, so this number
    /// could not be checked against a real request the way this repo's own
    /// "verify before asserting" convention would prefer. OpenAI's Whisper
    /// `prompt` field (which Groq's OpenAI-compatible
    /// `/audio/transcriptions` endpoint is documented to inherit) has a
    /// widely-cited 224-token ceiling; at a rough ~4 characters/token for
    /// English that's ~900 characters. Budgeted deliberately conservative
    /// (600, not ~900) so this stays safely under the real cap even if the
    /// token estimate is off by a comfortable margin.
    /// **Mihir: worth confirming against Groq's current docs, especially
    /// before dictating with a very large real dictionary.**
    public static let sttBiasPromptMaxCharacters = 600

    /// The cleanup LLM's context window is far larger than Whisper's prompt
    /// field, but this still isn't unbounded — capped generously so a very
    /// large dictionary can't silently balloon every cleanup call's token
    /// cost or put pressure on the 600ms cleanup latency budget.
    public static let cleanupAddendumMaxCharacters = 2000

    /// Builds the STT bias string for Groq's Whisper `prompt` field.
    /// Returns `nil` when `entries` is empty so
    /// `GroqMultipartRequestBuilder.build`'s existing "omit the `prompt`
    /// form field entirely when nil/empty" behavior is unaffected by this
    /// step — S5a's own behavior (no dictionary yet) is preserved exactly.
    ///
    /// `entries` must already be in oldest-to-newest order (which is how
    /// `DictionaryStore.entries` is naturally maintained — an append-only
    /// array); this function truncates from the FRONT (oldest) first when
    /// the rendered prompt would exceed `maxCharacters`.
    public static func sttBiasPrompt(
        forEntries entries: [DictionaryEntry],
        maxCharacters: Int = sttBiasPromptMaxCharacters
    ) -> String? {
        guard !entries.isEmpty else { return nil }

        let prefix = "Vocabulary that may appear: "
        let suffix = "."

        func rendered(_ subset: [DictionaryEntry]) -> String {
            prefix + subset.map(renderedTerm).joined(separator: ", ") + suffix
        }

        var kept = entries
        while kept.count > 1 && rendered(kept).count > maxCharacters {
            kept.removeFirst() // oldest-first truncation
        }

        let result = rendered(kept)
        guard result.count <= maxCharacters else {
            // Pathological case: even a single entry doesn't fit (e.g. a
            // very long soundsLike hint) — hard-truncate rather than send
            // an over-cap prompt to Groq.
            return String(result.prefix(maxCharacters))
        }
        return result
    }

    /// Builds the "these terms are spelled exactly: …" cleanup addendum
    /// (blueprint Step 8's literal wording). Returns `nil` when `terms` is
    /// empty so `CleanupPromptTemplate`'s new dictionary-aware `messages`
    /// overload can fall back to the untouched plain
    /// `messages(forTranscript:)` path. Takes plain term strings (not
    /// `DictionaryEntry`) since cleanup only needs correct spelling, not the
    /// STT-only "sounds like" pronunciation hint.
    public static func cleanupSpellingAddendum(
        forTerms terms: [String],
        maxCharacters: Int = cleanupAddendumMaxCharacters
    ) -> String? {
        guard !terms.isEmpty else { return nil }

        let prefix = "These terms are spelled exactly: "
        let suffix = "."

        func rendered(_ subset: [String]) -> String {
            prefix + subset.joined(separator: ", ") + suffix
        }

        var kept = terms
        while kept.count > 1 && rendered(kept).count > maxCharacters {
            kept.removeFirst() // oldest-first truncation
        }

        let result = rendered(kept)
        guard result.count <= maxCharacters else {
            return String(result.prefix(maxCharacters))
        }
        return result
    }

    private static func renderedTerm(_ entry: DictionaryEntry) -> String {
        if let soundsLike = entry.soundsLike, !soundsLike.isEmpty {
            return "\(entry.term) (sounds like: \(soundsLike))"
        }
        return entry.term
    }
}
