import Foundation

/// Result of a successful transcription. `text` is already
/// hallucination-filtered (see `GroqTranscriptionResponseParsing`) — an
/// empty string means "recognized as silence/noise", not an error.
/// `engineName` identifies which conformer actually served it (e.g.
/// "groq:whisper-large-v3-turbo" or "apple-speech:en-US") so the menu/logs
/// can show which engine served the last utterance — mirrors
/// `CleanupResult`'s exact same field, added for S5b's failover-visibility
/// requirement (blueprint task 3).
public struct TranscriptionResult: Equatable, Sendable {
    public let text: String
    public let engineName: String

    public init(text: String, engineName: String) {
        self.text = text
        self.engineName = engineName
    }
}

/// The engine protocol named in docs/architecture.md's "Engine protocols"
/// section (blueprint Step 5a task 1). S5a ships exactly one conformer
/// (`GroqTranscriptionEngine`); S5b slots a local engine in behind this same
/// protocol without touching any call site.
///
/// Takes a file URL (not a raw buffer) because `AudioRecorder` (Step 3)
/// already writes the 16 kHz mono recording to a WAV file on disk for the
/// "Play last recording" debug item — reusing that file avoids re-encoding
/// the same audio twice. `biasPrompt` is the S8 dictionary hook the
/// reference report names for Groq's `prompt` field; S5a always passes
/// `nil` since `DictionaryStore` doesn't exist yet.
public protocol TranscriptionEngine: Sendable {
    func transcribe(audioFileURL: URL, biasPrompt: String?) async throws -> TranscriptionResult
}

/// Every way a transcription attempt can fail, classified so the caller can
/// show a specific pill message instead of a raw error dump (blueprint Step
/// 5a task 1: "robust error surface ... ALL must produce a visible pill
/// message ... never fail silently or hang").
public enum TranscriptionEngineError: Error, Equatable, Sendable {
    /// No key in Keychain, or it read back empty.
    case noAPIKeyConfigured
    /// No network path to Groq at all (not merely a slow one — see `.timedOut`).
    case offline
    /// HTTP 429. `retryAfterSeconds` is populated when Groq sends a
    /// `Retry-After` header, `nil` otherwise.
    case rateLimited(retryAfterSeconds: Int?)
    /// Any other non-200 HTTP status, with a pre-formatted user-facing message.
    case httpError(status: Int, message: String)
    /// Request reached Groq but the response body didn't parse as expected
    /// (missing "text" field, non-JSON body, etc).
    case malformedResponse(String)
    case timedOut
    case cancelled
    /// S5b: a local engine (Apple Speech) couldn't run — unsupported OS,
    /// unsupported locale, or the on-device language asset isn't installed
    /// yet. Kept distinct from `.malformedResponse` (a genuinely different
    /// failure shape — "this engine can't run right now", not "the server
    /// sent something unexpected") so a human reading the pill/log can tell
    /// them apart, same reasoning as every other case in this enum.
    case localEngineUnavailable(String)
}

public extension TranscriptionEngineError {
    /// One-line, user-facing text for the recording pill / menu status —
    /// never the raw NSError/JSON, per the blueprint's "never fail silently"
    /// requirement.
    var pillMessage: String {
        switch self {
        case .noAPIKeyConfigured:
            return "Groq: no API key configured. Add one in Settings."
        case .offline:
            return "No internet connection — couldn't reach Groq."
        case .rateLimited(let retryAfterSeconds):
            if let retryAfterSeconds {
                return "Groq rate limit hit — try again in \(retryAfterSeconds)s."
            }
            return "Groq rate limit hit — try again in a moment."
        case .httpError(_, let message):
            return message
        case .malformedResponse(let detail):
            return "Groq returned an unexpected response: \(detail)"
        case .timedOut:
            return "Transcription timed out."
        case .cancelled:
            return "Transcription cancelled."
        case .localEngineUnavailable(let reason):
            return "Local speech engine unavailable: \(reason)"
        }
    }
}

/// Maps raw `URLError`s and HTTP status codes onto `TranscriptionEngineError`
/// — the classification logic behind the blueprint's "rate-limit, offline,
/// no-key, malformed" error surface requirement. Pure and offline-testable
/// (no network call happens here; it just interprets outcomes).
public enum TranscriptionErrorClassifier {
    public static func classify(networkError: Error) -> TranscriptionEngineError {
        if let transcriptionError = networkError as? TranscriptionEngineError {
            return transcriptionError
        }
        if let urlError = networkError as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed,
                 .secureConnectionFailed:
                return .offline
            case .timedOut:
                return .timedOut
            case .cancelled:
                return .cancelled
            default:
                return .malformedResponse(urlError.localizedDescription)
            }
        }
        return .malformedResponse((networkError as NSError).localizedDescription)
    }

    public static func classify(httpStatus: Int, host: String?, retryAfterSeconds: Int?) -> TranscriptionEngineError {
        if httpStatus == 429 {
            return .rateLimited(retryAfterSeconds: retryAfterSeconds)
        }
        return .httpError(status: httpStatus, message: friendlyMessage(status: httpStatus, host: host))
    }

    /// Adapted from freeflow's `TranscriptionService.friendlyHTTPMessage`
    /// (MIT — verified in references/freeflow/LICENSE), narrowed to Groq's
    /// wording since VoxFlow (unlike freeflow) doesn't support swapping base
    /// URLs yet.
    public static func friendlyMessage(status: Int, host: String?) -> String {
        let provider = host ?? "Groq"
        switch status {
        case 401:
            return "Invalid Groq API key. Open Settings to fix it."
        case 403:
            return "Groq key lacks permission for this endpoint (HTTP 403)."
        case 404:
            return "Groq transcription endpoint not found (HTTP 404)."
        case 413:
            return "Recording too large for Groq (HTTP 413). Try a shorter dictation."
        case 400:
            return "Groq rejected the request (HTTP 400). Check the model name."
        case 500..<600:
            return "Groq server error at \(provider) (HTTP \(status)). Try again in a moment."
        default:
            return "Groq request failed (HTTP \(status))."
        }
    }
}
