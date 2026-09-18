import Foundation
import Testing
@testable import VoxFlowCore

@Suite("OllamaChatRequestBuilder")
struct OllamaChatRequestBuilderTests {

    static let baseURL = URL(string: "http://localhost:11434")!

    @Test("builds a POST request against the api/chat path")
    func buildsCorrectURLAndMethod() {
        let (request, _) = OllamaChatRequestBuilder.build(
            baseURL: Self.baseURL,
            model: "llama3.2:3b",
            messages: [CleanupPromptTemplate.ChatMessage(role: "user", content: "hi")],
            temperature: 0
        )
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "http://localhost:11434/api/chat")
    }

    @Test("has no Authorization header — Ollama is a local, unauthenticated daemon")
    func noAuthorizationHeader() {
        let (request, _) = OllamaChatRequestBuilder.build(
            baseURL: Self.baseURL,
            model: "llama3.2:3b",
            messages: [],
            temperature: 0
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("body sets stream:false and nests temperature under options")
    func bodyShapeIsOllamaSpecific() throws {
        let (_, body) = OllamaChatRequestBuilder.build(
            baseURL: Self.baseURL,
            model: "llama3.2:3b",
            messages: [CleanupPromptTemplate.ChatMessage(role: "user", content: "um hello")],
            temperature: 0
        )
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "llama3.2:3b")
        #expect(json["stream"] as? Bool == false)
        let options = try #require(json["options"] as? [String: Any])
        #expect(options["temperature"] as? Double == 0)

        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["content"] as? String == "um hello")
    }
}
