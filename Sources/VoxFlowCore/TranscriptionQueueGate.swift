import Foundation

/// Pure decision logic for `TranscriptionCoordinator`'s single-flight queue
/// depth cap (2026-08-30 fix): a real, live-log-confirmed bug where rapid
/// consecutive dictations queued UNBOUNDED — each new request waited
/// through every predecessor's FULL timeout before its own even started,
/// turning 3 back-to-back Groq timeouts into a 45-second pileup for the
/// 4th, otherwise-ordinary dictation (confirmed via `log show`: three
/// consecutive ~20-24s timeouts, then a 4th request whose OWN network call
/// took under a second once it finally got its turn).
///
/// Fix: cap queue depth at 2 (one in flight + at most one queued behind
/// it). A 3rd concurrent request is rejected immediately with a clear
/// pill instead of extending the queue — bounds worst-case wait to ~2x one
/// timeout instead of unbounded, per Mihir's chosen option ("keep the
/// never-silently-drop-text guarantee, bound the wait" over "coalesce to
/// latest, silently supersede the queued one").
public enum TranscriptionQueueGate {
    public enum Decision: Equatable {
        case enqueue
        case rejectQueueFull
    }

    /// - Parameter currentDepth: how many requests are already in flight
    ///   or queued (0 = idle, 1 = one running, 2 = one running + one
    ///   queued — the cap).
    public static func decide(currentDepth: Int) -> Decision {
        currentDepth >= 2 ? .rejectQueueFull : .enqueue
    }

    public static let queueFullMessage = "Still processing a previous dictation — try again in a moment."
}
