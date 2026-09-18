import Foundation
import Testing
@testable import VoxFlowCore

/// A fully-controllable stub `CleanupEngine` — no networking anywhere,
/// used to test `CleanupFailoverChain`'s ordering/first-success-wins logic
/// in isolation from any real Groq/Ollama implementation.
private final class StubCleanupEngine: CleanupEngine, @unchecked Sendable {
    enum Behavior {
        case success(CleanupResult)
        case failure(Error)
    }

    let behavior: Behavior
    private(set) var callCount = 0

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func clean(transcript: String) async throws -> CleanupResult {
        callCount += 1
        switch behavior {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    // Deliberately does NOT override `clean(transcript:tone:dictionaryTerms:)`
    // — this stub exercises `CleanupEngine`'s combined default extension
    // implementation (ignores both tone and dictionary terms, delegates to
    // `clean(transcript:)` above), same as every pre-Step-7/8 conformer gets
    // for free. `ToneAndDictionaryCapturingStubCleanupEngine` below is the
    // one that overrides it to prove real forwarding of both parameters.
}

/// Step 7+8+9+listFormatting RECONCILED: unlike `StubCleanupEngine` above,
/// this stub DOES override the real, widest combined
/// `clean(transcript:tone:dictionaryTerms:autoEditsEnabled:listFormattingEnabled:)`
/// requirement and records EVERY parameter it was actually called with —
/// this is what proves `CleanupFailoverChain`'s widest `clean` really
/// forwards all of them to each engine's own override, rather than
/// silently falling through to the `CleanupEngine` default (which would
/// ignore them, per `CleanupEngine.swift`'s own doc comment).
///
/// Widened once per protocol widening (Step 7/8 reconciliation, then Step
/// 9, now list-formatting) — same reasoning each time: a stub that only
/// implements an older, narrower requirement silently falls through to
/// that requirement's own default when called through the newest
/// signature, which is exactly the gap each of these tests exists to
/// catch.
private final class ToneAndDictionaryCapturingStubCleanupEngine: CleanupEngine, @unchecked Sendable {
    enum Behavior {
        case success(CleanupResult)
        case failure(Error)
    }

    let behavior: Behavior
    private(set) var callCount = 0
    private(set) var lastToneReceived: ToneProfile?
    private(set) var lastDictionaryTermsReceived: [String]?
    private(set) var lastAutoEditsEnabledReceived: Bool?
    private(set) var lastListFormattingEnabledReceived: Bool?

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func clean(transcript: String) async throws -> CleanupResult {
        try await clean(transcript: transcript, tone: .neutral, dictionaryTerms: [], autoEditsEnabled: true, listFormattingEnabled: true)
    }

    func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool, listFormattingEnabled: Bool) async throws -> CleanupResult {
        callCount += 1
        lastToneReceived = tone
        lastDictionaryTermsReceived = dictionaryTerms
        lastAutoEditsEnabledReceived = autoEditsEnabled
        lastListFormattingEnabledReceived = listFormattingEnabled
        switch behavior {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}

@Suite("CleanupFailoverChain")
struct CleanupFailoverChainTests {

    @Test("a healthy primary is used and the secondary is never called")
    func healthyPrimaryShortCircuits() async throws {
        let primary = StubCleanupEngine(.success(CleanupResult(text: "Cleaned by primary.", engineName: "primary")))
        let secondary = StubCleanupEngine(.success(CleanupResult(text: "Cleaned by secondary.", engineName: "secondary")))
        let chain = CleanupFailoverChain(engines: [primary, secondary])

        let result = try await chain.clean(transcript: "hello")

        #expect(result.engineName == "primary")
        #expect(primary.callCount == 1)
        #expect(secondary.callCount == 0)
    }

    @Test("a failing primary falls over to the secondary, which succeeds")
    func failingPrimaryFallsOverToSecondary() async throws {
        let primary = StubCleanupEngine(.failure(CleanupEngineError.offline))
        let secondary = StubCleanupEngine(.success(CleanupResult(text: "Cleaned by secondary.", engineName: "secondary")))
        let chain = CleanupFailoverChain(engines: [primary, secondary])

        let result = try await chain.clean(transcript: "hello")

        #expect(result.engineName == "secondary")
        #expect(primary.callCount == 1)
        #expect(secondary.callCount == 1)
    }

    @Test("if every engine fails, the FIRST engine's error is thrown, not the last (2026-08-13 bug fix)")
    func allEnginesFailingThrowsFirstError() async throws {
        // Mirrors TranscriptionFailoverChain's identical fix: the primary's
        // failure reason is the one worth surfacing, not whichever fallback
        // engine happened to fail last.
        let primary = StubCleanupEngine(.failure(CleanupEngineError.rateLimited(retryAfterSeconds: 5)))
        let secondary = StubCleanupEngine(.failure(CleanupEngineError.offline))
        let chain = CleanupFailoverChain(engines: [primary, secondary])

        do {
            _ = try await chain.clean(transcript: "hello")
            Issue.record("expected an error to be thrown")
        } catch let error as CleanupEngineError {
            #expect(error == .rateLimited(retryAfterSeconds: 5))
        }
        #expect(primary.callCount == 1)
        #expect(secondary.callCount == 1)
    }

    @Test("a single-engine chain works with no fallback to reach")
    func singleEngineChainWorks() async throws {
        let only = StubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "only")))
        let chain = CleanupFailoverChain(engines: [only])

        let result = try await chain.clean(transcript: "hello")
        #expect(result.text == "Cleaned.")
    }

    // MARK: - Step 7: tone forwarding

    @Test("clean(transcript:tone:) forwards the real tone to the primary engine, not .neutral by default")
    func chainForwardsRealToneToPrimary() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "primary")))
        let chain = CleanupFailoverChain(engines: [primary])

        _ = try await chain.clean(transcript: "hello", tone: .casual)

        #expect(primary.lastToneReceived == .casual)
    }

    @Test("clean(transcript:) with no tone forwards .neutral through the chain")
    func chainForwardsNeutralWhenNoToneGiven() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "primary")))
        let chain = CleanupFailoverChain(engines: [primary])

        _ = try await chain.clean(transcript: "hello")

        #expect(primary.lastToneReceived == .neutral)
    }

    @Test("when the primary fails over to the secondary, the secondary receives the SAME tone the primary was called with")
    func failoverForwardsSameToneToSecondary() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.failure(CleanupEngineError.offline))
        let secondary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned by secondary.", engineName: "secondary")))
        let chain = CleanupFailoverChain(engines: [primary, secondary])

        let result = try await chain.clean(transcript: "hello", tone: .professional)

        #expect(result.engineName == "secondary")
        #expect(primary.lastToneReceived == .professional)
        #expect(secondary.lastToneReceived == .professional)
    }

    @Test("an engine that never overrides clean(transcript:tone:dictionaryTerms:) still works in a chain via the default extension (tone silently ignored, not a crash)")
    func chainStillWorksWithAToneUnawareEngine() async throws {
        // StubCleanupEngine (no combined override) proves the Step 7/8
        // protocol widening is non-breaking for any pre-existing,
        // not-yet-updated conformer.
        let toneUnaware = StubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "unaware")))
        let chain = CleanupFailoverChain(engines: [toneUnaware])

        let result = try await chain.clean(transcript: "hello", tone: .codeOrTerminal)

        #expect(result.text == "Cleaned.")
        #expect(toneUnaware.callCount == 1)
    }

    // MARK: - Step 8: dictionary-terms forwarding (mirrors Step 7's tone
    // forwarding coverage above — Step 8 alone didn't add chain-level
    // forwarding tests for its own parameter; added here as part of the
    // Step 7/Step 8 reconciliation so the merged behavior is verified with
    // the same rigor on both dimensions.)

    @Test("clean(transcript:dictionaryTerms:) forwards the real terms to the primary engine, not [] by default")
    func chainForwardsRealDictionaryTermsToPrimary() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "primary")))
        let chain = CleanupFailoverChain(engines: [primary])

        _ = try await chain.clean(transcript: "hello", dictionaryTerms: ["CogniSwitch", "ContextOps"])

        #expect(primary.lastDictionaryTermsReceived == ["CogniSwitch", "ContextOps"])
    }

    @Test("clean(transcript:) with no dictionary terms forwards an empty list through the chain")
    func chainForwardsEmptyDictionaryTermsWhenNoneGiven() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "primary")))
        let chain = CleanupFailoverChain(engines: [primary])

        _ = try await chain.clean(transcript: "hello")

        #expect(primary.lastDictionaryTermsReceived == [])
    }

    @Test("when the primary fails over to the secondary, the secondary receives the SAME dictionary terms the primary was called with")
    func failoverForwardsSameDictionaryTermsToSecondary() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.failure(CleanupEngineError.offline))
        let secondary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned by secondary.", engineName: "secondary")))
        let chain = CleanupFailoverChain(engines: [primary, secondary])

        let result = try await chain.clean(transcript: "hello", dictionaryTerms: ["Parakeet"])

        #expect(result.engineName == "secondary")
        #expect(primary.lastDictionaryTermsReceived == ["Parakeet"])
        #expect(secondary.lastDictionaryTermsReceived == ["Parakeet"])
    }

    @Test("clean(transcript:tone:dictionaryTerms:) forwards both parameters together to the primary")
    func chainForwardsBothToneAndDictionaryTermsTogether() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "primary")))
        let chain = CleanupFailoverChain(engines: [primary])

        _ = try await chain.clean(transcript: "hello", tone: .casual, dictionaryTerms: ["UMass"])

        #expect(primary.lastToneReceived == .casual)
        #expect(primary.lastDictionaryTermsReceived == ["UMass"])
    }

    // MARK: - Step 9: autoEditsEnabled forwarding (mirrors Step 7/8's own
    // forwarding coverage above)

    @Test("clean(transcript:tone:dictionaryTerms:autoEditsEnabled:) forwards the real value to the primary engine, not true by default")
    func chainForwardsRealAutoEditsEnabledToPrimary() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "primary")))
        let chain = CleanupFailoverChain(engines: [primary])

        _ = try await chain.clean(transcript: "hello", tone: .neutral, dictionaryTerms: [], autoEditsEnabled: false)

        #expect(primary.lastAutoEditsEnabledReceived == false)
    }

    @Test("clean(transcript:tone:dictionaryTerms:) with no autoEditsEnabled forwards true through the chain")
    func chainForwardsTrueWhenNoAutoEditsEnabledGiven() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "primary")))
        let chain = CleanupFailoverChain(engines: [primary])

        _ = try await chain.clean(transcript: "hello", tone: .neutral, dictionaryTerms: [])

        #expect(primary.lastAutoEditsEnabledReceived == true)
    }

    @Test("when the primary fails over to the secondary, the secondary receives the SAME autoEditsEnabled the primary was called with")
    func failoverForwardsSameAutoEditsEnabledToSecondary() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.failure(CleanupEngineError.offline))
        let secondary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned by secondary.", engineName: "secondary")))
        let chain = CleanupFailoverChain(engines: [primary, secondary])

        let result = try await chain.clean(transcript: "hello", tone: .neutral, dictionaryTerms: [], autoEditsEnabled: false)

        #expect(result.engineName == "secondary")
        #expect(primary.lastAutoEditsEnabledReceived == false)
        #expect(secondary.lastAutoEditsEnabledReceived == false)
    }

    // MARK: - List formatting forwarding (2026-08-14, mirrors Step 9's own
    // forwarding coverage above)

    @Test("clean(transcript:tone:dictionaryTerms:autoEditsEnabled:listFormattingEnabled:) forwards the real value to the primary engine, not true by default")
    func chainForwardsRealListFormattingEnabledToPrimary() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "primary")))
        let chain = CleanupFailoverChain(engines: [primary])

        _ = try await chain.clean(transcript: "hello", tone: .neutral, dictionaryTerms: [], autoEditsEnabled: true, listFormattingEnabled: false)

        #expect(primary.lastListFormattingEnabledReceived == false)
    }

    @Test("clean(transcript:tone:dictionaryTerms:autoEditsEnabled:) with no listFormattingEnabled forwards true through the chain")
    func chainForwardsTrueWhenNoListFormattingEnabledGiven() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned.", engineName: "primary")))
        let chain = CleanupFailoverChain(engines: [primary])

        _ = try await chain.clean(transcript: "hello", tone: .neutral, dictionaryTerms: [], autoEditsEnabled: true)

        #expect(primary.lastListFormattingEnabledReceived == true)
    }

    @Test("when the primary fails over to the secondary, the secondary receives the SAME listFormattingEnabled the primary was called with")
    func failoverForwardsSameListFormattingEnabledToSecondary() async throws {
        let primary = ToneAndDictionaryCapturingStubCleanupEngine(.failure(CleanupEngineError.offline))
        let secondary = ToneAndDictionaryCapturingStubCleanupEngine(.success(CleanupResult(text: "Cleaned by secondary.", engineName: "secondary")))
        let chain = CleanupFailoverChain(engines: [primary, secondary])

        let result = try await chain.clean(transcript: "hello", tone: .neutral, dictionaryTerms: [], autoEditsEnabled: true, listFormattingEnabled: false)

        #expect(result.engineName == "secondary")
        #expect(primary.lastListFormattingEnabledReceived == false)
        #expect(secondary.lastListFormattingEnabledReceived == false)
    }
}
