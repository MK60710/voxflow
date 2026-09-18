import Foundation

/// The primary `TranscriptionEngine` (blueprint Step 5a, Milestone 1):
/// uploads the recorded WAV to Groq's OpenAI-compatible
/// `/audio/transcriptions` endpoint and returns the (hallucination-filtered)
/// transcript. Pattern adapted from freeflow's `TranscriptionService` (MIT
/// — verified in references/freeflow/LICENSE), split into three pieces so
/// each is independently testable offline:
/// `GroqMultipartRequestBuilder` (request/body construction),
/// `GroqTranscriptionResponseParsing` (response parsing + hallucination
/// filter), and this type (orchestration + error classification).
///
/// Never logs or embeds the API key: `apiKeyProvider` is called fresh on
/// every request so a key added via Settings after launch is picked up
/// without restarting, and so this type never has to persist the key
/// itself — Keychain access lives in `Sources/VoxFlow/KeychainCredentialStore.swift`
/// (App-layer, like `AudioRecorder`/`HotkeyManager`'s other system-side-effect
/// code), not here.
public final class GroqTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var model: String
        public var language: String?
        /// Floor for the request timeout, not the whole budget — a longer
        /// recording gets more time on top of this (see `transcribe`'s
        /// `timeoutSeconds` calculation below). 20s was the ORIGINAL flat
        /// timeout, kept as the floor so short dictations are unaffected;
        /// the bug this floor alone caused (confirmed live: long dictations
        /// timing out mid-upload, forcing Mihir to redictate) is that it
        /// never grew for longer recordings, unlike
        /// `AppleSpeechTranscriptionEngine`'s `audioDuration * 4 + 10`,
        /// which was built correctly from the start.
        public var timeoutSeconds: TimeInterval

        public init(
            baseURL: URL = URL(string: "https://api.groq.com/openai/v1")!,
            model: String = "whisper-large-v3-turbo",
            language: String? = nil,
            timeoutSeconds: TimeInterval = 20
        ) {
            self.baseURL = baseURL
            self.model = model
            self.language = language
            self.timeoutSeconds = timeoutSeconds
        }
    }

    private let apiKeyProvider: @Sendable () -> String?
    private let transport: TranscriptionHTTPTransport
    private let configuration: Configuration

    public init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        transport: TranscriptionHTTPTransport = URLSessionTranscriptionTransport(),
        configuration: Configuration = Configuration()
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.transport = transport
        self.configuration = configuration
    }

    public func transcribe(audioFileURL: URL, biasPrompt: String?) async throws -> TranscriptionResult {
        guard let rawKey = apiKeyProvider() else {
            throw TranscriptionEngineError.noAPIKeyConfigured
        }
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw TranscriptionEngineError.noAPIKeyConfigured
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioFileURL)
        } catch {
            throw TranscriptionEngineError.malformedResponse("Couldn't read the recorded audio file")
        }

        let (request, body) = GroqMultipartRequestBuilder.build(
            baseURL: configuration.baseURL,
            apiKey: apiKey,
            model: configuration.model,
            language: configuration.language,
            prompt: biasPrompt,
            audioData: audioData,
            audioFileName: audioFileURL.lastPathComponent
        )
        // Scale the timeout to the actual recording length instead of the
        // flat `configuration.timeoutSeconds` alone: a longer WAV takes
        // longer to upload and longer for Groq to process, so a fixed
        // ceiling was killing long dictations mid-flight (the real bug —
        // see `Configuration.timeoutSeconds`'s doc comment). +1s of budget
        // per second of audio, plus a flat 20s buffer for upload/queue
        // overhead on top of that — mirrors the reasoning
        // `AppleSpeechTranscriptionEngine` already applies for its own
        // (much slower, on-device) timeout, just with constants suited to
        // a network round-trip instead of local analysis. `nil` (an
        // unparseable WAV header) falls back to the flat floor rather than
        // failing the request outright.
        let audioDuration = WAVEncoder.durationSeconds(ofWAVData: audioData) ?? 0
        let timeoutSeconds = max(configuration.timeoutSeconds, audioDuration + 20)

        var timedRequest = request
        timedRequest.timeoutInterval = timeoutSeconds

        do {
            let (data, response) = try await transport.upload(request: timedRequest, bodyData: body)
            return try GroqTranscriptionResponseParsing.parse(
                data: data,
                httpResponse: response as? HTTPURLResponse,
                engineName: "groq:\(configuration.model)"
            )
        } catch let error as TranscriptionEngineError {
            throw error
        } catch {
            throw TranscriptionErrorClassifier.classify(networkError: error)
        }
    }
}
