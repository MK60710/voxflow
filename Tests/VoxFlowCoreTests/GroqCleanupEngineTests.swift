import Foundation
import Testing
@testable import VoxFlowCore

/// Mock transport so `GroqCleanupEngine`'s orchestration (key check → build
/// request → call transport → classify/parse) is fully testable OFFLINE —
/// mirrors `GroqTranscriptionEngineTests`'s `MockTranscriptionHTTPTransport`.
private final class MockCleanupHTTPTransport: CleanupHTTPTransport, @unchecked Sendable {
    enum Behavior {
        case success(data: Data, status: Int)
        case networkError(Error)
    }

    var behavior: Behavior
    private(set) var callCount = 0
    private(set) var lastRequest: URLRequest?
    private(set) var lastBody: Data?

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func send(request: URLRequest, bodyData: Data) async throws -> (Data, URLResponse) {
        callCount += 1
        lastRequest = request
        lastBody = bodyData

        switch behavior {
        case .success(let data, let status):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (data, response)
        case .networkError(let error):
            throw error
        }
    }
}

@Suite("GroqCleanupEngine")
struct GroqCleanupEngineTests {

    // MARK: - No-key path (never touches the network)

    @Test("no API key configured throws noAPIKeyConfigured without ever calling the transport")
    func noAPIKeyNeverCallsTransport() async throws {
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(), status: 200))
        let engine = GroqCleanupEngine(apiKeyProvider: { nil }, transport: transport)

        do {
            _ = try await engine.clean(transcript: "um hello")
            Issue.record("expected noAPIKeyConfigured to be thrown")
        } catch let error as CleanupEngineError {
            #expect(error == .noAPIKeyConfigured)
        }
        #expect(transport.callCount == 0)
    }

    @Test("an empty-string API key is treated the same as no key")
    func emptyStringKeyTreatedAsNoKey() async throws {
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(), status: 200))
        let engine = GroqCleanupEngine(apiKeyProvider: { "   " }, transport: transport)

        do {
            _ = try await engine.clean(transcript: "um hello")
            Issue.record("expected noAPIKeyConfigured to be thrown")
        } catch let error as CleanupEngineError {
            #expect(error == .noAPIKeyConfigured)
        }
        #expect(transport.callCount == 0)
    }

    // MARK: - Success path

    @Test("a successful response returns the parsed cleaned text and sends the Authorization header")
    func successfulResponseReturnsCleanedText() async throws {
        let json = #"{"choices": [{"message": {"role": "assistant", "content": "So basically, the deadline moved to Friday."}}]}"#
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = GroqCleanupEngine(apiKeyProvider: { "sk-real-looking-key" }, transport: transport)

        let result = try await engine.clean(transcript: "um so basically the uh the deadline moved to friday")

        #expect(result.text == "So basically, the deadline moved to Friday.")
        #expect(result.engineName == "groq:openai/gpt-oss-20b")
        #expect(transport.callCount == 1)
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-real-looking-key")
    }

    @Test("default configuration sends reasoning_effort=low (openai/gpt-oss-20b is a reasoning model)")
    func defaultConfigurationSendsLowReasoningEffort() async throws {
        let json = #"{"choices": [{"message": {"content": "Cleaned."}}]}"#
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = GroqCleanupEngine(apiKeyProvider: { "sk-test" }, transport: transport)

        _ = try await engine.clean(transcript: "um hello")

        let body = try #require(transport.lastBody)
        let json2 = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json2["reasoning_effort"] as? String == "low")
    }

    @Test("the request body includes the real transcript as the final message")
    func requestBodyIncludesTranscript() async throws {
        let json = #"{"choices": [{"message": {"content": "Cleaned."}}]}"#
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = GroqCleanupEngine(apiKeyProvider: { "key" }, transport: transport)

        _ = try await engine.clean(transcript: "the real raw transcript")

        let body = try #require(transport.lastBody)
        let json2 = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json2["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "the real raw transcript")
        #expect(json2["temperature"] as? Double == 0)
    }

    // MARK: - Error surface

    @Test("a URLError.notConnectedToInternet is classified as offline")
    func offlineErrorClassified() async throws {
        let transport = MockCleanupHTTPTransport(behavior: .networkError(URLError(.notConnectedToInternet)))
        let engine = GroqCleanupEngine(apiKeyProvider: { "key" }, transport: transport)

        do {
            _ = try await engine.clean(transcript: "hello")
            Issue.record("expected an offline error")
        } catch let error as CleanupEngineError {
            #expect(error == .offline)
        }
    }

    @Test("HTTP 429 from the transport is surfaced as rateLimited")
    func rateLimitErrorSurfaced() async throws {
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(), status: 429))
        let engine = GroqCleanupEngine(apiKeyProvider: { "key" }, transport: transport)

        do {
            _ = try await engine.clean(transcript: "hello")
            Issue.record("expected a rateLimited error")
        } catch let error as CleanupEngineError {
            #expect(error == .rateLimited(retryAfterSeconds: nil))
        }
    }

    @Test("a malformed 200 response is surfaced as malformedResponse, not a crash or hang")
    func malformedResponseSurfaced() async throws {
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data([0x00, 0x01, 0x02]), status: 200))
        let engine = GroqCleanupEngine(apiKeyProvider: { "key" }, transport: transport)

        do {
            _ = try await engine.clean(transcript: "hello")
            Issue.record("expected a malformedResponse error")
        } catch let error as CleanupEngineError {
            guard case .malformedResponse = error else {
                Issue.record("expected .malformedResponse, got \(error)")
                return
            }
        }
    }

    // MARK: - Step 7: tone forwarding
    //
    // `clean(transcript:)` (no tone) must remain byte-identical to
    // `.neutral` — the untouched Step 6 behavior every earlier test above
    // already exercises. These tests cover the NEW tone-aware path:
    // `clean(transcript:tone:)` must actually vary the request body's
    // system prompt per tone, not just accept-and-ignore the parameter.

    @Test("clean(transcript:) with no tone sends the exact same system prompt as clean(transcript:tone: .neutral)")
    func noToneArgumentMatchesExplicitNeutral() async throws {
        let json = #"{"choices": [{"message": {"content": "Cleaned."}}]}"#

        let transportA = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engineA = GroqCleanupEngine(apiKeyProvider: { "key" }, transport: transportA)
        _ = try await engineA.clean(transcript: "um so basically the deadline moved")

        let transportB = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engineB = GroqCleanupEngine(apiKeyProvider: { "key" }, transport: transportB)
        _ = try await engineB.clean(transcript: "um so basically the deadline moved", tone: .neutral)

        // Compare parsed structures, not raw bytes: JSONSerialization does
        // NOT guarantee identical key/dictionary ordering between two
        // independently-built payloads (even structurally-identical ones),
        // so a byte-for-byte Data comparison here is flaky by construction,
        // not a real signal. NSDictionary equality is order-independent.
        let bodyA = try #require(transportA.lastBody)
        let bodyB = try #require(transportB.lastBody)
        let dictA = try #require(try JSONSerialization.jsonObject(with: bodyA) as? NSDictionary)
        let dictB = try #require(try JSONSerialization.jsonObject(with: bodyB) as? NSDictionary)
        #expect(dictA == dictB)
    }

    @Test("clean(transcript:tone:) sends the tone-specific system prompt as the request's system message, for every tone")
    func toneSelectsMatchingSystemPromptInRequestBody() async throws {
        let json = #"{"choices": [{"message": {"content": "Cleaned."}}]}"#

        for tone in ToneProfile.allCases {
            let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
            let engine = GroqCleanupEngine(apiKeyProvider: { "key" }, transport: transport)

            // autoEditsEnabled/listFormattingEnabled: false — isolates
            // tone selection from either addendum, which would otherwise
            // append to the system message and break this exact-match
            // assertion.
            _ = try await engine.clean(transcript: "um so basically the deadline moved", tone: tone, dictionaryTerms: [], autoEditsEnabled: false, listFormattingEnabled: false)

            let body = try #require(transport.lastBody)
            let parsed = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try #require(parsed["messages"] as? [[String: Any]])
            let systemMessage = try #require(messages.first)
            #expect(systemMessage["role"] as? String == "system")
            #expect(systemMessage["content"] as? String == CleanupPromptTemplate.systemPrompt(for: tone))
        }
    }

    @Test("casual and professional tones produce genuinely different request bodies for the same transcript")
    func differentTonesProduceDifferentRequestBodies() async throws {
        let json = #"{"choices": [{"message": {"content": "Cleaned."}}]}"#

        let casualTransport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let casualEngine = GroqCleanupEngine(apiKeyProvider: { "key" }, transport: casualTransport)
        _ = try await casualEngine.clean(transcript: "hey are you free tonight", tone: .casual)

        let professionalTransport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let professionalEngine = GroqCleanupEngine(apiKeyProvider: { "key" }, transport: professionalTransport)
        _ = try await professionalEngine.clean(transcript: "hey are you free tonight", tone: .professional)

        #expect(casualTransport.lastBody != professionalTransport.lastBody)
    }
}
