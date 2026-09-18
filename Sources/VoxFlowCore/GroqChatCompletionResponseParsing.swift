import Foundation

/// Parses Groq's `/chat/completions` response (OpenAI-compatible shape:
/// `choices[0].message.content`). Mirrors
/// `GroqTranscriptionResponseParsing`'s split of "classify the HTTP layer"
/// from "parse the success body" so each half has independent tests.
public enum GroqChatCompletionResponseParsing {
    public static func parse(data: Data, httpResponse: HTTPURLResponse?, engineName: String) throws -> CleanupResult {
        guard let httpResponse else {
            throw CleanupEngineError.malformedResponse("No HTTP response from Groq")
        }

        guard httpResponse.statusCode == 200 else {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
            throw CleanupErrorClassifier.classify(
                httpStatus: httpResponse.statusCode,
                host: httpResponse.url?.host,
                retryAfterSeconds: retryAfter
            )
        }

        return try parseSuccessBody(data, engineName: engineName)
    }

    static func parseSuccessBody(_ data: Data, engineName: String) throws -> CleanupResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CleanupEngineError.malformedResponse("Response had no choices[0].message.content")
        }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return CleanupResult(text: cleaned, engineName: engineName)
    }
}
