import Foundation

/// Builds the JSON request for Groq's OpenAI-compatible
/// `/chat/completions` endpoint (blueprint Step 6: "free cloud LLM primary
/// is Groq llama-3.1-8b-instant"). Same key/base-URL as
/// `GroqTranscriptionEngine` — Groq hosts both the STT and chat-completions
/// APIs under one account. Pure and offline-testable, mirroring
/// `GroqMultipartRequestBuilder`'s split of "build the request" from
/// "send it".
public enum GroqChatCompletionRequestBuilder {
    /// Builds the POST request + JSON body. `messages` come from
    /// `CleanupPromptTemplate.messages(forTranscript:)`.
    public static func build(
        baseURL: URL,
        apiKey: String,
        model: String,
        messages: [CleanupPromptTemplate.ChatMessage],
        temperature: Double,
        maxTokens: Int?,
        reasoningEffort: String? = nil
    ) -> (request: URLRequest, body: Data) {
        let url = baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature
        ]
        if let maxTokens {
            payload["max_tokens"] = maxTokens
        }
        // 2026-08-30: reasoning-capable models (e.g. openai/gpt-oss-20b, the
        // replacement for the deprecated llama-3.1-8b-instant — confirmed
        // dead via a live 404 against Groq's API) burn real time thinking
        // before answering. "low" cuts reasoning tokens ~6x (171->27 in a
        // live test) and keeps completion time well inside the 600ms
        // cleanup budget. Omitted (not sent as null) for models that don't
        // support the param, since Groq/OpenAI-compatible endpoints reject
        // unknown fields on some models rather than ignoring them.
        if let reasoningEffort {
            payload["reasoning_effort"] = reasoningEffort
        }

        // JSONSerialization on a well-formed [String: Any] of only strings/
        // numbers/arrays never actually fails; the `?? Data()` exists so
        // this stays a non-throwing pure function (matching
        // GroqMultipartRequestBuilder's non-throwing shape) rather than one
        // more error case every call site has to handle for a case that
        // can't occur with this input shape.
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return (request, body)
    }
}
