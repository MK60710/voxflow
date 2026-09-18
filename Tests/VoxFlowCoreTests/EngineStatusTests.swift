import Testing
@testable import VoxFlowCore

@Suite("EngineStatus / EngineStatusResolver")
struct EngineStatusTests {

    @Test("menu labels match the blueprint's exact wording")
    func menuLabelsMatchBlueprintWording() {
        #expect(EngineStatus.notConfigured.menuLabel == "Groq: no key")
        #expect(EngineStatus.ready.menuLabel == "Groq: ready")
        #expect(EngineStatus.rateLimited.menuLabel == "Groq: rate-limited")
    }

    @Test("only .ready is considered healthy")
    func onlyReadyIsHealthy() {
        #expect(EngineStatus.ready.isHealthy)
        #expect(!EngineStatus.notConfigured.isHealthy)
        #expect(!EngineStatus.rateLimited.isHealthy)
        #expect(!EngineStatus.checking.isHealthy)
        #expect(!EngineStatus.error("x").isHealthy)
    }

    @Test("no API key at all always resolves to notConfigured, regardless of the error passed")
    func noAPIKeyAlwaysResolvesToNotConfigured() {
        #expect(EngineStatusResolver.afterTranscriptionAttempt(hasAPIKey: false, error: nil) == .notConfigured)
        #expect(EngineStatusResolver.afterTranscriptionAttempt(hasAPIKey: false, error: .rateLimited(retryAfterSeconds: nil)) == .notConfigured)
        #expect(EngineStatusResolver.afterTranscriptionAttempt(hasAPIKey: false, error: .offline) == .notConfigured)
    }

    @Test("a successful attempt (no error) with a key resolves to ready")
    func successWithKeyResolvesToReady() {
        #expect(EngineStatusResolver.afterTranscriptionAttempt(hasAPIKey: true, error: nil) == .ready)
    }

    @Test("rateLimited error resolves to .rateLimited")
    func rateLimitedErrorResolvesCorrectly() {
        #expect(EngineStatusResolver.afterTranscriptionAttempt(hasAPIKey: true, error: .rateLimited(retryAfterSeconds: 5)) == .rateLimited)
    }

    @Test("offline error resolves to an error status, not notConfigured (key is fine, network isn't)")
    func offlineErrorResolvesToErrorNotNotConfigured() {
        let status = EngineStatusResolver.afterTranscriptionAttempt(hasAPIKey: true, error: .offline)
        #expect(status == .error("offline"))
    }

    @Test("a cancelled request does not downgrade status away from ready")
    func cancelledDoesNotDowngradeStatus() {
        #expect(EngineStatusResolver.afterTranscriptionAttempt(hasAPIKey: true, error: .cancelled) == .ready)
    }

    @Test("httpError includes the status code in the resolved error status")
    func httpErrorIncludesStatusCode() {
        let status = EngineStatusResolver.afterTranscriptionAttempt(
            hasAPIKey: true,
            error: .httpError(status: 401, message: "bad key")
        )
        #expect(status == .error("HTTP 401"))
    }

    @Test("S5b: localEngineUnavailable (the failover chain's last-engine error) resolves to a real error, not ready")
    func localEngineUnavailableResolvesToError() {
        let status = EngineStatusResolver.afterTranscriptionAttempt(
            hasAPIKey: true,
            error: .localEngineUnavailable("locale not supported")
        )
        #expect(status == .error("all engines failed"))
    }
}
