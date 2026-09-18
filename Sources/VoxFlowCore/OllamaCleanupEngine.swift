import Foundation

/// The local fallback `CleanupEngine` (blueprint Step 6: "Ollama local
/// fallback — Ollama is already installed and running"). Talks to the local
/// `ollama serve` daemon's REST API (`http://localhost:11434/api/chat`) —
/// no API key, no network beyond localhost, so this keeps working with
/// Wi-Fi off, which is the whole point of it being the fallback.
///
/// **Model note (Step 6):** the blueprint/reference-report name
/// `qwen2.5:3b` (~1.9 GB) as the target model, but pulling any NEW model
/// needs Mihir's explicit approval per the House Rules and he was away from
/// the machine when this step ran. `ollama list` (read-only, not an
/// install) showed `llama3.2:3b` already pulled — named in
/// `docs/reference-report.md` §4 itself as an equally acceptable
/// alternative ("Ollama local (qwen2.5:3b or llama3.2:3b)") — so
/// `Configuration.model` defaults to `qwen2.5:3b` here (matching the
/// blueprint's stated stack name for when it's eventually approved+pulled),
/// while the App-layer `CleanupCoordinator` that actually constructs this
/// engine passes the real, already-present `llama3.2:3b` instead. See
/// PROGRESS.md for the exact pending `ollama pull qwen2.5:3b` command+size.
public final class OllamaCleanupEngine: CleanupEngine, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var model: String
        public var timeoutSeconds: TimeInterval

        public init(
            baseURL: URL = URL(string: "http://localhost:11434")!,
            model: String = "qwen2.5:3b",
            timeoutSeconds: TimeInterval = 15
        ) {
            self.baseURL = baseURL
            self.model = model
            self.timeoutSeconds = timeoutSeconds
        }
    }

    private let transport: CleanupHTTPTransport
    private let configuration: Configuration

    public init(
        transport: CleanupHTTPTransport = URLSessionCleanupHTTPTransport(),
        configuration: Configuration = Configuration()
    ) {
        self.transport = transport
        self.configuration = configuration
    }

    public func clean(transcript: String) async throws -> CleanupResult {
        // Step 7+8+9+listFormatting RECONCILED: the plain path is now just
        // the combined path called with defaults — one real implementation,
        // not several copies that could drift.
        try await clean(transcript: transcript, tone: .neutral, dictionaryTerms: [], autoEditsEnabled: true, listFormattingEnabled: true)
    }

    /// List-formatting override (2026-08-14) — same reasoning as
    /// `GroqCleanupEngine.clean(transcript:tone:dictionaryTerms:autoEditsEnabled:listFormattingEnabled:)`.
    public func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool, listFormattingEnabled: Bool) async throws -> CleanupResult {
        let messages = CleanupPromptTemplate.messages(forTranscript: transcript, tone: tone, dictionaryTerms: dictionaryTerms, autoEditsEnabled: autoEditsEnabled, listFormattingEnabled: listFormattingEnabled)
        let (request, body) = OllamaChatRequestBuilder.build(
            baseURL: configuration.baseURL,
            model: configuration.model,
            messages: messages,
            temperature: CleanupPromptTemplate.temperature
        )
        var timedRequest = request
        timedRequest.timeoutInterval = configuration.timeoutSeconds

        let engineName = "ollama:\(configuration.model)"
        do {
            let (data, response) = try await transport.send(request: timedRequest, bodyData: body)
            return try OllamaChatResponseParsing.parse(
                data: data,
                httpResponse: response as? HTTPURLResponse,
                engineName: engineName
            )
        } catch let error as CleanupEngineError {
            throw error
        } catch {
            throw CleanupErrorClassifier.classify(networkError: error)
        }
    }
}
