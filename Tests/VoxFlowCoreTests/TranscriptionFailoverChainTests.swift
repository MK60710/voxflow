import Foundation
import Testing
@testable import VoxFlowCore

/// A fully-controllable stub `TranscriptionEngine` — no networking or real
/// Speech framework calls anywhere, used to test
/// `TranscriptionFailoverChain`'s ordering/first-success-wins logic in
/// isolation from any real Groq/Apple Speech implementation. Mirrors
/// `CleanupFailoverChainTests.swift`'s `StubCleanupEngine` shape exactly.
private final class StubTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    enum Behavior {
        case success(TranscriptionResult)
        case failure(Error)
    }

    let behavior: Behavior
    private(set) var callCount = 0
    private(set) var lastAudioFileURL: URL?
    private(set) var lastBiasPrompt: String??

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func transcribe(audioFileURL: URL, biasPrompt: String?) async throws -> TranscriptionResult {
        callCount += 1
        lastAudioFileURL = audioFileURL
        lastBiasPrompt = biasPrompt
        switch behavior {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}

@Suite("TranscriptionFailoverChain")
struct TranscriptionFailoverChainTests {

    static let testURL = URL(fileURLWithPath: "/tmp/voxflow-test.wav")

    @Test("a healthy primary is used and the secondary is never called")
    func healthyPrimaryShortCircuits() async throws {
        let primary = StubTranscriptionEngine(.success(TranscriptionResult(text: "From primary.", engineName: "primary")))
        let secondary = StubTranscriptionEngine(.success(TranscriptionResult(text: "From secondary.", engineName: "secondary")))
        let chain = TranscriptionFailoverChain(engines: [primary, secondary])

        let result = try await chain.transcribe(audioFileURL: Self.testURL, biasPrompt: nil)

        #expect(result.engineName == "primary")
        #expect(primary.callCount == 1)
        #expect(secondary.callCount == 0)
    }

    @Test("a failing primary falls over to the secondary, which succeeds")
    func failingPrimaryFallsOverToSecondary() async throws {
        let primary = StubTranscriptionEngine(.failure(TranscriptionEngineError.offline))
        let secondary = StubTranscriptionEngine(.success(TranscriptionResult(text: "From secondary.", engineName: "secondary")))
        let chain = TranscriptionFailoverChain(engines: [primary, secondary])

        let result = try await chain.transcribe(audioFileURL: Self.testURL, biasPrompt: nil)

        #expect(result.engineName == "secondary")
        #expect(primary.callCount == 1)
        #expect(secondary.callCount == 1)
    }

    @Test("if every engine fails, the FIRST engine's error is thrown, not the last (2026-08-13 bug fix)")
    func allEnginesFailingThrowsFirstError() async throws {
        // Real regression: the primary (Groq) failing with something
        // diagnostically important (rate-limited) must not get masked by
        // the secondary (Apple Speech)'s own, usually-secondary failure
        // reason — see TranscriptionFailoverChain.transcribe's doc comment.
        let primary = StubTranscriptionEngine(.failure(TranscriptionEngineError.rateLimited(retryAfterSeconds: 30)))
        let secondary = StubTranscriptionEngine(.failure(TranscriptionEngineError.localEngineUnavailable("asset not installed")))
        let chain = TranscriptionFailoverChain(engines: [primary, secondary])

        do {
            _ = try await chain.transcribe(audioFileURL: Self.testURL, biasPrompt: nil)
            Issue.record("expected an error to be thrown")
        } catch let error as TranscriptionEngineError {
            #expect(error == .rateLimited(retryAfterSeconds: 30))
        }
        #expect(primary.callCount == 1)
        #expect(secondary.callCount == 1)
    }

    @Test("a single-engine chain works with no fallback to reach")
    func singleEngineChainWorks() async throws {
        let only = StubTranscriptionEngine(.success(TranscriptionResult(text: "Transcribed.", engineName: "only")))
        let chain = TranscriptionFailoverChain(engines: [only])

        let result = try await chain.transcribe(audioFileURL: Self.testURL, biasPrompt: nil)
        #expect(result.text == "Transcribed.")
    }

    @Test("the audio file URL and bias prompt are forwarded unchanged to the primary")
    func forwardsAudioURLAndBiasPromptToPrimary() async throws {
        let primary = StubTranscriptionEngine(.success(TranscriptionResult(text: "Transcribed.", engineName: "primary")))
        let chain = TranscriptionFailoverChain(engines: [primary])

        _ = try await chain.transcribe(audioFileURL: Self.testURL, biasPrompt: "CogniSwitch, ContextOps")

        #expect(primary.lastAudioFileURL == Self.testURL)
        #expect(primary.lastBiasPrompt == "CogniSwitch, ContextOps")
    }

    @Test("when the primary fails over to the secondary, the secondary receives the SAME audio URL and bias prompt")
    func failoverForwardsSameParametersToSecondary() async throws {
        let primary = StubTranscriptionEngine(.failure(TranscriptionEngineError.offline))
        let secondary = StubTranscriptionEngine(.success(TranscriptionResult(text: "From secondary.", engineName: "secondary")))
        let chain = TranscriptionFailoverChain(engines: [primary, secondary])

        _ = try await chain.transcribe(audioFileURL: Self.testURL, biasPrompt: "Parakeet")

        #expect(primary.lastBiasPrompt == "Parakeet")
        #expect(secondary.lastBiasPrompt == "Parakeet")
        #expect(secondary.lastAudioFileURL == Self.testURL)
    }
}
