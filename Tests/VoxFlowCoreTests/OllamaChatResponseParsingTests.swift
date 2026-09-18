import Foundation
import Testing
@testable import VoxFlowCore

@Suite("OllamaChatResponseParsing")
struct OllamaChatResponseParsingTests {

    static func httpResponse(status: Int, url: URL = URL(string: "http://localhost:11434/api/chat")!) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
    }

    @Test("a well-formed 200 response (real Ollama shape) returns the trimmed content")
    func successfulResponseReturnsContent() throws {
        // Exact shape verified against a real local `ollama serve` during
        // Step 6 — see OllamaCleanupEngine's doc comment.
        let json = #"{"model":"llama3.2:3b","message":{"role":"assistant","content":"  Hello there.  "},"done":true}"#
        let result = try OllamaChatResponseParsing.parse(
            data: Data(json.utf8),
            httpResponse: Self.httpResponse(status: 200),
            engineName: "ollama:llama3.2:3b"
        )
        #expect(result.text == "Hello there.")
        #expect(result.engineName == "ollama:llama3.2:3b")
    }

    @Test("a nil httpResponse is surfaced as malformedResponse, not a crash")
    func nilHTTPResponseSurfaced() {
        #expect(throws: CleanupEngineError.self) {
            _ = try OllamaChatResponseParsing.parse(data: Data(), httpResponse: nil, engineName: "ollama:test")
        }
    }

    @Test("HTTP 404 (model not pulled) is classified as httpError, not rateLimited")
    func http404IsHTTPErrorNotRateLimit() throws {
        do {
            _ = try OllamaChatResponseParsing.parse(
                data: Data(),
                httpResponse: Self.httpResponse(status: 404),
                engineName: "ollama:test"
            )
            Issue.record("expected an httpError")
        } catch let error as CleanupEngineError {
            guard case .httpError(let status, _) = error else {
                Issue.record("expected .httpError, got \(error)")
                return
            }
            #expect(status == 404)
        }
    }

    @Test("a 200 response missing message.content is malformedResponse")
    func missingContentIsMalformed() {
        let json = #"{"model":"llama3.2:3b","done":true}"#
        do {
            _ = try OllamaChatResponseParsing.parse(
                data: Data(json.utf8),
                httpResponse: Self.httpResponse(status: 200),
                engineName: "ollama:test"
            )
            Issue.record("expected malformedResponse")
        } catch let error as CleanupEngineError {
            guard case .malformedResponse = error else {
                Issue.record("expected .malformedResponse, got \(error)")
                return
            }
        } catch {
            Issue.record("expected CleanupEngineError, got \(error)")
        }
    }
}
