import Foundation

/// Drives the menu bar's Engine section (blueprint Step 5a task 3): "Groq:
/// ready" / "Groq: no key" / "Groq: rate-limited" etc. Kept as pure data
/// (no AppKit) so `EngineStatusResolver`'s mapping logic is unit-testable
/// without a live TranscriptionCoordinator.
public enum EngineStatus: Equatable, Sendable {
    case notConfigured
    case checking
    case ready
    case rateLimited
    case error(String)

    public var menuLabel: String {
        switch self {
        case .notConfigured: return "Groq: no key"
        case .checking: return "Groq: checking…"
        case .ready: return "Groq: ready"
        case .rateLimited: return "Groq: rate-limited"
        case .error(let detail): return "Groq: \(detail)"
        }
    }

    /// Drives the menu label's color (secondary/neutral vs. orange warning).
    public var isHealthy: Bool {
        self == .ready
    }
}

/// Pure mapping from "did a transcription attempt succeed, and if not, how"
/// to the next `EngineStatus` — separated from `TranscriptionCoordinator` so
/// every branch (success, each error case, no-key-at-all) is directly
/// testable without mocking a whole coordinator.
public enum EngineStatusResolver {
    public static func afterTranscriptionAttempt(hasAPIKey: Bool, error: TranscriptionEngineError?) -> EngineStatus {
        guard hasAPIKey else { return .notConfigured }
        guard let error else { return .ready }

        switch error {
        case .noAPIKeyConfigured:
            return .notConfigured
        case .rateLimited:
            return .rateLimited
        case .offline:
            return .error("offline")
        case .timedOut:
            return .error("timed out")
        case .cancelled:
            // A cancelled request (e.g. superseded by a newer utterance)
            // isn't evidence the key or connection is bad — don't downgrade
            // the status display over it.
            return .ready
        case .httpError(let status, _):
            return .error("HTTP \(status)")
        case .malformedResponse:
            return .error("bad response")
        case .localEngineUnavailable:
            // Reaches here when `TranscriptionFailoverChain` throws its
            // FIRST engine's error (fixed 2026-08-13 — see that type's own
            // doc comment) and the local engine happens to be first
            // (`preferLocalEngine` is on). This resolver only runs at all
            // once the WHOLE chain has thrown, which only happens after
            // every engine in it has already failed — so regardless of
            // which specific error is attached, Groq (the fallback in this
            // ordering) failed too. Not a case to hide behind `.ready`.
            return .error("all engines failed")
        }
    }
}
