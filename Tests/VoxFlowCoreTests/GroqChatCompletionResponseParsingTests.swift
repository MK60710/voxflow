import Foundation
import Testing
@testable import VoxFlowCore

@Suite("GroqChatCompletionResponseParsing")
struct GroqChatCompletionResponseParsingTests {

    static func httpResponse(status: Int, url: URL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    @Test("a well-formed 200 response returns the trimmed message content")
    func successfulResponseReturnsContent() throws {
        let json = #"{"choices": [{"message": {"role": "assistant", "content": "  So basically, the deadline moved to Friday.  "}}]}"#
        let result = try GroqChatCompletionResponseParsing.parse(
            data: Data(json.utf8),
            httpResponse: Self.httpResponse(status: 200),
            engineName: "groq:llama-3.1-8b-instant"
        )
        #expect(result.text == "So basically, the deadline moved to Friday.")
        #expect(result.engineName == "groq:llama-3.1-8b-instant")
    }

    @Test("a nil httpResponse is surfaced as malformedResponse, not a crash")
    func nilHTTPResponseSurfaced() {
        #expect(throws: CleanupEngineError.self) {
            _ = try GroqChatCompletionResponseParsing.parse(data: Data(), httpResponse: nil, engineName: "groq:test")
        }
    }

    @Test("HTTP 429 is classified as rateLimited using the Retry-After header")
    func rateLimitSurfaced() throws {
        do {
            _ = try GroqChatCompletionResponseParsing.parse(
                data: Data(),
                httpResponse: Self.httpResponse(status: 429, headers: ["Retry-After": "9"]),
                engineName: "groq:test"
            )
            Issue.record("expected a rateLimited error")
        } catch let error as CleanupEngineError {
            #expect(error == .rateLimited(retryAfterSeconds: 9))
        }
    }

    @Test("a 200 response missing choices[0].message.content is malformedResponse")
    func missingContentIsMalformed() {
        let json = #"{"choices": []}"#
        do {
            _ = try GroqChatCompletionResponseParsing.parse(
                data: Data(json.utf8),
                httpResponse: Self.httpResponse(status: 200),
                engineName: "groq:test"
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

    @Test("non-JSON body on a 200 is malformedResponse, not a crash")
    func nonJSONBodySurfaced() {
        do {
            _ = try GroqChatCompletionResponseParsing.parse(
                data: Data([0xFF, 0x00, 0x11]),
                httpResponse: Self.httpResponse(status: 200),
                engineName: "groq:test"
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
