import Foundation

/// Builds the JSON request for Ollama's local `/api/chat` endpoint
/// (verified against a real `ollama serve` instance on this machine during
/// Step 6: `POST http://localhost:11434/api/chat` with
/// `{"model", "messages", "stream": false, "options": {"temperature"}}`
/// returns `{"message": {"role", "content"}, ...}`). Pure and
/// offline-testable, mirroring `GroqChatCompletionRequestBuilder`'s shape
/// even though the two wire formats differ slightly (Ollama nests
/// temperature under `options`, has no `Authorization` header since it's a
/// local, unauthenticated daemon, and needs `"stream": false` to get one
/// JSON object back instead of a newline-delimited stream).
public enum OllamaChatRequestBuilder {
    public static func build(
        baseURL: URL,
        model: String,
        messages: [CleanupPromptTemplate.ChatMessage],
        temperature: Double
    ) -> (request: URLRequest, body: Data) {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("chat")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
            "options": ["temperature": temperature]
        ]

        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return (request, body)
    }
}
