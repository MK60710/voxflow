import Foundation

/// Mirrors Apple's `AssetInventory.Status` (the `Speech` framework,
/// macOS 26+) as a plain, testable enum. `VoxFlowCore` doesn't import
/// `Speech` itself — that's a live-system framework, kept in the App layer
/// per this repo's convention (like `AudioRecorder`/`HotkeyManager`) — so
/// `AppleSpeechTranscriptionEngine` (Sources/VoxFlow) converts the real
/// `AssetInventory.Status` into this type at the one call site that touches
/// the real API, and everything downstream of that conversion is pure and
/// unit-testable without a live macOS Speech asset.
public enum AppleSpeechAssetStatus: Equatable, Sendable {
    case installed
    case needsDownload
    case downloading
    case unsupported
}

/// Pure decision logic: given the language asset's current status, is the
/// local engine ready to transcribe right now, and if not, what
/// `TranscriptionEngineError` should the caller surface — mirrors
/// `EngineStatusResolver`'s "pure mapping, unit-testable without a live
/// coordinator" pattern (blueprint S5b task 2).
public enum AppleSpeechReadiness: Equatable, Sendable {
    case ready
    case notReady(TranscriptionEngineError)
}

public enum AppleSpeechAssetStatusMapping {
    public static func readiness(for status: AppleSpeechAssetStatus) -> AppleSpeechReadiness {
        switch status {
        case .installed:
            return .ready
        case .needsDownload:
            return .notReady(.localEngineUnavailable("language asset not installed yet"))
        case .downloading:
            return .notReady(.localEngineUnavailable("language asset is still downloading"))
        case .unsupported:
            return .notReady(.localEngineUnavailable("locale not supported by Apple Speech"))
        }
    }
}
