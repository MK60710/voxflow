import Foundation
import Testing
@testable import VoxFlowCore

/// Mock transport so `GroqTranscriptionEngine`'s orchestration (key check →
/// build request → call transport → classify/parse) is fully testable
/// OFFLINE — no live network call happens anywhere in this file. This is
/// the "no live network in Scripts/test.sh" requirement from the blueprint.
private final class MockTranscriptionHTTPTransport: TranscriptionHTTPTransport, @unchecked Sendable {
    enum Behavior {
        case success(data: Data, status: Int)
        case networkError(Error)
    }

    var behavior: Behavior
    private(set) var callCount = 0
    private(set) var lastRequest: URLRequest?
    private(set) var lastBody: Data?

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func upload(request: URLRequest, bodyData: Data) async throws -> (Data, URLResponse) {
        callCount += 1
        lastRequest = request
        lastBody = bodyData

        switch behavior {
        case .success(let data, let status):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
            return (data, response)
        case .networkError(let error):
            throw error
        }
    }
}

@Suite("GroqTranscriptionEngine")
struct GroqTranscriptionEngineTests {

    static func tempWAVFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("engine-test-\(UUID().uuidString).wav")
        try WAVEncoder.makeSilentWAV(durationSeconds: 0.2).write(to: url)
        return url
    }

    // MARK: - No-key path (never touches the network)

    @Test("no API key configured throws noAPIKeyConfigured without ever calling the transport")
    func noAPIKeyNeverCallsTransport() async throws {
        let transport = MockTranscriptionHTTPTransport(behavior: .success(data: Data(), status: 200))
        let engine = GroqTranscriptionEngine(apiKeyProvider: { nil }, transport: transport)
        let fileURL = try Self.tempWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await engine.transcribe(audioFileURL: fileURL, biasPrompt: nil)
            Issue.record("expected noAPIKeyConfigured to be thrown")
        } catch let error as TranscriptionEngineError {
            #expect(error == .noAPIKeyConfigured)
        }
        #expect(transport.callCount == 0)
    }

    @Test("an empty-string API key is treated the same as no key")
    func emptyStringKeyTreatedAsNoKey() async throws {
        let transport = MockTranscriptionHTTPTransport(behavior: .success(data: Data(), status: 200))
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "   " }, transport: transport)
        let fileURL = try Self.tempWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await engine.transcribe(audioFileURL: fileURL, biasPrompt: nil)
            Issue.record("expected noAPIKeyConfigured to be thrown")
        } catch let error as TranscriptionEngineError {
            #expect(error == .noAPIKeyConfigured)
        }
        #expect(transport.callCount == 0)
    }

    // MARK: - Success path

    @Test("a successful response returns the parsed transcript and sends the Authorization header")
    func successfulResponseReturnsTranscript() async throws {
        let json = #"{"text": "Deploy the RAG pipeline.", "segments": [{"no_speech_prob": 0.01}]}"#
        let transport = MockTranscriptionHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "sk-real-looking-key" }, transport: transport)
        let fileURL = try Self.tempWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await engine.transcribe(audioFileURL: fileURL, biasPrompt: nil)

        #expect(result.text == "Deploy the RAG pipeline.")
        #expect(transport.callCount == 1)
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-real-looking-key")
    }

    // MARK: - Error surface: offline / rate-limit / malformed (blueprint requirement)

    @Test("a URLError.notConnectedToInternet is classified as offline")
    func offlineErrorClassified() async throws {
        let transport = MockTranscriptionHTTPTransport(
            behavior: .networkError(URLError(.notConnectedToInternet))
        )
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "key" }, transport: transport)
        let fileURL = try Self.tempWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await engine.transcribe(audioFileURL: fileURL, biasPrompt: nil)
            Issue.record("expected an offline error")
        } catch let error as TranscriptionEngineError {
            #expect(error == .offline)
        }
    }

    @Test("a URLError.timedOut is classified as timedOut")
    func timeoutErrorClassified() async throws {
        let transport = MockTranscriptionHTTPTransport(behavior: .networkError(URLError(.timedOut)))
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "key" }, transport: transport)
        let fileURL = try Self.tempWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await engine.transcribe(audioFileURL: fileURL, biasPrompt: nil)
            Issue.record("expected a timedOut error")
        } catch let error as TranscriptionEngineError {
            #expect(error == .timedOut)
        }
    }

    @Test("HTTP 429 from the transport is surfaced as rateLimited")
    func rateLimitErrorSurfaced() async throws {
        let transport = MockTranscriptionHTTPTransport(behavior: .success(data: Data(), status: 429))
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "key" }, transport: transport)
        let fileURL = try Self.tempWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await engine.transcribe(audioFileURL: fileURL, biasPrompt: nil)
            Issue.record("expected a rateLimited error")
        } catch let error as TranscriptionEngineError {
            #expect(error == .rateLimited(retryAfterSeconds: nil))
        }
    }

    @Test("a malformed 200 response is surfaced as malformedResponse, not a crash or hang")
    func malformedResponseSurfaced() async throws {
        let transport = MockTranscriptionHTTPTransport(
            behavior: .success(data: Data([0x00, 0x01, 0x02]), status: 200)
        )
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "key" }, transport: transport)
        let fileURL = try Self.tempWAVFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await engine.transcribe(audioFileURL: fileURL, biasPrompt: nil)
            Issue.record("expected a malformedResponse error")
        } catch let error as TranscriptionEngineError {
            guard case .malformedResponse = error else {
                Issue.record("expected .malformedResponse, got \(error)")
                return
            }
        }
    }

    @Test("a missing/unreadable audio file is surfaced as malformedResponse, not a crash")
    func missingAudioFileSurfaced() async throws {
        let transport = MockTranscriptionHTTPTransport(behavior: .success(data: Data(), status: 200))
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "key" }, transport: transport)
        let nonexistentURL = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).wav")

        do {
            _ = try await engine.transcribe(audioFileURL: nonexistentURL, biasPrompt: nil)
            Issue.record("expected a malformedResponse error")
        } catch let error as TranscriptionEngineError {
            guard case .malformedResponse = error else {
                Issue.record("expected .malformedResponse, got \(error)")
                return
            }
        }
        #expect(transport.callCount == 0)
    }

    // MARK: - Timeout scales with audio length (the real bug: a flat 20s
    // timeout killed long dictations mid-upload/processing, forcing
    // redictation — see GroqTranscriptionEngine.Configuration's doc comment)

    @Test("a short recording uses the configuration's flat timeout floor")
    func shortRecordingUsesTimeoutFloor() async throws {
        let json = #"{"text": "hi", "segments": [{"no_speech_prob": 0.01}]}"#
        let transport = MockTranscriptionHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "key" }, transport: transport)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("floor-\(UUID().uuidString).wav")
        try WAVEncoder.makeSilentWAV(durationSeconds: 0).write(to: url) // effectively 0s of audio
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await engine.transcribe(audioFileURL: url, biasPrompt: nil)

        let timeout = try #require(transport.lastRequest?.timeoutInterval)
        #expect(abs(timeout - 20) < 0.01)
    }

    @Test("a long recording gets a timeout well above the flat floor")
    func longRecordingGetsScaledTimeout() async throws {
        let json = #"{"text": "a long dictation", "segments": [{"no_speech_prob": 0.01}]}"#
        let transport = MockTranscriptionHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "key" }, transport: transport)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("long-\(UUID().uuidString).wav")
        try WAVEncoder.makeSilentWAV(durationSeconds: 90).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await engine.transcribe(audioFileURL: url, biasPrompt: nil)

        // 90s of audio + 20s buffer, per the scaling formula.
        #expect(transport.lastRequest?.timeoutInterval == 110)
    }

    @Test("an unparseable audio file falls back to the flat timeout floor instead of failing the request")
    func unparseableAudioFallsBackToFloor() async throws {
        let json = #"{"text": "hi", "segments": [{"no_speech_prob": 0.01}]}"#
        let transport = MockTranscriptionHTTPTransport(behavior: .success(data: Data(json.utf8), status: 200))
        let engine = GroqTranscriptionEngine(apiKeyProvider: { "key" }, transport: transport)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notreallyawav-\(UUID().uuidString).wav")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await engine.transcribe(audioFileURL: url, biasPrompt: nil)

        #expect(transport.lastRequest?.timeoutInterval == 20)
    }
}
