import Foundation

/// Parses Ollama's `/api/chat` response (`{"message": {"role", "content"},
/// "done": true, ...}` — verified shape against a real local `ollama serve`
/// instance during Step 6). Ollama has no HTTP auth layer and no
/// `Retry-After`/rate-limit concept for a local daemon, so unlike
/// `GroqChatCompletionResponseParsing` this never produces `.rateLimited` —
/// non-200 here almost always means "model not pulled" (404) or "Ollama not
/// running" (connection refused, surfaced by `CleanupErrorClassifier`'s
/// `URLError` path before parsing is ever reached).
public enum OllamaChatResponseParsing {
    public static func parse(data: Data, httpResponse: HTTPURLResponse?, engineName: String) throws -> CleanupResult {
        guard let httpResponse else {
            throw CleanupEngineError.malformedResponse("No HTTP response from Ollama")
        }

        guard httpResponse.statusCode == 200 else {
            throw CleanupErrorClassifier.classify(
                httpStatus: httpResponse.statusCode,
                host: httpResponse.url?.host,
                retryAfterSeconds: nil
            )
        }

        return try parseSuccessBody(data, engineName: engineName)
    }

    static func parseSuccessBody(_ data: Data, engineName: String) throws -> CleanupResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CleanupEngineError.malformedResponse("Response had no message.content")
        }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return CleanupResult(text: cleaned, engineName: engineName)
    }
}
