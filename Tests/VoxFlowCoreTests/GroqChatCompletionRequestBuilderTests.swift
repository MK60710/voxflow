import Foundation
import Testing
@testable import VoxFlowCore

@Suite("GroqChatCompletionRequestBuilder")
struct GroqChatCompletionRequestBuilderTests {

    static let baseURL = URL(string: "https://api.groq.com/openai/v1")!

    @Test("builds a POST request against the chat/completions path")
    func buildsCorrectURLAndMethod() {
        let (request, _) = GroqChatCompletionRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "sk-test",
            model: "llama-3.1-8b-instant",
            messages: [CleanupPromptTemplate.ChatMessage(role: "user", content: "hi")],
            temperature: 0,
            maxTokens: nil
        )
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
    }

    @Test("sets a Bearer Authorization header with the exact key")
    func setsAuthorizationHeader() {
        let (request, _) = GroqChatCompletionRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "sk-real-looking-key",
            model: "llama-3.1-8b-instant",
            messages: [],
            temperature: 0,
            maxTokens: nil
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-real-looking-key")
    }

    @Test("body JSON contains model, temperature and every message in order")
    func bodyContainsExpectedFields() throws {
        let messages = [
            CleanupPromptTemplate.ChatMessage(role: "system", content: "You are a cleaner."),
            CleanupPromptTemplate.ChatMessage(role: "user", content: "um hello"),
            CleanupPromptTemplate.ChatMessage(role: "assistant", content: "Hello.")
        ]
        let (_, body) = GroqChatCompletionRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "sk-test",
            model: "llama-3.1-8b-instant",
            messages: messages,
            temperature: 0,
            maxTokens: 300
        )
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "llama-3.1-8b-instant")
        #expect(json["temperature"] as? Double == 0)
        #expect(json["max_tokens"] as? Int == 300)

        let jsonMessages = try #require(json["messages"] as? [[String: Any]])
        #expect(jsonMessages.count == 3)
        #expect(jsonMessages[0]["role"] as? String == "system")
        #expect(jsonMessages[1]["content"] as? String == "um hello")
        #expect(jsonMessages[2]["role"] as? String == "assistant")
    }

    @Test("omitting maxTokens leaves max_tokens out of the body entirely")
    func omittingMaxTokensLeavesItOut() throws {
        let (_, body) = GroqChatCompletionRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "sk-test",
            model: "llama-3.1-8b-instant",
            messages: [],
            temperature: 0,
            maxTokens: nil
        )
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["max_tokens"] == nil)
    }

    @Test("reasoningEffort, when provided, is sent as reasoning_effort in the body")
    func reasoningEffortIncludedWhenProvided() throws {
        let (_, body) = GroqChatCompletionRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "sk-test",
            model: "openai/gpt-oss-20b",
            messages: [],
            temperature: 0,
            maxTokens: nil,
            reasoningEffort: "low"
        )
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["reasoning_effort"] as? String == "low")
    }

    @Test("omitting reasoningEffort leaves reasoning_effort out of the body entirely")
    func omittingReasoningEffortLeavesItOut() throws {
        let (_, body) = GroqChatCompletionRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "sk-test",
            model: "llama-3.1-8b-instant",
            messages: [],
            temperature: 0,
            maxTokens: nil
        )
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["reasoning_effort"] == nil)
    }
}
