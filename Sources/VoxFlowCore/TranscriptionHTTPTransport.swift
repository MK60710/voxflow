import Foundation

/// Abstracts the actual network call so `GroqTranscriptionEngine`'s request
/// building, response parsing, and error classification can all be unit
/// tested OFFLINE with a mock transport (blueprint Step 5a verification:
/// "tested OFFLINE with Swift Testing, no live network in Scripts/test.sh").
/// Pattern mirrors freeflow's `LLMAPITransport` (MIT).
public protocol TranscriptionHTTPTransport: Sendable {
    func upload(request: URLRequest, bodyData: Data) async throws -> (Data, URLResponse)
}

/// The real transport used by the app — a thin `URLSession.upload` wrapper.
/// Never used directly in `Scripts/test.sh`'s suite; only in the app target
/// and the standalone `VoxFlowSmokeTest` integration check.
public struct URLSessionTranscriptionTransport: TranscriptionHTTPTransport {
    public init() {}

    public func upload(request: URLRequest, bodyData: Data) async throws -> (Data, URLResponse) {
        try await URLSession.shared.upload(for: request, from: bodyData)
    }
}
