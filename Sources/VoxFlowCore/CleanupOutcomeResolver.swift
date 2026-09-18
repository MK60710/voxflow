import Foundation

/// What actually happened to a piece of text on its way through cleanup —
/// drives the menu's "which engine served this" display and the pill/log
/// message when cleanup didn't happen. Deliberately not just a Bool: the
/// blueprint's failover visibility requirement (mirrored from Step 5b task
/// 3) wants to know WHICH engine served, and the raw-fallback path wants to
/// know WHY (disabled / raw-mode / timed out / all engines failed) so a
/// human reading the log can tell those apart.
public enum CleanupSource: Equatable, Sendable {
    case cleaned(engineName: String)
    case raw(reason: String)
}

/// Pure decision logic for "given the result of trying to clean this
/// transcript, what text do we actually insert, and what's the story for
/// the log/menu" — split out from `CleanupCoordinator` (App layer) so the
/// failover/fallback decision itself is unit-testable without any real
/// engine, network, or `MainActor` context (blueprint Step 6 task 5:
/// "tests ... failover logic").
public enum CleanupOutcomeResolver {
    /// `cleanupOutcome` is a `Result` rather than `throws` so call sites
    /// that already caught an error (e.g. from `CleanupLatencyGuard.run`)
    /// can hand it here directly without re-throwing/re-catching.
    public static func resolve(
        originalTranscript: String,
        cleanupOutcome: Result<CleanupResult, Error>
    ) -> (text: String, source: CleanupSource) {
        switch cleanupOutcome {
        case .success(let result):
            // "Never add content" cuts both ways: an engine that comes back
            // with an EMPTY string for a non-trivial transcript has failed
            // to do its job (rule 5 in the prompt only licenses an empty
            // reply for filler-only input) just as much as one that
            // paraphrases — treat it as a failure and fall back to raw
            // rather than silently dropping what the user said.
            guard !result.text.isEmpty else {
                return (originalTranscript, .raw(reason: "cleanup engine (\(result.engineName)) returned empty text"))
            }

            // Confirmed real bug (PROGRESS.md): a non-empty cleaned reply
            // can still silently drop the back half of a long transcript,
            // directly violating the prompt's own "do not drop content"
            // rule, without ever producing the empty-string signal the
            // check above catches. `ContentPreservationGuard` is the same
            // "raw text with a reason" fallback `CleanupLatencyGuard`
            // already uses for its 600ms timeout, applied to this
            // different failure shape.
            let verdict = ContentPreservationGuard.evaluate(rawTranscript: originalTranscript, cleanedText: result.text)
            guard !verdict.droppedTooMuchContent else {
                return (
                    originalTranscript,
                    .raw(reason: "cleanup engine (\(result.engineName)) dropped too much content (\(verdict.cleanedWordCount)/\(verdict.rawContentWordEstimate) words kept)")
                )
            }

            // Confirmed real bug (2026-08-12, Step 10 testing session): the
            // check above only catches a reply that's too SHORT. It says
            // nothing about a reply that's the same length or longer but
            // fabricated — the model answered a command/question-shaped
            // utterance ("select all of the budget items") instead of
            // cleaning it, and the truncation check above didn't notice
            // because the answer had MORE words than the input, not fewer.
            // `ResponseDivergenceGuard` is the orthogonal catch: does the
            // cleaned text's vocabulary actually come from what was said.
            let divergence = ResponseDivergenceGuard.evaluate(rawTranscript: originalTranscript, cleanedText: result.text)
            guard !divergence.isLikelyFabricated else {
                let overlapPercent = Int((divergence.overlapRatio * 100).rounded())
                return (
                    originalTranscript,
                    .raw(reason: "cleanup engine (\(result.engineName)) appears to have answered instead of transcribing (\(overlapPercent)% word overlap)")
                )
            }

            return (result.text, .cleaned(engineName: result.engineName))

        case .failure(let error):
            if let cleanupError = error as? CleanupEngineError {
                if cleanupError == .timedOut {
                    return (originalTranscript, .raw(reason: "cleanup exceeded \(LatencyBudget.cleanupMs)ms budget"))
                }
                return (originalTranscript, .raw(reason: cleanupError.pillMessage))
            }
            return (originalTranscript, .raw(reason: error.localizedDescription))
        }
    }
}
