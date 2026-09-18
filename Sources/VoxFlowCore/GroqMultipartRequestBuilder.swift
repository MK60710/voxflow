import Foundation

/// Builds the `multipart/form-data` request for Groq's OpenAI-compatible
/// `/audio/transcriptions` endpoint (blueprint Step 5a task 1). Pattern
/// adapted from freeflow's `TranscriptionService.makeMultipartBody` (MIT —
/// verified in references/freeflow/LICENSE) — same field layout, ported to
/// return a plain `(URLRequest, Data)` pair so it's independently testable
/// without a network call.
public enum GroqMultipartRequestBuilder {
    /// Models whose Groq/OpenAI-compatible endpoint returns segment metadata
    /// (`no_speech_prob` etc) when asked for `verbose_json` — needed by the
    /// hallucination filter in `GroqTranscriptionResponseParsing`. Mirrors
    /// freeflow's `modelsSupportingVerboseJSON` (MIT).
    static let modelsSupportingVerboseJSON: Set<String> = [
        "whisper-1",
        "whisper-large-v3",
        "whisper-large-v3-turbo"
    ]

    public static func responseFormat(forModel model: String) -> String {
        modelsSupportingVerboseJSON.contains(model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            ? "verbose_json"
            : "json"
    }

    public static func audioContentType(forFileName fileName: String) -> String {
        let lowered = fileName.lowercased()
        if lowered.hasSuffix(".wav") { return "audio/wav" }
        if lowered.hasSuffix(".mp3") { return "audio/mpeg" }
        if lowered.hasSuffix(".m4a") { return "audio/mp4" }
        return "audio/mp4"
    }

    /// Builds the POST request + multipart body. `boundary` defaults to a
    /// fresh UUID but is an explicit parameter so tests can assert on exact
    /// body bytes without regex-parsing a random boundary out first.
    public static func build(
        baseURL: URL,
        apiKey: String,
        model: String,
        language: String?,
        prompt: String?,
        audioData: Data,
        audioFileName: String,
        boundary: String = UUID().uuidString
    ) -> (request: URLRequest, body: Data) {
        let url = baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("transcriptions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let responseFormat = responseFormat(forModel: model)

        var body = Data()
        func append(_ value: String) {
            body.append(Data(value.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("\(responseFormat)\r\n")

        if let language, !language.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            append("\(language)\r\n")
        }

        if let prompt, !prompt.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            append("\(prompt)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFileName)\"\r\n")
        append("Content-Type: \(audioContentType(forFileName: audioFileName))\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        return (request, body)
    }
}
