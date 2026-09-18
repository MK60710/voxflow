import Testing
@testable import VoxFlowCore

@Suite("AppleSpeechAssetStatusMapping")
struct AppleSpeechAssetStatusMappingTests {

    @Test("installed asset status is ready to transcribe")
    func installedIsReady() {
        #expect(AppleSpeechAssetStatusMapping.readiness(for: .installed) == .ready)
    }

    @Test("needsDownload maps to a localEngineUnavailable error, not ready")
    func needsDownloadIsNotReady() {
        let readiness = AppleSpeechAssetStatusMapping.readiness(for: .needsDownload)
        guard case .notReady(let error) = readiness else {
            Issue.record("expected .notReady, got \(readiness)")
            return
        }
        #expect(error == .localEngineUnavailable("language asset not installed yet"))
    }

    @Test("downloading maps to a localEngineUnavailable error, not ready")
    func downloadingIsNotReady() {
        let readiness = AppleSpeechAssetStatusMapping.readiness(for: .downloading)
        guard case .notReady(let error) = readiness else {
            Issue.record("expected .notReady, got \(readiness)")
            return
        }
        #expect(error == .localEngineUnavailable("language asset is still downloading"))
    }

    @Test("unsupported maps to a localEngineUnavailable error, not ready")
    func unsupportedIsNotReady() {
        let readiness = AppleSpeechAssetStatusMapping.readiness(for: .unsupported)
        guard case .notReady(let error) = readiness else {
            Issue.record("expected .notReady, got \(readiness)")
            return
        }
        #expect(error == .localEngineUnavailable("locale not supported by Apple Speech"))
    }
}
