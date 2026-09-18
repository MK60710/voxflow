import Foundation

/// Parses Groq's `/audio/transcriptions` response and applies the Whisper
/// hallucination filter (blueprint Step 5a: "verbose_json response format to
/// get segment metadata for a hallucination filter — drop segments with
/// high no-speech probability"). Filter phrase list, threshold, and
/// filtering logic are ported directly from freeflow's
/// `TranscriptionService.isHallucination`/`parseTranscript` (MIT — verified
/// in references/freeflow/LICENSE), since the blueprint names this exact
/// pattern as copy-ready.
public enum GroqTranscriptionResponseParsing {
    /// Whisper-large-v3(-turbo) hallucinates these common short phrases on
    /// silence/background noise. Only filtered when Groq's own
    /// `no_speech_prob` for that segment is also high — conservative by
    /// design, to avoid dropping real speech that happens to match one of
    /// these phrases (e.g. someone actually saying "thank you").
    static let hallucinationPhrases: Set<String> = [
        "thank you",
        "thank you for watching",
        "thank you very much",
        "thank you so much",
        "thanks for watching",
        "please subscribe",
        "like and subscribe",
        "subtitles by",
        "subtitles by the amara.org community",
        "you"
    ]

    static let hallucinationNoSpeechThreshold = 0.1

    /// `httpResponse` is `nil` only if the transport returned something that
    /// wasn't even an `HTTPURLResponse` (shouldn't happen over HTTPS, but
    /// treated as malformed rather than force-unwrapped). `engineName`
    /// mirrors `GroqChatCompletionResponseParsing.parse`'s exact same
    /// parameter (S5b: `TranscriptionResult` now carries `engineName` too).
    public static func parse(data: Data, httpResponse: HTTPURLResponse?, engineName: String) throws -> TranscriptionResult {
        guard let httpResponse else {
            throw TranscriptionEngineError.malformedResponse("No HTTP response from Groq")
        }

        guard httpResponse.statusCode == 200 else {
            let retryAfter = (httpResponse.value(forHTTPHeaderField: "Retry-After")).flatMap { Int($0) }
            throw TranscriptionErrorClassifier.classify(
                httpStatus: httpResponse.statusCode,
                host: httpResponse.url?.host,
                retryAfterSeconds: retryAfter
            )
        }

        return try parseSuccessBody(data, engineName: engineName)
    }

    static func parseSuccessBody(_ data: Data, engineName: String) throws -> TranscriptionResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw TranscriptionEngineError.malformedResponse("Response had no \"text\" field")
        }

        if isHallucination(text: text, json: json) {
            return TranscriptionResult(text: "", engineName: engineName)
        }
        return TranscriptionResult(text: text, engineName: engineName)
    }

    static func isHallucination(text: String, json: [String: Any]) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        guard hallucinationPhrases.contains(normalized) else {
            return false
        }

        // No segment metadata (e.g. model didn't honor verbose_json) — skip
        // the filter rather than guess; a real "thank you" utterance is
        // worse to lose than an occasional hallucinated one to keep.
        guard let segments = json["segments"] as? [[String: Any]],
              let noSpeechProb = segments.first?["no_speech_prob"] as? Double else {
            return false
        }

        return noSpeechProb >= hallucinationNoSpeechThreshold
    }
}
