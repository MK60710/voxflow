import Foundation
import os.log
import VoxFlowCore

private let cleanupLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "Cleanup")

/// Owns the cleanup stage of the pipeline (blueprint Step 6): a
/// `CleanupFailoverChain` of `GroqCleanupEngine` (primary) →
/// `OllamaCleanupEngine` (local fallback), the cleanup on/off Settings
/// toggle, the raw-mode bypass, and the 600ms latency guard. Called by
/// `TranscriptionCoordinator` between transcription and text insertion —
/// mirrors that type's shape (singleton `.shared`, `@MainActor`,
/// `ObservableObject` for the menu/Settings UI).
///
/// Reuses `KeychainCredentialStore.readGroqAPIKey()` for the Groq cleanup
/// engine — same service/account as `GroqTranscriptionEngine`, since Groq
/// hosts both the STT and chat-completions endpoints under one key. Never
/// reads, logs, or persists the key itself; only passes the same provider
/// closure `TranscriptionCoordinator` already uses.
@MainActor
final class CleanupCoordinator: ObservableObject {
    static let shared = CleanupCoordinator()

    private static let cleanupEnabledDefaultsKey = "voxflow.cleanupEnabled"
    private static let ollamaModelDefaultsKey = "voxflow.ollamaCleanupModel"
    private static let autoEditsEnabledDefaultsKey = "voxflow.autoEditsEnabled"
    private static let listFormattingEnabledDefaultsKey = "voxflow.listFormattingEnabled"

    /// **Step 6 model note:** the blueprint/reference-report name
    /// `qwen2.5:3b` (~1.9 GB) as Ollama's target cleanup model, but pulling
    /// any new model needs Mihir's explicit approval (House Rule) and he
    /// was away from the machine when this step ran. `ollama list`
    /// (read-only check) showed `llama3.2:3b` already pulled — named
    /// alongside qwen2.5:3b in `docs/reference-report.md` §4 as an equally
    /// acceptable small local model — so THIS is the real default used at
    /// runtime. See PROGRESS.md for the exact pending
    /// `ollama pull qwen2.5:3b` command + size; Settings can override this
    /// via `ollamaModelDefaultsKey` once Mihir approves and pulls it.
    static let defaultOllamaModel = "llama3.2:3b"

    /// Step 6 task 3: cleanup on/off toggle, persisted like every other
    /// VoxFlow setting (`UserDefaults`, per docs/architecture.md's
    /// "Settings storage" section). Defaults to on — cleanup is the
    /// feature this step adds; Mihir opts OUT, not in.
    @Published var cleanupEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cleanupEnabled, forKey: Self.cleanupEnabledDefaultsKey)
        }
    }

    /// Step 9 task 4: auto-edits ("scratch that") on/off toggle. Same
    /// persistence pattern as `cleanupEnabled`, same "opt out, not opt in"
    /// default. Only meaningful when `cleanupEnabled` is also true —
    /// correction handling is part of the cleanup LLM's job, so if cleanup
    /// itself is off (or raw mode is requested), there's no LLM call for
    /// this to affect either way.
    @Published var autoEditsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoEditsEnabled, forKey: Self.autoEditsEnabledDefaultsKey)
        }
    }

    /// List formatting (2026-08-14, Mihir's request): format a dictated
    /// step-by-step process ("first... next... then...") as a numbered
    /// list, one step per line. Same persistence pattern and "opt out, not
    /// opt in" default as every other cleanup toggle. Only meaningful when
    /// `cleanupEnabled` is also true, same reasoning as `autoEditsEnabled`.
    @Published var listFormattingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(listFormattingEnabled, forKey: Self.listFormattingEnabledDefaultsKey)
        }
    }

    /// Drives the menu's "which engine served the last cleanup" line —
    /// `nil` until the first utterance has gone through this coordinator at
    /// least once.
    @Published private(set) var lastCleanupSource: CleanupSource?

    /// Step 7: the tone profile actually used for the last dictation —
    /// drives the menu/Settings "Tone: Casual (Slack)"-style line so Mihir
    /// can see context-awareness working without checking Console. `nil`
    /// until the first utterance has gone through this coordinator.
    @Published private(set) var lastToneUsed: ToneProfile?

    private let engine: CleanupEngine

    private init() {
        self.cleanupEnabled = (UserDefaults.standard.object(forKey: Self.cleanupEnabledDefaultsKey) as? Bool) ?? true
        self.autoEditsEnabled = (UserDefaults.standard.object(forKey: Self.autoEditsEnabledDefaultsKey) as? Bool) ?? true
        self.listFormattingEnabled = (UserDefaults.standard.object(forKey: Self.listFormattingEnabledDefaultsKey) as? Bool) ?? true
        let ollamaModel = UserDefaults.standard.string(forKey: Self.ollamaModelDefaultsKey) ?? Self.defaultOllamaModel

        let groq = GroqCleanupEngine(apiKeyProvider: { KeychainCredentialStore.readGroqAPIKey() })
        let ollama = OllamaCleanupEngine(configuration: OllamaCleanupEngine.Configuration(model: ollamaModel))
        self.engine = CleanupFailoverChain(engines: [groq, ollama])
    }

    /// Entry point `TranscriptionCoordinator` calls after a successful
    /// transcription, before handing text to `TextInsertionCoordinator`.
    /// Always returns SOME text to insert — raw transcript on any bypass or
    /// failure, cleaned text on success — so the caller never has to decide
    /// what "cleanup didn't work" means; that decision lives here and in
    /// `CleanupOutcomeResolver`.
    ///
    /// `rawModeRequested` (Shift held at key-release, task 3) is checked
    /// BEFORE the engine is ever invoked — a true bypass, not "call cleanup
    /// and hope it's fast or ignore the result".
    ///
    /// `tone` (Step 7, blueprint task 1/2): the tone profile
    /// `TranscriptionCoordinator` resolved from the frontmost app captured
    /// at hotkey-press time, via `ContextSettingsStore`/`ContextDetector`.
    /// Defaults to `.neutral` — the exact Step 6 behavior — for any caller
    /// (e.g. an older test) that doesn't pass one.
    func cleanUp(transcript: String, tone: ToneProfile = .neutral, rawModeRequested: Bool) async -> String {
        lastToneUsed = tone
        guard cleanupEnabled else {
            lastCleanupSource = .raw(reason: "cleanup disabled in Settings")
            os_log(.info, log: cleanupLog, "Cleanup bypassed: disabled in Settings")
            return transcript
        }
        guard !rawModeRequested else {
            lastCleanupSource = .raw(reason: "raw mode (Shift held at release)")
            os_log(.info, log: cleanupLog, "Cleanup bypassed: raw mode requested")
            return transcript
        }

        let outcome: Result<CleanupResult, Error>
        do {
            // Step 6 task 4: the real 600ms race, not a post-hoc elapsed-
            // time check — see CleanupLatencyGuard's doc comment.
            // Step 8: dictionary terms are threaded into the cleanup
            // prompt as "these terms are spelled exactly: …" — see
            // `DictionaryCoordinator.termsForCleanup` and
            // `CleanupEngine.swift`'s Step 8 protocol addition.
            let dictionaryTerms = DictionaryCoordinator.shared.termsForCleanup
            // Step 9: `autoEditsEnabled` captured now, not read again after
            // the guard/network call, so a Settings change mid-flight can't
            // apply to an in-progress request.
            let autoEdits = autoEditsEnabled
            // List formatting (2026-08-14): same "captured now, not
            // re-read mid-flight" reasoning as autoEdits above.
            let listFormatting = listFormattingEnabled
            let result = try await CleanupLatencyGuard.run(budgetMilliseconds: LatencyBudget.cleanupMs) {
                try await self.engine.clean(transcript: transcript, tone: tone, dictionaryTerms: dictionaryTerms, autoEditsEnabled: autoEdits, listFormattingEnabled: listFormatting)
            }
            outcome = .success(result)
        } catch {
            outcome = .failure(error)
        }

        let (text, source) = CleanupOutcomeResolver.resolve(originalTranscript: transcript, cleanupOutcome: outcome)
        lastCleanupSource = source

        switch source {
        case .cleaned(let engineName):
            os_log(.info, log: cleanupLog, "Cleanup served by %{public}@", engineName)
        case .raw(let reason):
            os_log(.info, log: cleanupLog, "Cleanup fell back to raw transcript: %{public}@", reason)
        }

        return text
    }
}
