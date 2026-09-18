import Foundation
import os.log
import VoxFlowCore

private let warmupLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "ConnectionWarmup")

/// Fires one throwaway request to Groq's API host at launch so DNS
/// resolution, the TCP handshake, and the TLS handshake are already paid
/// for by the time the first real dictation happens — perf fix, not a
/// blueprint step (see PROGRESS.md "Slow first-request transcription": one
/// observed release→transcript of ~11.9s, almost entirely network
/// cold-start, since the upload itself was already halved by the 16-bit
/// PCM fix).
///
/// `GroqTranscriptionEngine` and `GroqCleanupEngine` both talk to
/// `api.groq.com` through the same `URLSession.shared` (see
/// `TranscriptionHTTPTransport.swift`/`CleanupHTTPTransport.swift`, both
/// thin `URLSession.shared` wrappers) — URLSession pools connections per
/// host, not per path, so warming the connection once here benefits both
/// the STT and cleanup calls; no need to warm two separate requests.
enum GroqConnectionWarmup {
    private static let warmupURL = URL(string: "https://api.groq.com/openai/v1/models")!

    /// No-op if no Groq key is configured — mirrors the same Keychain-
    /// presence check `CleanupCoordinator` already uses to decide whether
    /// Groq is even a live engine. Nothing to warm if the cloud path isn't
    /// in use.
    ///
    /// Bug fix (PROGRESS.md's S5b entry): the Keychain check used to run
    /// synchronously on the calling thread (`applicationDidFinishLaunching`,
    /// i.e. the main thread) BEFORE ever entering `Task.detached` below —
    /// confirmed live via `sample` that when the Keychain ACL doesn't yet
    /// recognize a rebuilt binary's CDHash, that read blocks indefinitely
    /// on an invisible `SecurityAgent` dialog, hanging the whole app launch
    /// (same root cause as `TranscriptionCoordinator.init()`'s bug, fixed
    /// in the same session). Moved inside `Task.detached` so it's off the
    /// main thread and off the launch-time critical path entirely.
    static func warmUpIfConfigured() {
        Task.detached(priority: .utility) {
            guard KeychainCredentialStore.readGroqAPIKey() != nil else {
                os_log(.info, log: warmupLog, "No Groq key configured — skipping connection warm-up")
                return
            }

            var request = URLRequest(url: warmupURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 5

            let start = Date()
            do {
                _ = try await URLSession.shared.data(for: request)
                let elapsed = LatencyInstrumentation.milliseconds(from: start, to: Date())
                os_log(.info, log: warmupLog, "Groq connection warmed up in %dms", elapsed)
            } catch {
                // Non-fatal by design — this is purely an optimization. If
                // it fails (offline at launch, DNS hiccup), the first real
                // dictation just pays the same cold-start cost it always
                // did. No pill, no user-facing effect: warm-up failing is
                // not the same as dictation failing.
                os_log(.info, log: warmupLog, "Groq connection warm-up failed (non-fatal): %{public}@", error.localizedDescription)
            }
        }
    }
}
