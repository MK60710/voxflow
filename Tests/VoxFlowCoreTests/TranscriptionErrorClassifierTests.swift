import Foundation
import Testing
@testable import VoxFlowCore

@Suite("TranscriptionErrorClassifier")
struct TranscriptionErrorClassifierTests {

    // MARK: - Network error classification

    @Test("common no-connectivity URLErrors classify as offline")
    func noConnectivityErrorsClassifyAsOffline() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed
        ]
        for code in codes {
            let classified = TranscriptionErrorClassifier.classify(networkError: URLError(code))
            #expect(classified == .offline, "expected \(code) to classify as offline")
        }
    }

    @Test("URLError.timedOut classifies as timedOut")
    func timedOutClassifiesCorrectly() {
        #expect(TranscriptionErrorClassifier.classify(networkError: URLError(.timedOut)) == .timedOut)
    }

    @Test("URLError.cancelled classifies as cancelled")
    func cancelledClassifiesCorrectly() {
        #expect(TranscriptionErrorClassifier.classify(networkError: URLError(.cancelled)) == .cancelled)
    }

    @Test("an already-classified TranscriptionEngineError passes through unchanged")
    func alreadyClassifiedErrorPassesThrough() {
        let original = TranscriptionEngineError.rateLimited(retryAfterSeconds: 3)
        #expect(TranscriptionErrorClassifier.classify(networkError: original) == original)
    }

    @Test("an unrecognized error type becomes malformedResponse rather than being lost")
    func unrecognizedErrorBecomesMalformed() {
        struct SomeOtherError: Error {}
        let classified = TranscriptionErrorClassifier.classify(networkError: SomeOtherError())
        guard case .malformedResponse = classified else {
            Issue.record("expected .malformedResponse, got \(classified)")
            return
        }
    }

    // MARK: - HTTP status classification

    @Test("HTTP 429 classifies as rateLimited with the retry-after value passed through")
    func http429ClassifiesAsRateLimited() {
        let classified = TranscriptionErrorClassifier.classify(httpStatus: 429, host: "api.groq.com", retryAfterSeconds: 7)
        #expect(classified == .rateLimited(retryAfterSeconds: 7))
    }

    @Test("HTTP 401 message mentions an invalid key and Settings")
    func http401MessageIsHelpful() {
        let classified = TranscriptionErrorClassifier.classify(httpStatus: 401, host: "api.groq.com", retryAfterSeconds: nil)
        guard case .httpError(let status, let message) = classified else {
            Issue.record("expected .httpError")
            return
        }
        #expect(status == 401)
        #expect(message.contains("Invalid Groq API key"))
        #expect(message.contains("Settings"))
    }

    @Test("HTTP 413 message mentions the recording being too large")
    func http413MessageMentionsSize() {
        let classified = TranscriptionErrorClassifier.classify(httpStatus: 413, host: "api.groq.com", retryAfterSeconds: nil)
        guard case .httpError(_, let message) = classified else {
            Issue.record("expected .httpError")
            return
        }
        #expect(message.lowercased().contains("too large"))
    }

    @Test("pillMessage never exposes raw JSON or NSError text for the common cases")
    func pillMessagesAreUserFacing() {
        #expect(TranscriptionEngineError.noAPIKeyConfigured.pillMessage.contains("Groq"))
        #expect(TranscriptionEngineError.offline.pillMessage.lowercased().contains("internet"))
        #expect(TranscriptionEngineError.rateLimited(retryAfterSeconds: nil).pillMessage.lowercased().contains("rate limit"))
        #expect(TranscriptionEngineError.timedOut.pillMessage.lowercased().contains("timed out"))
    }

    @Test("rateLimited pillMessage includes the retry-after seconds when present")
    func rateLimitedPillMessageIncludesRetryAfter() {
        #expect(TranscriptionEngineError.rateLimited(retryAfterSeconds: 15).pillMessage.contains("15"))
    }
}
