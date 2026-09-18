import Foundation

/// A `TranscriptionEngine` that tries each engine in order, first success
/// wins — `docs/architecture.md`'s "Failover is a chain of engines, not
/// flags: [primary, secondary] — first success wins, all-fail surfaces an
/// error pill" applied to transcription (blueprint S5b task 3). Mirrors
/// `CleanupFailoverChain` exactly: the app layer constructs this as
/// `[GroqTranscriptionEngine, AppleSpeechTranscriptionEngine]` (or the
/// reverse, per the preferred-engine setting); this type doesn't know or
/// care which concrete engines it holds, so it's fully testable with mock
/// `TranscriptionEngine` stubs.
public final class TranscriptionFailoverChain: TranscriptionEngine, @unchecked Sendable {
    private let engines: [TranscriptionEngine]

    /// `engines` must be non-empty — a zero-engine chain is a caller bug,
    /// not a runtime condition to recover from.
    public init(engines: [TranscriptionEngine]) {
        precondition(!engines.isEmpty, "TranscriptionFailoverChain needs at least one engine")
        self.engines = engines
    }

    /// **Bug fixed 2026-08-13 (Step 11a):** used to throw the LAST engine's
    /// error when every engine failed. In the default `[groq, appleSpeech]`
    /// order, that meant a real Groq failure (e.g. rate-limited) got
    /// silently discarded in favor of Apple Speech's OWN, usually-secondary
    /// failure reason ("local engine unavailable") — confirmed live during
    /// Step 10 testing, where this masked a genuine Groq rate-limit behind
    /// a confusing "language asset not installed" pill message and cost
    /// real debugging time. Now throws the FIRST engine's error instead:
    /// whichever engine is tried first is the one actually expected to
    /// serve the request in normal operation (primary, or whichever the
    /// `preferLocalEngine` setting currently prefers), so its failure
    /// reason is the one most worth surfacing — later engines are fallback
    /// safety nets, and their own failure is secondary information.
    public func transcribe(audioFileURL: URL, biasPrompt: String?) async throws -> TranscriptionResult {
        var firstError: Error?
        for engine in engines {
            do {
                return try await engine.transcribe(audioFileURL: audioFileURL, biasPrompt: biasPrompt)
            } catch {
                if firstError == nil {
                    firstError = error
                }
                continue
            }
        }
        throw firstError ?? TranscriptionEngineError.malformedResponse("No transcription engines configured")
    }
}
