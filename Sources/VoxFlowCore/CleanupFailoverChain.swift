import Foundation

/// A `CleanupEngine` that tries each engine in order, first success wins —
/// `docs/architecture.md`'s "Failover is a chain of engines, not flags:
/// [primary, secondary] — first success wins, all-fail surfaces an error
/// pill" applied to cleanup (blueprint Step 6 task 2: "failover mirroring
/// Step 5a's TranscriptionEngine error-classification pattern"). The app
/// layer constructs this as `[GroqCleanupEngine, OllamaCleanupEngine]`; this
/// type itself doesn't know or care which concrete engines it holds, so
/// it's fully testable with mock `CleanupEngine` stubs.
public final class CleanupFailoverChain: CleanupEngine, @unchecked Sendable {
    private let engines: [CleanupEngine]

    /// `engines` must be non-empty — a zero-engine chain is a caller bug,
    /// not a runtime condition to recover from.
    public init(engines: [CleanupEngine]) {
        precondition(!engines.isEmpty, "CleanupFailoverChain needs at least one engine")
        self.engines = engines
    }

    public func clean(transcript: String) async throws -> CleanupResult {
        try await clean(transcript: transcript, tone: .neutral, dictionaryTerms: [], autoEditsEnabled: true, listFormattingEnabled: true)
    }

    /// Kept as a real override (not left to `CleanupEngine`'s default
    /// extension) so a caller using the older 3-parameter signature still
    /// dispatches through the actual chain — the protocol's own default
    /// for this signature just calls `self.clean(transcript:)`, which
    /// would silently ignore `tone`/`dictionaryTerms` for every engine in
    /// the chain. Delegates to the real widest override below with
    /// defaults, same "on by default" convention as everywhere else.
    public func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String]) async throws -> CleanupResult {
        try await clean(transcript: transcript, tone: tone, dictionaryTerms: dictionaryTerms, autoEditsEnabled: true, listFormattingEnabled: true)
    }

    /// Kept as a real override for the identical reason as the 3-parameter
    /// one above — without it, calling this signature on a chain would
    /// fall through to `CleanupEngine`'s default extension and silently
    /// ignore `listFormattingEnabled` for every engine in the chain.
    public func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool) async throws -> CleanupResult {
        try await clean(transcript: transcript, tone: tone, dictionaryTerms: dictionaryTerms, autoEditsEnabled: autoEditsEnabled, listFormattingEnabled: true)
    }

    /// List-formatting (2026-08-14): the REAL, widest override — forwards
    /// every parameter to each engine's own widest override in turn, first
    /// success wins. **Bug fixed 2026-08-13 (Step 11a):** same fix as
    /// `TranscriptionFailoverChain.transcribe` — this used to throw the
    /// LAST engine's error when every engine failed, which would mask a
    /// real Groq failure behind Ollama's own (usually secondary) failure
    /// reason. Now throws the FIRST engine's error: whichever engine is
    /// tried first is the one actually expected to serve the request in
    /// normal operation, so its failure reason is the one worth surfacing.
    public func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool, listFormattingEnabled: Bool) async throws -> CleanupResult {
        var firstError: Error?
        for engine in engines {
            do {
                return try await engine.clean(transcript: transcript, tone: tone, dictionaryTerms: dictionaryTerms, autoEditsEnabled: autoEditsEnabled, listFormattingEnabled: listFormattingEnabled)
            } catch {
                if firstError == nil {
                    firstError = error
                }
                continue
            }
        }
        throw firstError ?? CleanupEngineError.malformedResponse("No cleanup engines configured")
    }
}
