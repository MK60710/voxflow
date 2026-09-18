import Foundation
import Testing
@testable import VoxFlowCore

@Suite("CleanupOutcomeResolver")
struct CleanupOutcomeResolverTests {

    @Test("a successful non-empty cleanup result is used as-is, marked .cleaned")
    func successfulResultIsUsed() {
        let outcome: Result<CleanupResult, Error> = .success(
            CleanupResult(text: "So basically, the deadline moved to Friday.", engineName: "groq:llama-3.1-8b-instant")
        )
        let (text, source) = CleanupOutcomeResolver.resolve(
            originalTranscript: "um so basically the deadline moved to friday",
            cleanupOutcome: outcome
        )
        #expect(text == "So basically, the deadline moved to Friday.")
        #expect(source == .cleaned(engineName: "groq:llama-3.1-8b-instant"))
    }

    @Test("an empty cleaned result falls back to the raw transcript, not silently dropped")
    func emptyCleanedResultFallsBackToRaw() {
        let outcome: Result<CleanupResult, Error> = .success(
            CleanupResult(text: "", engineName: "groq:llama-3.1-8b-instant")
        )
        let (text, source) = CleanupOutcomeResolver.resolve(
            originalTranscript: "deploy the RAG pipeline to prod",
            cleanupOutcome: outcome
        )
        #expect(text == "deploy the RAG pipeline to prod")
        guard case .raw(let reason) = source else {
            Issue.record("expected .raw, got \(source)")
            return
        }
        #expect(reason.contains("empty"))
    }

    @Test("a timedOut failure falls back to raw with a budget-specific reason")
    func timedOutFallsBackToRawWithBudgetReason() {
        let outcome: Result<CleanupResult, Error> = .failure(CleanupEngineError.timedOut)
        let (text, source) = CleanupOutcomeResolver.resolve(
            originalTranscript: "the raw transcript",
            cleanupOutcome: outcome
        )
        #expect(text == "the raw transcript")
        guard case .raw(let reason) = source else {
            Issue.record("expected .raw, got \(source)")
            return
        }
        #expect(reason.contains("\(LatencyBudget.cleanupMs)ms"))
    }

    @Test("any other CleanupEngineError falls back to raw using its pillMessage as the reason")
    func otherCleanupErrorsFallBackToRawWithPillMessage() {
        let outcome: Result<CleanupResult, Error> = .failure(CleanupEngineError.offline)
        let (text, source) = CleanupOutcomeResolver.resolve(
            originalTranscript: "the raw transcript",
            cleanupOutcome: outcome
        )
        #expect(text == "the raw transcript")
        #expect(source == .raw(reason: CleanupEngineError.offline.pillMessage))
    }

    @Test("a non-CleanupEngineError failure still falls back to raw instead of propagating")
    func unrecognizedErrorStillFallsBackToRaw() {
        struct SomeOtherError: Error, LocalizedError {
            var errorDescription: String? { "some other failure" }
        }
        let outcome: Result<CleanupResult, Error> = .failure(SomeOtherError())
        let (text, source) = CleanupOutcomeResolver.resolve(
            originalTranscript: "the raw transcript",
            cleanupOutcome: outcome
        )
        #expect(text == "the raw transcript")
        guard case .raw = source else {
            Issue.record("expected .raw, got \(source)")
            return
        }
    }

    @Test("a fabricated/answered reply (the real 2026-08-12 bug) falls back to raw, not the answer")
    func fabricatedReplyFallsBackToRaw() {
        let outcome: Result<CleanupResult, Error> = .success(
            CleanupResult(text: "I couldn't find any budget items mentioned in the conversation", engineName: "groq:llama-3.1-8b-instant")
        )
        let (text, source) = CleanupOutcomeResolver.resolve(
            originalTranscript: "select all of the budget items",
            cleanupOutcome: outcome
        )
        #expect(text == "select all of the budget items")
        guard case .raw(let reason) = source else {
            Issue.record("expected .raw, got \(source)")
            return
        }
        #expect(reason.contains("answered instead of transcribing"))
    }

    @Test("the original transcript is NEVER lost on any failure path")
    func originalTranscriptNeverLostOnFailure() {
        let failures: [Result<CleanupResult, Error>] = [
            .failure(CleanupEngineError.timedOut),
            .failure(CleanupEngineError.offline),
            .failure(CleanupEngineError.rateLimited(retryAfterSeconds: nil)),
            .failure(CleanupEngineError.malformedResponse("bad json")),
            .success(CleanupResult(text: "", engineName: "x"))
        ]
        for failure in failures {
            let (text, _) = CleanupOutcomeResolver.resolve(originalTranscript: "keep me safe", cleanupOutcome: failure)
            #expect(text == "keep me safe")
        }
    }
}
