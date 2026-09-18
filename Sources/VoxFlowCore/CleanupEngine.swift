import Foundation

/// Result of a successful cleanup call. `engineName` identifies which
/// conformer actually served it (e.g. "groq:llama-3.1-8b-instant" or
/// "ollama:llama3.2:3b") so the menu/logs can show which engine served the
/// last utterance, mirroring the blueprint's failover visibility
/// requirement for `TranscriptionEngine` (Step 5b task 3) applied here too.
public struct CleanupResult: Equatable, Sendable {
    public let text: String
    public let engineName: String

    public init(text: String, engineName: String) {
        self.text = text
        self.engineName = engineName
    }
}

/// The engine protocol for Step 6 (blueprint task 2): transcript in, cleaned
/// text out. Deliberately narrower than `docs/architecture.md`'s original
/// sketch (`clean(_:tone:dictionary:)`) — S7 (tone) and S8 (dictionary)
/// don't exist yet, and the blueprint explicitly names the cleanup PROMPT
/// file (not this protocol) as the collision surface those two steps
/// extend. Documented here as a known future-extension point rather than
/// speculatively widening the signature now: see PROGRESS.md's Step 6
/// deviations note.
public protocol CleanupEngine: Sendable {
    func clean(transcript: String) async throws -> CleanupResult

    /// Step 7+8 RECONCILED requirement (see PROGRESS.md's Step 7/8 entries
    /// and the reconciliation entry below): Step 7 widened this protocol to
    /// `clean(transcript:tone:)`, Step 8 independently widened it to
    /// `clean(transcript:dictionaryTerms:)` — both branches predicted this
    /// exact collision in their own PROGRESS.md write-ups. Neither
    /// overload alone is kept as a protocol requirement; they're combined
    /// into one real requirement carrying both parameters, because a
    /// conformer needs to apply BOTH the tone-appropriate prompt variant AND
    /// the dictionary spelling bias in a single cleanup call, not one or the
    /// other depending on which overload happened to be called.
    ///
    /// Declared as a REAL protocol requirement (not just an extension
    /// method) for the same reason both source branches called out
    /// independently: extension-only methods are statically dispatched, so
    /// calling `.clean(transcript:tone:dictionaryTerms:)` through a
    /// `CleanupEngine` existential (how `CleanupCoordinator`/
    /// `CleanupFailoverChain` hold engines) would silently always run the
    /// default below and ignore any conformer's real override.
    ///
    /// `clean(transcript:tone:)` and `clean(transcript:dictionaryTerms:)`
    /// survive as extension convenience overloads further down this file
    /// (non-requirements, statically dispatched) purely so callers that only
    /// care about one dimension — including both branches' existing test
    /// suites — don't have to spell out the other parameter. Since every
    /// call site that matters (`GroqCleanupEngine`, `OllamaCleanupEngine`,
    /// `CleanupFailoverChain`) is a concrete type, not an existential, at
    /// the point these convenience overloads are invoked, static dispatch
    /// still lands on each type's real 3-parameter override.
    ///
    /// Step 9 note: this 3-parameter signature is now itself a NON-
    /// requirement convenience overload (see below) delegating into the
    /// REAL 4-parameter requirement with `autoEditsEnabled: true` — same
    /// "widen the real requirement, keep old arities as delegating
    /// overloads" pattern this file already used for Step 7/8, applied a
    /// third time.
    func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String]) async throws -> CleanupResult

    /// Step 9 (blueprint task 1/2, "auto-edits: scratch that"): widened
    /// further by the list-formatting requirement below — kept as a real
    /// protocol requirement (not just an extension method) for the exact
    /// same reason as always: extension-only methods are statically
    /// dispatched, so calling this signature through a `CleanupEngine`
    /// existential would silently always run the default and never reach a
    /// conformer's real prompt assembly.
    func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool) async throws -> CleanupResult

    /// List-formatting (2026-08-14, Mihir's request: format a dictated
    /// step-by-step process as a numbered list, one step per line): the
    /// REAL, widest protocol requirement, one parameter beyond Step 9's
    /// shape. Same "must be a real requirement, not an extension default"
    /// reasoning as every prior widening in this file.
    func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool, listFormattingEnabled: Bool) async throws -> CleanupResult
}

/// Default implementations of every combined requirement above. This is
/// what keeps each widening non-breaking: any conformer written before the
/// widening it's missing (`StubCleanupEngine` in tests, or a future engine
/// that never bothers with tone/dictionary/auto-edits/list-formatting)
/// automatically satisfies the protocol with zero code changes.
public extension CleanupEngine {
    func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String]) async throws -> CleanupResult {
        try await clean(transcript: transcript)
    }

    /// Delegates the OLD (Step 7/8) requirement into the Step 9 requirement
    /// with `autoEditsEnabled: true` — opt OUT, not opt in, matching
    /// `cleanupEnabled`'s convention. A conformer that only implements the
    /// 3-parameter requirement still satisfies this default — its cleanup
    /// just never sees correction semantics, a safe, honest fallback.
    func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool) async throws -> CleanupResult {
        try await clean(transcript: transcript, tone: tone, dictionaryTerms: dictionaryTerms)
    }

    /// Delegates the Step 9 requirement into the REAL, widest requirement
    /// with `listFormattingEnabled: true` — same "opt out, not opt in"
    /// convention, same reasoning as every delegation above.
    func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool, listFormattingEnabled: Bool) async throws -> CleanupResult {
        try await clean(transcript: transcript, tone: tone, dictionaryTerms: dictionaryTerms, autoEditsEnabled: autoEditsEnabled)
    }

    /// Convenience overload for tone-only callers (Step 7's original
    /// shape). Not a protocol requirement — see the doc comment above for
    /// why that's safe here.
    func clean(transcript: String, tone: ToneProfile) async throws -> CleanupResult {
        try await clean(transcript: transcript, tone: tone, dictionaryTerms: [], autoEditsEnabled: true)
    }

    /// Convenience overload for dictionary-only callers (Step 8's original
    /// shape). Not a protocol requirement — see the doc comment above for
    /// why that's safe here.
    func clean(transcript: String, dictionaryTerms: [String]) async throws -> CleanupResult {
        try await clean(transcript: transcript, tone: .neutral, dictionaryTerms: dictionaryTerms, autoEditsEnabled: true)
    }
}

/// Every way a cleanup attempt can fail, classified so the caller shows a
/// specific pill/log message instead of a raw error dump — mirrors
/// `TranscriptionEngineError`'s exact shape (blueprint Step 6 task 2:
/// "failover mirroring Step 5a's TranscriptionEngine error-classification
/// pattern"). Kept as a distinct type (not reusing `TranscriptionEngineError`
/// directly) since cleanup and transcription are different endpoints with
/// different failure semantics (e.g. cleanup's `.timedOut` is also produced
/// locally by `CleanupLatencyGuard`'s 600ms race, not just a network
/// timeout).
public enum CleanupEngineError: Error, Equatable, Sendable {
    case noAPIKeyConfigured
    case offline
    case rateLimited(retryAfterSeconds: Int?)
    case httpError(status: Int, message: String)
    case malformedResponse(String)
    case timedOut
    case cancelled
}

public extension CleanupEngineError {
    var pillMessage: String {
        switch self {
        case .noAPIKeyConfigured:
            return "Cleanup: no API key configured."
        case .offline:
            return "No internet connection — couldn't reach the cleanup service."
        case .rateLimited(let retryAfterSeconds):
            if let retryAfterSeconds {
                return "Cleanup rate limit hit — try again in \(retryAfterSeconds)s."
            }
            return "Cleanup rate limit hit — try again in a moment."
        case .httpError(_, let message):
            return message
        case .malformedResponse(let detail):
            return "Cleanup service returned an unexpected response: \(detail)"
        case .timedOut:
            return "Cleanup timed out — inserted raw transcript instead."
        case .cancelled:
            return "Cleanup cancelled."
        }
    }
}

/// Maps raw `URLError`s and HTTP status codes onto `CleanupEngineError` —
/// same shape as `TranscriptionErrorClassifier`, deliberately duplicated
/// (not shared) so the two endpoints' error surfaces can diverge later
/// without one file coupling both.
public enum CleanupErrorClassifier {
    public static func classify(networkError: Error) -> CleanupEngineError {
        if let cleanupError = networkError as? CleanupEngineError {
            return cleanupError
        }
        if let urlError = networkError as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed,
                 .secureConnectionFailed:
                return .offline
            case .timedOut:
                return .timedOut
            case .cancelled:
                return .cancelled
            default:
                return .malformedResponse(urlError.localizedDescription)
            }
        }
        return .malformedResponse((networkError as NSError).localizedDescription)
    }

    public static func classify(httpStatus: Int, host: String?, retryAfterSeconds: Int?) -> CleanupEngineError {
        if httpStatus == 429 {
            return .rateLimited(retryAfterSeconds: retryAfterSeconds)
        }
        return .httpError(status: httpStatus, message: friendlyMessage(status: httpStatus, host: host))
    }

    public static func friendlyMessage(status: Int, host: String?) -> String {
        let provider = host ?? "the cleanup service"
        switch status {
        case 401:
            return "Invalid API key for cleanup. Open Settings to fix it."
        case 403:
            return "Cleanup key lacks permission for this endpoint (HTTP 403)."
        case 404:
            return "Cleanup endpoint not found (HTTP 404)."
        case 413:
            return "Transcript too large for the cleanup request (HTTP 413)."
        case 400:
            return "Cleanup request rejected (HTTP 400). Check the model name."
        case 500..<600:
            return "Server error at \(provider) (HTTP \(status)). Try again in a moment."
        default:
            return "Cleanup request failed (HTTP \(status))."
        }
    }
}
