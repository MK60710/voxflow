import Foundation

/// Abstracts the network call so both `GroqCleanupEngine` and
/// `OllamaCleanupEngine` are unit-testable OFFLINE with a mock transport —
/// same "no live network in Scripts/test.sh" requirement as Step 5a's
/// `TranscriptionHTTPTransport`, which this mirrors (a separate protocol
/// rather than reusing that one directly: cleanup sends a JSON body, not a
/// multipart upload, and keeping the two independent means either endpoint's
/// transport can evolve without touching the other).
public protocol CleanupHTTPTransport: Sendable {
    func send(request: URLRequest, bodyData: Data) async throws -> (Data, URLResponse)
}

/// The real transport used by the app for both Groq's and Ollama's
/// chat-completions-style endpoints — a thin `URLSession.upload` wrapper.
/// Never used directly in `Scripts/test.sh`'s suite.
public struct URLSessionCleanupHTTPTransport: CleanupHTTPTransport {
    public init() {}

    public func send(request: URLRequest, bodyData: Data) async throws -> (Data, URLResponse) {
        try await URLSession.shared.upload(for: request, from: bodyData)
    }
}
