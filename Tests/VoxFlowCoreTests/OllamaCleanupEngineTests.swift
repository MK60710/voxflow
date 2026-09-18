import Foundation
import Testing
@testable import VoxFlowCore

/// Mock transport so `OllamaCleanupEngine` is fully testable OFFLINE, same
/// pattern as `GroqCleanupEngineTests`'s mock — no real Ollama daemon call
/// happens anywhere in this file.
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
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (data, response)
        case .networkError(let error):
            throw error
        }
    }
}

@Suite("OllamaCleanupEngine")
struct OllamaCleanupEngineTests {

    @Test("has no Keychain/API-key dependency at all — never blocks on a missing key")
    func noAPIKeyDependency() async throws {
        let json = #"{"message": {"content": "Cleaned."}}"#
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = OllamaCleanupEngine(transport: transport)

        let result = try await engine.clean(transcript: "um hello")
        #expect(result.text == "Cleaned.")
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("engineName includes the configured model")
    func engineNameIncludesModel() async throws {
        let json = #"{"message": {"content": "Cleaned."}}"#
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = OllamaCleanupEngine(
            transport: transport,
            configuration: OllamaCleanupEngine.Configuration(model: "llama3.2:3b")
        )

        let result = try await engine.clean(transcript: "um hello")
        #expect(result.engineName == "ollama:llama3.2:3b")
    }

    @Test("connection-refused (Ollama not running) classifies as offline, not a crash")
    func connectionRefusedClassifiedAsOffline() async throws {
        let transport = MockCleanupHTTPTransport(behavior: .networkError(URLError(.cannotConnectToHost)))
        let engine = OllamaCleanupEngine(transport: transport)

        do {
            _ = try await engine.clean(transcript: "hello")
            Issue.record("expected an offline error")
        } catch let error as CleanupEngineError {
            #expect(error == .offline)
        }
    }

    @Test("HTTP 404 (model not pulled) surfaces as httpError with the status code")
    func modelNotPulledSurfacesAsHTTPError() async throws {
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(), status: 404))
        let engine = OllamaCleanupEngine(transport: transport)

        do {
            _ = try await engine.clean(transcript: "hello")
            Issue.record("expected an httpError")
        } catch let error as CleanupEngineError {
            guard case .httpError(let status, _) = error else {
                Issue.record("expected .httpError, got \(error)")
                return
            }
            #expect(status == 404)
        }
    }

    @Test("request targets localhost:11434/api/chat by default")
    func defaultsToLocalhost() async throws {
        let json = #"{"message": {"content": "Cleaned."}}"#
        let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = OllamaCleanupEngine(transport: transport)

        _ = try await engine.clean(transcript: "hello")
        #expect(transport.lastRequest?.url?.absoluteString == "http://localhost:11434/api/chat")
    }

    // MARK: - Step 7: tone forwarding (same coverage as GroqCleanupEngineTests)

    @Test("clean(transcript:) with no tone sends the exact same request body as clean(transcript:tone: .neutral)")
    func noToneArgumentMatchesExplicitNeutral() async throws {
        let json = #"{"message": {"content": "Cleaned."}}"#

        let transportA = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engineA = OllamaCleanupEngine(transport: transportA)
        _ = try await engineA.clean(transcript: "um so basically the deadline moved")

        let transportB = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engineB = OllamaCleanupEngine(transport: transportB)
        _ = try await engineB.clean(transcript: "um so basically the deadline moved", tone: .neutral)

        // Compare parsed structures, not raw bytes — see
        // GroqCleanupEngineTests's identical test for why: JSONSerialization
        // doesn't guarantee stable dictionary-key ordering between two
        // independently-built payloads, so raw Data equality is flaky here.
        let bodyA = try #require(transportA.lastBody)
        let bodyB = try #require(transportB.lastBody)
        let dictA = try #require(try JSONSerialization.jsonObject(with: bodyA) as? NSDictionary)
        let dictB = try #require(try JSONSerialization.jsonObject(with: bodyB) as? NSDictionary)
        #expect(dictA == dictB)
    }

    @Test("clean(transcript:tone:) sends the tone-specific system prompt in the request body, for every tone")
    func toneSelectsMatchingSystemPromptInRequestBody() async throws {
        let json = #"{"message": {"content": "Cleaned."}}"#

        for tone in ToneProfile.allCases {
            let transport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
            let engine = OllamaCleanupEngine(transport: transport)

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
        let json = #"{"message": {"content": "Cleaned."}}"#

        let casualTransport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let casualEngine = OllamaCleanupEngine(transport: casualTransport)
        _ = try await casualEngine.clean(transcript: "hey are you free tonight", tone: .casual)

        let professionalTransport = MockCleanupHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let professionalEngine = OllamaCleanupEngine(transport: professionalTransport)
        _ = try await professionalEngine.clean(transcript: "hey are you free tonight", tone: .professional)

        #expect(casualTransport.lastBody != professionalTransport.lastBody)
    }
}
