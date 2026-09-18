import Foundation

/// The primary `CleanupEngine` (blueprint Step 6: "free cloud LLM primary is
/// Groq llama-3.1-8b-instant with Ollama local fallback"). Uses the exact
/// same Keychain-backed API key as `GroqTranscriptionEngine` — Groq hosts
/// both endpoints under one account, so the app-layer `apiKeyProvider`
/// closure this is constructed with reads
/// `KeychainCredentialStore.readGroqAPIKey()` too, never a second key.
///
/// Never logs or embeds the API key, same discipline as
/// `GroqTranscriptionEngine`: the key is fetched fresh per call via the
/// provider closure, never stored on this type.
public final class GroqCleanupEngine: CleanupEngine, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var model: String
        public var timeoutSeconds: TimeInterval
        public var maxTokens: Int?

        /// Passed as `reasoning_effort` when non-nil (see
        /// `GroqChatCompletionRequestBuilder`'s doc comment). `nil` for
        /// non-reasoning models where the param isn't applicable.
        public var reasoningEffort: String?

        public init(
            baseURL: URL = URL(string: "https://api.groq.com/openai/v1")!,
            // 2026-08-30: llama-3.1-8b-instant was DEPRECATED by Groq —
            // confirmed via a live call returning 404 model_not_found, not
            // assumed. Every cleanup call had been silently falling back
            // to raw text. Replacement verified live: openai/gpt-oss-20b
            // returns 200 with correct cleanup output; paired with
            // reasoningEffort="low" below to stay inside the 600ms budget.
            model: String = "openai/gpt-oss-20b",
            timeoutSeconds: TimeInterval = 10,
            maxTokens: Int? = 300,
            reasoningEffort: String? = "low"
        ) {
            self.baseURL = baseURL
            self.model = model
            self.timeoutSeconds = timeoutSeconds
            self.maxTokens = maxTokens
            self.reasoningEffort = reasoningEffort
        }
    }

    private let apiKeyProvider: @Sendable () -> String?
    private let transport: CleanupHTTPTransport
    private let configuration: Configuration

    public init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        transport: CleanupHTTPTransport = URLSessionCleanupHTTPTransport(),
        configuration: Configuration = Configuration()
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.transport = transport
        self.configuration = configuration
    }

    public func clean(transcript: String) async throws -> CleanupResult {
        // Step 7+8+9+listFormatting RECONCILED: the plain path is now just
        // the combined path called with defaults — one real implementation,
        // not several copies that could drift.
        try await clean(transcript: transcript, tone: .neutral, dictionaryTerms: [], autoEditsEnabled: true, listFormattingEnabled: true)
    }

    /// List-formatting (2026-08-14): the REAL, widest protocol requirement
    /// override — see `CleanupEngine.swift`'s doc comment for why this must
    /// be a real override, not just an extension method, to be reached
    /// through the `CleanupFailoverChain`'s `[CleanupEngine]` existential.
    /// Builds the request from the messages that apply the tone-specific
    /// prompt variant (Step 7), the dictionary spelling addendum (Step 8),
    /// correction-handling (Step 9), AND step-by-step list formatting in
    /// one call.
    public func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool, listFormattingEnabled: Bool) async throws -> CleanupResult {
        guard let rawKey = apiKeyProvider() else {
            throw CleanupEngineError.noAPIKeyConfigured
        }
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw CleanupEngineError.noAPIKeyConfigured
        }

        let messages = CleanupPromptTemplate.messages(forTranscript: transcript, tone: tone, dictionaryTerms: dictionaryTerms, autoEditsEnabled: autoEditsEnabled, listFormattingEnabled: listFormattingEnabled)
        let (request, body) = GroqChatCompletionRequestBuilder.build(
            baseURL: configuration.baseURL,
            apiKey: apiKey,
            model: configuration.model,
            messages: messages,
            temperature: CleanupPromptTemplate.temperature,
            maxTokens: configuration.maxTokens,
            reasoningEffort: configuration.reasoningEffort
        )
        var timedRequest = request
        timedRequest.timeoutInterval = configuration.timeoutSeconds

        let engineName = "groq:\(configuration.model)"
        do {
            let (data, response) = try await transport.send(request: timedRequest, bodyData: body)
            return try GroqChatCompletionResponseParsing.parse(
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
