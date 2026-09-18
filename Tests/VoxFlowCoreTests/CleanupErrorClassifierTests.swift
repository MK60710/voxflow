import Foundation
import Testing
@testable import VoxFlowCore

@Suite("CleanupErrorClassifier")
struct CleanupErrorClassifierTests {

    // MARK: - Network error classification

    @Test("common no-connectivity URLErrors classify as offline")
    func noConnectivityErrorsClassifyAsOffline() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed
        ]
        for code in codes {
            let classified = CleanupErrorClassifier.classify(networkError: URLError(code))
            #expect(classified == .offline, "expected \(code) to classify as offline")
        }
    }

    @Test("URLError.timedOut classifies as timedOut")
    func timedOutClassifiesCorrectly() {
        #expect(CleanupErrorClassifier.classify(networkError: URLError(.timedOut)) == .timedOut)
    }

    @Test("URLError.cancelled classifies as cancelled")
    func cancelledClassifiesCorrectly() {
        #expect(CleanupErrorClassifier.classify(networkError: URLError(.cancelled)) == .cancelled)
    }

    @Test("an already-classified CleanupEngineError passes through unchanged")
    func alreadyClassifiedErrorPassesThrough() {
        let original = CleanupEngineError.rateLimited(retryAfterSeconds: 3)
        #expect(CleanupErrorClassifier.classify(networkError: original) == original)
    }

    @Test("an unrecognized error type becomes malformedResponse rather than being lost")
    func unrecognizedErrorBecomesMalformed() {
        struct SomeOtherError: Error {}
        let classified = CleanupErrorClassifier.classify(networkError: SomeOtherError())
        guard case .malformedResponse = classified else {
            Issue.record("expected .malformedResponse, got \(classified)")
            return
        }
    }

    // MARK: - HTTP status classification

    @Test("HTTP 429 classifies as rateLimited with the retry-after value passed through")
    func http429ClassifiesAsRateLimited() {
        let classified = CleanupErrorClassifier.classify(httpStatus: 429, host: "api.groq.com", retryAfterSeconds: 5)
        #expect(classified == .rateLimited(retryAfterSeconds: 5))
    }

    @Test("HTTP 401 message mentions an invalid key and Settings")
    func http401MessageIsHelpful() {
        let classified = CleanupErrorClassifier.classify(httpStatus: 401, host: "api.groq.com", retryAfterSeconds: nil)
        guard case .httpError(let status, let message) = classified else {
            Issue.record("expected .httpError")
            return
        }
        #expect(status == 401)
        #expect(message.contains("Invalid API key"))
        #expect(message.contains("Settings"))
    }

    @Test("pillMessage never exposes raw JSON or NSError text for the common cases")
    func pillMessagesAreUserFacing() {
        #expect(CleanupEngineError.noAPIKeyConfigured.pillMessage.contains("Cleanup"))
        #expect(CleanupEngineError.offline.pillMessage.lowercased().contains("internet"))
        #expect(CleanupEngineError.rateLimited(retryAfterSeconds: nil).pillMessage.lowercased().contains("rate limit"))
        #expect(CleanupEngineError.timedOut.pillMessage.lowercased().contains("timed out"))
    }

    @Test("timedOut pillMessage explains raw transcript was inserted instead")
    func timedOutPillMessageExplainsFallback() {
        #expect(CleanupEngineError.timedOut.pillMessage.lowercased().contains("raw"))
    }

    @Test("rateLimited pillMessage includes the retry-after seconds when present")
    func rateLimitedPillMessageIncludesRetryAfter() {
        #expect(CleanupEngineError.rateLimited(retryAfterSeconds: 12).pillMessage.contains("12"))
    }
}
