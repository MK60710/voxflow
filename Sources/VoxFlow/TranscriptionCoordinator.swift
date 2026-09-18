import AppKit
import Foundation
import os.log
import VoxFlowCore

private let transcriptionLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "Transcription")

/// Owns the primary `TranscriptionEngine` (Groq, blueprint Step 5a) and
/// completes the pipeline `DictationCoordinator` (S3) and
/// `TextInsertionCoordinator` (S4) already built: key-release → transcribe
/// → insert, passing the frontmost app captured at hotkey-PRESS time (see
/// docs/architecture.md's "Engine protocols" + PROGRESS.md's Step 4
/// deviations note — `TextInserter.insert(_:expectedFrontmostApp:)` already
/// takes that as a parameter for exactly this reason).
///
/// Also owns `engineStatus`/`lastTestResult` for the menu bar's Engine
/// section and `testConnection()` for the "Test Groq connection" button
/// (blueprint Step 5a task 3) — both let Mihir confirm the key works
/// without dictating.
@MainActor
final class TranscriptionCoordinator: ObservableObject {
    static let shared = TranscriptionCoordinator()

    private static let preferLocalEngineDefaultsKey = "voxflow.preferLocalTranscriptionEngine"

    @Published private(set) var engineStatus: EngineStatus = .notConfigured
    @Published private(set) var lastTestResult: String?
    @Published private(set) var isTestingConnection = false
    /// S5b task 3 ("menu shows which engine served the last utterance") —
    /// `nil` until the first real dictation has gone through this
    /// coordinator. Mirrors `CleanupCoordinator.lastCleanupSource`'s exact
    /// visibility purpose, one field instead of a two-case enum since
    /// transcription (unlike cleanup) has no "fell back to raw" concept —
    /// it either succeeds via SOME engine or the whole pipeline fails.
    @Published private(set) var lastTranscriptionEngineName: String?

    /// S5b task 3 ("settings toggle for preferred engine"): which engine
    /// tries first. Defaults to cloud (Groq) — S5a's original, already-
    /// proven behavior — since local is the NEW fallback, not a change to
    /// what most dictations already use. Persisted like every other
    /// VoxFlow setting (`UserDefaults`, per `CleanupCoordinator`'s exact
    /// pattern).
    @Published var preferLocalEngine: Bool {
        didSet {
            UserDefaults.standard.set(preferLocalEngine, forKey: Self.preferLocalEngineDefaultsKey)
            rebuildEngineChain()
        }
    }

    /// The real pipeline engine used by `transcribeAndInsert` — a
    /// `TranscriptionFailoverChain` whose order follows `preferLocalEngine`.
    /// Rebuilt (not just reordered in place) whenever that setting changes,
    /// since `TranscriptionFailoverChain` is immutable by design (mirrors
    /// `CleanupFailoverChain`).
    private var engine: TranscriptionEngine

    /// Kept SEPARATE from `engine` on purpose: "Test Groq connection" (the
    /// existing menu button, blueprint Step 5a task 3) must test Groq
    /// specifically, not silently succeed via the local fallback and report
    /// a false "Groq works" reading. Only this property is used by
    /// `testConnection()`.
    private let groqEngineForTesting: TranscriptionEngine
    private let hasAPIKey: () -> Bool

    /// **Single-flight queue (2026-08-13), a real bug fix:** confirmed live
    /// — rapid hotkey taps each spawned their own independent `Task`, so
    /// several transcription attempts ran CONCURRENTLY. When Groq was
    /// rate-limited (heavy session usage) and all of them fell back to
    /// Apple Speech at once, the local engine serialized so badly under
    /// concurrent load that results arrived 7-22 SECONDS late — roughly
    /// 40x its measured single-request latency (~500ms). Chaining each new
    /// call onto the previous one's `Task` (await-then-run, not
    /// fire-and-forget) guarantees at most ONE transcription is ever in
    /// flight, in the order spoken. Chosen over simply dropping/rejecting
    /// a new press while one is in progress: this codebase has consistently
    /// treated losing dictated text as a real failure (see
    /// `TranscriptLogCoordinator`'s whole reason for existing) — a delayed
    /// result is an acceptable tradeoff, a silently discarded one is not.
    ///
    /// **2026-08-30 fix — queue depth capped, not unbounded:** unbounded
    /// chaining meant a run of rapid dictations each waited through EVERY
    /// predecessor's full timeout, even already-failed ones — confirmed
    /// live via `log show`: 3 consecutive ~20-24s Groq timeouts turned a
    /// 4th, ordinary dictation into a 45-second wait. `queueDepth` +
    /// `TranscriptionQueueGate` cap this at 2 (one in flight + one
    /// queued); a 3rd concurrent request fails fast with a clear pill
    /// instead of extending the queue further.
    private var pendingWork: Task<Void, Never>?
    private var queueDepth = 0

    private init() {
        // `preferLocalEngine` is assigned LAST among stored properties,
        // deliberately: its `didSet` calls `rebuildEngineChain()`, which
        // touches `engine`/`groqEngineForTesting` — the Swift compiler
        // requires those already initialized before any code path that
        // could run `didSet` touches `self`, even during init.
        let preferLocal = UserDefaults.standard.bool(forKey: Self.preferLocalEngineDefaultsKey)
        self.hasAPIKey = { KeychainCredentialStore.readGroqAPIKey() != nil }
        let groq = GroqTranscriptionEngine(apiKeyProvider: { KeychainCredentialStore.readGroqAPIKey() })
        self.groqEngineForTesting = groq
        let appleSpeech = AppleSpeechTranscriptionEngine()
        self.engine = TranscriptionFailoverChain(
            engines: preferLocal ? [appleSpeech, groq] : [groq, appleSpeech]
        )
        self.preferLocalEngine = preferLocal
        // Deliberately NOT calling `refreshEngineStatus()` here (real bug,
        // fixed this session — see PROGRESS.md's S5b entry): this `init()`
        // runs the first time ANY code touches `.shared`, which for
        // `MenuContent` happens as a `@ObservedObject` property during
        // SwiftUI's SYNCHRONOUS Scene-graph construction — before
        // `applicationDidFinishLaunching`, before the run loop is fully
        // spun up. `refreshEngineStatus()` calls `hasAPIKey()`, a
        // synchronous Keychain read (`SecItemCopyMatching`) — confirmed
        // live via `sample` that when the Keychain ACL doesn't yet
        // recognize this build's CDHash (any time the binary's code
        // changes, e.g. after a normal rebuild), that read blocks
        // indefinitely on an invisible, un-clickable `SecurityAgent`
        // authorization dialog, hanging the ENTIRE app before it ever
        // finishes launching. `engineStatus`'s declared default
        // (`.notConfigured`) is a safe initial value; the menu's existing
        // `.onAppear { transcription.refreshEngineStatus() }` (already
        // present in `MenuContent.engineSection`) refreshes it lazily the
        // first time the menu is actually opened — safely off the
        // launch-time synchronous path.
    }

    /// Rebuilds the failover chain in the new preferred order — called from
    /// `preferLocalEngine`'s `didSet`. Reconstructs `AppleSpeechTranscriptionEngine`
    /// fresh each time rather than caching it: it's stateless (no
    /// connection/session to preserve, unlike a URLSession-backed engine),
    /// so a fresh instance costs nothing and keeps this simple.
    private func rebuildEngineChain() {
        let groq = GroqTranscriptionEngine(apiKeyProvider: { KeychainCredentialStore.readGroqAPIKey() })
        let appleSpeech = AppleSpeechTranscriptionEngine()
        engine = TranscriptionFailoverChain(
            engines: preferLocalEngine ? [appleSpeech, groq] : [groq, appleSpeech]
        )
    }

    /// Re-checks Keychain state — called on init and whenever the menu
    /// opens, so adding a key via `security add-generic-password` and then
    /// reopening the menu reflects "ready" without relaunching the app.
    func refreshEngineStatus() {
        guard engineStatus != .checking else { return }
        engineStatus = hasAPIKey() ? .ready : .notConfigured
    }

    /// Called by `DictationCoordinator` on key-up once the WAV file is
    /// finalized. `keyReleaseTime` is stage 1 of the latency instrumentation
    /// (blueprint task 2); `expectedFrontmostApp` is the hotkey-PRESS-time
    /// capture `DictationCoordinator` took before recording even started.
    /// `rawModeRequested` is Step 6's Shift-held-at-release raw-mode
    /// modifier (task 3), threaded straight through to
    /// `CleanupCoordinator.cleanUp` so it can skip cleanup entirely rather
    /// than run it and discard the result.
    func transcribeAndInsert(
        audioFileURL: URL,
        keyReleaseTime: Date,
        expectedFrontmostApp: NSRunningApplication?,
        rawModeRequested: Bool = false,
        audioDuration: TimeInterval = 0
    ) {
        // S5b: NOT gated on `hasAPIKey()` anymore (pre-S5b behavior) — the
        // whole point of the local fallback is that dictation still works
        // with zero Groq key configured. `engine` (the failover chain)
        // handles a missing key itself: Groq throws `.noAPIKeyConfigured`,
        // the chain moves on to Apple Speech. `refreshEngineStatus()` still
        // reflects Groq's OWN key state for the menu's "Groq: ..." line,
        // independent of whether dictation as a whole can proceed.
        if !hasAPIKey() {
            engineStatus = .notConfigured
        }

        // Queue-depth cap (2026-08-30): reject a 3rd concurrent request
        // outright rather than let it wait through two predecessors' worth
        // of timeout. Checked BEFORE touching `pendingWork`/`queueDepth` —
        // a rejected request never enters the chain at all.
        guard TranscriptionQueueGate.decide(currentDepth: queueDepth) == .enqueue else {
            os_log(.info, log: transcriptionLog, "Queue full (depth %d) — rejecting new request", queueDepth)
            DictationCoordinator.shared.presentTranscriptionNotice(TranscriptionQueueGate.queueFullMessage, isError: true)
            return
        }

        // Single-flight chaining: capture whatever's currently
        // pending (nil if nothing is), then replace `pendingWork` with a
        // NEW task that awaits that previous one FIRST before doing this
        // call's real work. Each call in a rapid sequence links onto the
        // one before it, forming a strict in-order queue — never more than
        // one `performTranscribeAndInsert` body actually executing at once,
        // with zero risk of a race on `pendingWork` itself since this
        // whole method is `@MainActor`.
        queueDepth += 1
        let previousWork = pendingWork
        pendingWork = Task {
            await previousWork?.value
            await performTranscribeAndInsert(
                audioFileURL: audioFileURL,
                keyReleaseTime: keyReleaseTime,
                expectedFrontmostApp: expectedFrontmostApp,
                rawModeRequested: rawModeRequested,
                audioDuration: audioDuration
            )
            queueDepth -= 1
        }
    }

    private func performTranscribeAndInsert(
        audioFileURL: URL,
        keyReleaseTime: Date,
        expectedFrontmostApp: NSRunningApplication?,
        rawModeRequested: Bool,
        audioDuration: TimeInterval
    ) async {
        do {
                // Step 8: dictionary terms bias Groq's Whisper `prompt`
                // field via the EXISTING `biasPrompt` parameter — `nil`
                // (S5a's original behavior) whenever the dictionary is
                // empty. See `DictionaryCoordinator.sttBiasPrompt`.
                let result = try await engine.transcribe(
                    audioFileURL: audioFileURL,
                    biasPrompt: DictionaryCoordinator.shared.sttBiasPrompt
                )
                let transcriptionReceivedTime = Date()
                let sttMs = LatencyInstrumentation.milliseconds(from: keyReleaseTime, to: transcriptionReceivedTime)
                os_log(
                    .info, log: transcriptionLog,
                    "release→transcript: %{public}dms (STT budget %{public}dms)",
                    sttMs, LatencyBudget.sttMs
                )

                lastTranscriptionEngineName = result.engineName
                os_log(.info, log: transcriptionLog, "Transcription served by %{public}@", result.engineName)
                // Only claim Groq is "ready" when Groq is the engine that
                // actually served this dictation — a local-engine success
                // (Apple Speech, whether by failover or by the
                // preferLocalEngine setting) doesn't tell us anything about
                // Groq's own health, so it shouldn't overwrite that label.
                if result.engineName.hasPrefix("groq:") {
                    engineStatus = .ready
                }

                guard !result.text.isEmpty else {
                    os_log(.info, log: transcriptionLog, "Transcript empty (silence/hallucination filtered) — nothing to insert")
                    DictationCoordinator.shared.presentTranscriptionNotice("No speech detected", isError: false)
                    return
                }

                // Step 10: command recognition runs on the RAW transcript,
                // BEFORE cleanup (blueprint task 3) — an exact "select all"
                // must execute Select All, not get cleaned up into
                // "Select all." and typed as text. `CommandRecognizer` is
                // deliberately conservative (full-string match only), so
                // anything embedded mid-sentence falls through to the
                // normal cleanup+insertion path below unchanged.
                if CommandModeCoordinator.shared.commandModeEnabled,
                   let command = CommandRecognizer.recognize(result.text) {
                    os_log(.info, log: transcriptionLog, "Command recognized: %{public}@", command.displayName)
                    await CommandExecutor.execute(command)
                    DictationCoordinator.shared.presentTranscriptionNotice(command.displayName, isError: false)
                    return
                }

                // Snippets (Wispr Flow reference, 2026-08-13): same
                // exact-match-on-raw-transcript philosophy as commands
                // above — checked AFTER commands, so a trigger phrase that
                // happens to collide with a built-in command name loses to
                // the command (system behavior takes priority over
                // user-configured text, a defensible default for an
                // unlikely collision). The expansion is inserted VERBATIM,
                // bypassing cleanup entirely — an LLM cleanup pass has no
                // business rewriting a saved URL/email/prompt the user
                // typed on purpose.
                if let expansion = SnippetRecognizer.recognize(result.text, snippets: SnippetCoordinator.shared.entries) {
                    os_log(.info, log: transcriptionLog, "Snippet expanded (%{public}d chars)", expansion.count)
                    TranscriptLogCoordinator.shared.append(expansion)
                    TextInsertionCoordinator.shared.requestInsertion(expansion, expectedFrontmostApp: expectedFrontmostApp)
                    DictationCoordinator.shared.dictationFinished()
                    return
                }

                // Step 7: resolve the tone profile for THIS dictation from
                // the frontmost app captured at hotkey-PRESS time
                // (`expectedFrontmostApp`, the exact same capture S4/S5a use
                // for the text-insertion focus-guard) — never re-queried
                // after transcription, per the blueprint's explicit
                // instruction. `ContextSettingsStore` merges the built-in
                // `ContextDetector` defaults with any of Mihir's Settings
                // overrides.
                let tone = ContextSettingsStore.shared.toneProfile(
                    forBundleIdentifier: expectedFrontmostApp?.bundleIdentifier
                )
                os_log(
                    .info, log: transcriptionLog,
                    "tone: %{public}@ (bundle %{public}@)",
                    tone.displayName, expectedFrontmostApp?.bundleIdentifier ?? "unknown"
                )

                // Step 6: cleanup stage between transcription and insertion.
                // `CleanupCoordinator.cleanUp` owns the on/off toggle,
                // raw-mode bypass, the 600ms latency guard, and the
                // Groq→Ollama failover — this call site doesn't need to
                // know which of those paths fired, only what text to insert
                // and when it finished, for the total-latency log line.
                let cleanedText = await CleanupCoordinator.shared.cleanUp(
                    transcript: result.text,
                    tone: tone,
                    rawModeRequested: rawModeRequested
                )
                let cleanupReceivedTime = Date()
                let cleanupMs = LatencyInstrumentation.milliseconds(from: transcriptionReceivedTime, to: cleanupReceivedTime)
                os_log(
                    .info, log: transcriptionLog,
                    "transcript→cleanup: %{public}dms (cleanup budget %{public}dms)",
                    cleanupMs, LatencyBudget.cleanupMs
                )

                // Safety net: log the final text here BEFORE attempting
                // insertion, regardless of whether insertion itself
                // succeeds — so a silently failed paste (wrong app, focus
                // stolen, a permission gap, anything) never actually loses
                // what was said. See TranscriptLogCoordinator's doc comment.
                TranscriptLogCoordinator.shared.append(cleanedText)

                // Insights (Wispr Flow reference, 2026-08-13): word count of
                // the FINAL text (what actually got inserted, not the raw
                // transcript) against the REAL audio duration for accurate
                // words-per-minute — not the STT/cleanup processing time,
                // which would measure the wrong thing entirely.
                // `CleanupCoordinator.lastCleanupSource` reflects THIS
                // dictation's outcome, read immediately after `cleanUp`
                // returns, before any later dictation could overwrite it.
                let wordCount = cleanedText.split(whereSeparator: { $0.isWhitespace }).count
                let wasCleanedUp: Bool = {
                    if case .cleaned = CleanupCoordinator.shared.lastCleanupSource {
                        return true
                    }
                    return false
                }()
                InsightsCoordinator.shared.append(
                    wordCount: wordCount,
                    audioDurationSeconds: audioDuration,
                    bundleIdentifier: expectedFrontmostApp?.bundleIdentifier,
                    wasCleanedUp: wasCleanedUp
                )

                TextInsertionCoordinator.shared.requestInsertion(cleanedText, expectedFrontmostApp: expectedFrontmostApp)
                DictationCoordinator.shared.dictationFinished()
                let insertionTriggeredTime = Date()
                let totalMs = LatencyInstrumentation.milliseconds(from: keyReleaseTime, to: insertionTriggeredTime)
                os_log(
                    .info, log: transcriptionLog,
                    "release→insertion-triggered: %{public}dms total (budget %{public}dms)",
                    totalMs, LatencyBudget.totalMs
                )
        } catch let error as TranscriptionEngineError {
            handle(error, audioFileURL: audioFileURL)
        } catch {
            handle(.malformedResponse(error.localizedDescription), audioFileURL: audioFileURL)
        }
    }

    private func handle(_ error: TranscriptionEngineError, audioFileURL: URL) {
        engineStatus = EngineStatusResolver.afterTranscriptionAttempt(hasAPIKey: hasAPIKey(), error: error)
        os_log(.error, log: transcriptionLog, "Transcription failed: %{public}@", error.pillMessage)

        // Every engine failed for this dictation, so there's no raw text to
        // fall back to — but the audio itself is real and recoverable. See
        // FailedRecordingStore's doc comment.
        if let savedFilename = FailedRecordingStore.preserve(audioFileURL) {
            os_log(.info, log: transcriptionLog, "Failed recording saved as %{public}@", savedFilename)
            TranscriptLogCoordinator.shared.append("[Transcription failed (\(error.pillMessage)) — audio saved as \(savedFilename)]")
        }

        DictationCoordinator.shared.presentTranscriptionNotice(error.pillMessage, isError: true)
    }

    // MARK: - Menu: "Test Groq connection" (blueprint task 3)

    /// Transcribes a synthesized 1s silent WAV (not Mihir's voice) so the
    /// key/network path can be confirmed from the menu without dictating.
    /// A near-empty transcript is the EXPECTED, correct outcome here (it's
    /// silence) — success is judged by "did Groq respond at all", not by
    /// what the transcript says.
    func testConnection() {
        guard !isTestingConnection else { return }
        isTestingConnection = true
        lastTestResult = nil
        engineStatus = .checking

        Task {
            defer { isTestingConnection = false }

            guard hasAPIKey() else {
                engineStatus = .notConfigured
                lastTestResult = "No Groq key found in Keychain."
                return
            }

            let wavData = WAVEncoder.makeSilentWAV(durationSeconds: 1.0)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("voxflow-groq-test-\(UUID().uuidString).wav")
            do {
                try wavData.write(to: tempURL)
            } catch {
                engineStatus = .error("local test file failed")
                lastTestResult = "Couldn't write a local test file: \(error.localizedDescription)"
                return
            }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            do {
                // Deliberately `groqEngineForTesting`, not `engine` (the
                // failover chain) — this button is named "Test Groq
                // connection" and must actually test Groq, not silently
                // succeed via the local S5b fallback and report a false
                // "Groq works" reading.
                _ = try await groqEngineForTesting.transcribe(audioFileURL: tempURL, biasPrompt: nil)
                engineStatus = .ready
                lastTestResult = "Groq responded successfully — key works."
            } catch let error as TranscriptionEngineError {
                engineStatus = EngineStatusResolver.afterTranscriptionAttempt(hasAPIKey: true, error: error)
                lastTestResult = error.pillMessage
            } catch {
                engineStatus = .error("unknown error")
                lastTestResult = error.localizedDescription
            }
        }
    }
}
