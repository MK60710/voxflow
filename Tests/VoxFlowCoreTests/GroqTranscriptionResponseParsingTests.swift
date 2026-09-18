import Foundation
import Testing
@testable import VoxFlowCore

@Suite("GroqTranscriptionResponseParsing")
struct GroqTranscriptionResponseParsingTests {

    static let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    static func httpResponse(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    // MARK: - Happy path

    @Test("a plain 200 response with a text field returns the transcript")
    func plainSuccessReturnsText() throws {
        let json = #"{"text": "Kubernetes pod restarted."}"#
        let result = try GroqTranscriptionResponseParsing.parse(
            data: Data(json.utf8),
            httpResponse: Self.httpResponse(status: 200),
            engineName: "groq:test"
        )
        #expect(result.text == "Kubernetes pod restarted.")
    }

    @Test("verbose_json with segments and low no_speech_prob keeps the text unchanged")
    func lowNoSpeechProbKeepsText() throws {
        let json = #"""
        {"text": "The RAG pipeline is ready.", "segments": [{"no_speech_prob": 0.01}]}
        """#
        let result = try GroqTranscriptionResponseParsing.parse(
            data: Data(json.utf8),
            httpResponse: Self.httpResponse(status: 200),
            engineName: "groq:test"
        )
        #expect(result.text == "The RAG pipeline is ready.")
    }

    // MARK: - Hallucination filter

    @Test("a known hallucination phrase with high no_speech_prob is filtered to empty text")
    func hallucinationPhraseWithHighNoSpeechProbFiltered() throws {
        let json = #"""
        {"text": "Thank you.", "segments": [{"no_speech_prob": 0.85}]}
        """#
        let result = try GroqTranscriptionResponseParsing.parse(
            data: Data(json.utf8),
            httpResponse: Self.httpResponse(status: 200),
            engineName: "groq:test"
        )
        #expect(result.text == "")
    }

    @Test("a known hallucination phrase with LOW no_speech_prob is NOT filtered (real speech, conservative filter)")
    func hallucinationPhraseWithLowNoSpeechProbKept() throws {
        let json = #"""
        {"text": "thank you", "segments": [{"no_speech_prob": 0.02}]}
        """#
        let result = try GroqTranscriptionResponseParsing.parse(
            data: Data(json.utf8),
            httpResponse: Self.httpResponse(status: 200),
            engineName: "groq:test"
        )
        #expect(result.text == "thank you")
    }

    @Test("a hallucination phrase with no segment metadata at all is NOT filtered (can't confirm, so kept)")
    func hallucinationPhraseWithNoSegmentsKept() throws {
        let json = #"{"text": "thank you"}"#
        let result = try GroqTranscriptionResponseParsing.parse(
            data: Data(json.utf8),
            httpResponse: Self.httpResponse(status: 200),
            engineName: "groq:test"
        )
        #expect(result.text == "thank you")
    }

    @Test("ordinary speech that happens to not match any hallucination phrase is always kept, regardless of no_speech_prob")
    func ordinarySpeechNeverFiltered() throws {
        let json = #"""
        {"text": "Deploy the RAG pipeline to production.", "segments": [{"no_speech_prob": 0.99}]}
        """#
        let result = try GroqTranscriptionResponseParsing.parse(
            data: Data(json.utf8),
            httpResponse: Self.httpResponse(status: 200),
            engineName: "groq:test"
        )
        #expect(result.text == "Deploy the RAG pipeline to production.")
    }

    @Test("hallucination match is case- and punctuation-insensitive")
    func hallucinationMatchIsCaseAndPunctuationInsensitive() throws {
        let json = #"""
        {"text": "Thank you!", "segments": [{"no_speech_prob": 0.5}]}
        """#
        let result = try GroqTranscriptionResponseParsing.parse(
            data: Data(json.utf8),
            httpResponse: Self.httpResponse(status: 200),
            engineName: "groq:test"
        )
        #expect(result.text == "")
    }

    // MARK: - Error classification (blueprint: rate-limit / offline / no-key / malformed)

    @Test("HTTP 429 is classified as rateLimited")
    func http429IsRateLimited() {
        do {
            _ = try GroqTranscriptionResponseParsing.parse(data: Data(), httpResponse: Self.httpResponse(status: 429), engineName: "groq:test")
            Issue.record("expected an error to be thrown")
        } catch let error as TranscriptionEngineError {
            #expect(error == .rateLimited(retryAfterSeconds: nil))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("HTTP 429 with a Retry-After header carries that value through")
    func http429CarriesRetryAfter() {
        let response = Self.httpResponse(status: 429, headers: ["Retry-After": "12"])
        do {
            _ = try GroqTranscriptionResponseParsing.parse(data: Data(), httpResponse: response, engineName: "groq:test")
            Issue.record("expected an error to be thrown")
        } catch let error as TranscriptionEngineError {
            #expect(error == .rateLimited(retryAfterSeconds: 12))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("HTTP 401 is classified as an httpError with an invalid-key message")
    func http401IsHTTPError() {
        do {
            _ = try GroqTranscriptionResponseParsing.parse(data: Data(), httpResponse: Self.httpResponse(status: 401), engineName: "groq:test")
            Issue.record("expected an error to be thrown")
        } catch let error as TranscriptionEngineError {
            guard case .httpError(let status, let message) = error else {
                Issue.record("expected .httpError, got \(error)")
                return
            }
            #expect(status == 401)
            #expect(message.contains("Invalid Groq API key"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("HTTP 500 is classified as an httpError with a server-error message")
    func http500IsHTTPError() {
        do {
            _ = try GroqTranscriptionResponseParsing.parse(data: Data(), httpResponse: Self.httpResponse(status: 500), engineName: "groq:test")
            Issue.record("expected an error to be thrown")
        } catch let error as TranscriptionEngineError {
            guard case .httpError(let status, _) = error else {
                Issue.record("expected .httpError, got \(error)")
                return
            }
            #expect(status == 500)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("a 200 response with no text field is malformedResponse")
    func missingTextFieldIsMalformed() {
        do {
            _ = try GroqTranscriptionResponseParsing.parse(
                data: Data(#"{"unexpected": true}"#.utf8),
                httpResponse: Self.httpResponse(status: 200),
                engineName: "groq:test"
            )
            Issue.record("expected an error to be thrown")
        } catch let error as TranscriptionEngineError {
            guard case .malformedResponse = error else {
                Issue.record("expected .malformedResponse, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("non-JSON garbage on a 200 response is malformedResponse, not a crash")
    func garbageBodyIsMalformedNotCrash() {
        do {
            _ = try GroqTranscriptionResponseParsing.parse(
                data: Data([0x00, 0xFF, 0x13, 0x37]),
                httpResponse: Self.httpResponse(status: 200),
                engineName: "groq:test"
            )
            Issue.record("expected an error to be thrown")
        } catch let error as TranscriptionEngineError {
            guard case .malformedResponse = error else {
                Issue.record("expected .malformedResponse, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
