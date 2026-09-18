# VoxFlow Architecture

Status: feature-complete. The original menu-bar-only UI (a dropdown + a fixed-size Settings popup) has been replaced by a full app window with sidebar navigation — see "Window architecture" below. Update as components land; the latency table here is canonical.

## What VoxFlow is

Menu-bar-only macOS dictation app (no Dock icon). Hold a global hotkey anywhere → speak → release → polished text is typed into the focused app. Free forever: Groq free tier for cloud STT/LLM, Apple SpeechAnalyzer + Ollama as the always-works local path. Stack rationale: `docs/reference-report.md`.

## Build system (deliberately not Xcode)

- SwiftPM + Command Line Tools (Swift 6.3.1). Proven viable by FluidVoice and freeflow.
- `Scripts/bundle.sh` assembles `.build/VoxFlow.app` (Info.plist with `LSUIElement`, mic usage string) because TCC permissions are only granted to real app bundles, not bare executables.
- Tests: **Swift Testing (`import Testing`) only** — CLT ships no XCTest for macOS.
- Run tests with **`Scripts/test.sh`**, never bare `swift test`: CLT keeps Testing.framework and lib_TestingInterop.dylib outside the default search paths, so bare `swift test` fails with "no such module 'Testing'". The script passes the required -F/-rpath flags.

## Code signing (critical constraint)

Ad-hoc signing changes the app's identity every rebuild (designated requirement = CDHash), which silently revokes Accessibility/Input-Monitoring/mic grants. So:

- One-time setup (done 2026-07-13): self-signed cert **"VoxFlow Dev"**, RSA-2048, codeSigning EKU, 10-year validity, created via openssl → imported to login keychain → trusted for code signing (`security add-trusted-cert -r trustRoot -p codeSign`).
- `bundle.sh` signs every build with it. Grants persist because the cert (not the build hash) anchors the app's identity.
- Recovery if grants wedge anyway: `tccutil reset Accessibility com.mihirk.voxflow` and re-grant.
- Bundle ID `com.mihirk.voxflow` is stable forever — changing it orphans all grants (test enforces it).

## Components and data flow

```
              key-down                    key-up
 HotkeyManager ──────► AudioRecorder ──────────► TranscriptionEngine ──► CleanupEngine ──► TextInserter
   (S3/S11a)              (S3)                       (S5a/S5b)              (S6/S9)           (S4)
     │                     │                            │                    │
     │ captures            │ 16 kHz mono Float32        │ protocol:          │ protocol:
     │ frontmostApp        │ buffer                     │  GroqWhisperEngine │  GroqLLMCleanup
     │ bundle ID           │                            │  AppleSpeechEngine │  OllamaCleanup
     ▼                     ▼                            │  (failover chain,  │  (failover chain,
 ContextDetector (S7)   RecordingPill (NSPanel)         │   FIRST error      │   FIRST error
   tone profile          shows recording/command/       │   surfaced on      │   surfaced on
     │                   engine-fallback state           │   total failure)   │   total failure)
     │                                                   ▼                    ▼
     └──────────────────────────────────────────► prompt assembly ◄── DictionaryStore (S8)
                                                       │  + auto-edits addendum (S9)
                                                       │  + rule 6 few-shots against
                                                       │    answering instead of
                                                       │    transcribing (S11a bug fix)
 CommandRecognizer (S10) intercepts exact-command      │
 utterances BEFORE cleanup, hands off to               │
 CommandExecutor (S10, real CGEvent key combos) ────────┘ instead of the normal
                                                            cleanup→insert path
```

`HotkeyManager`'s hotkey is user-selectable (`HotkeyCoordinator`, Settings screen → Hotkey) among 4 modifier keys — Left Option, Right Option (default), Left Command, Right Command — not an arbitrary key/chord; see `HotkeyOption` in `Sources/VoxFlowCore/HotkeyFlagsDecoder.swift` for why (the whole hold-to-talk mechanism is built on `flagsChanged` events, which only modifier keys generate). Tap-to-toggle's companion key (hold the primary + tap the other one to start hands-free recording) is whichever OTHER Option/Command key shares the same side as the configured primary — `HotkeyOption.tapToggleCompanion` — so it works no matter which of the 4 is picked.

One dictation, happy path:
1. Key-down: `HotkeyManager` fires; capture frontmost bundle ID **now** (focus may change later — used for both tone (S7) and the S4 focus-guard); `AudioRecorder` starts; pill appears.
2. Key-up: recorder stops → 16 kHz mono buffer → `TranscriptionEngine.transcribe(buffer, dictionaryPrompt)`.
3. Transcript → `CommandRecognizer` (exact match against 4 command phrases? execute via `CommandExecutor` — real `CGEvent` key combos — instead of the normal path) → otherwise `CleanupEngine.clean(transcript, toneProfile, dictionary, autoEditsEnabled)`.
4. Cleaned text → `TextInserter.insert(text, expectedApp:)` — pasteboard-swap primary, CGEvent-unicode fallback; holds with a "click to insert" pill if focus changed.

## Latency budget (canonical)

| Stage | Budget | Notes |
|---|---|---|
| encode + STT | ≤ 900 ms | Groq whisper-large-v3-turbo typical 0.3–0.7 s for ≤ 15 s clips |
| cleanup LLM | ≤ 600 ms | gpt-oss-20b (reasoning_effort=low) typical 200–400 ms; guard: over-budget → insert raw |
| **total (release → text visible)** | **≤ 1500 ms** | mirrored in `VoxFlowCore.LatencyBudget` (test-enforced) |

## Engine protocols

Real shapes, not a sketch (`Sources/VoxFlowCore/TranscriptionEngine.swift`, `CleanupEngine.swift`):

```swift
protocol TranscriptionEngine: Sendable {
    func transcribe(audioFileURL: URL, biasPrompt: String?) async throws -> TranscriptionResult
}
protocol CleanupEngine: Sendable {
    func clean(transcript: String, tone: ToneProfile, dictionaryTerms: [String], autoEditsEnabled: Bool) async throws -> CleanupResult
    // narrower overloads (older arities) delegate into the widest one above —
    // see CleanupEngine.swift's own doc comment for why each widening had to
    // be a real protocol requirement, not just an extension default.
}
```
Failover is a chain of engines, not flags: `[primary, secondary]` — first success wins. **All-fail surfaces the FIRST engine's error, not the last** (fixed 2026-08-13, S11a — the old "last error wins" behavior masked a real Groq rate-limit behind Apple Speech's own secondary failure reason during live testing; see `TranscriptionFailoverChain.transcribe`'s doc comment). Engine choice + keys (Keychain) in Settings.

## Permissions and onboarding

| Permission | Needed by | Requested |
|---|---|---|
| Microphone | `AudioRecorder` | S3, first recording; live status in the S11a onboarding window |
| Accessibility | `HotkeyManager`'s `NSEvent` monitors AND `TextInserter` (synthetic Cmd-V) | S3/S4 at launch; live status in the S11a onboarding window |

**Input Monitoring is not a real VoxFlow requirement** despite two now-fixed stale UI strings that used to claim otherwise (`DictationCoordinator`'s permission alert, the menu's status line) — the 2026-07-30 switch from a `CGEventTap` to `NSEvent` global/local monitors (see `HotkeyManager`'s own doc comment) means Accessibility is the only permission the hotkey actually needs, same as text insertion already required.

A first-run onboarding window (`OnboardingCoordinator`) walks through both permissions with live status polling and System Settings deep links; reachable again anytime via Settings → General → "Onboarding…". Every permission request still also pairs with its own guidance alert at the point of use. Onboarding deliberately kept its own standalone window rather than folding into the main window below — it's a one-time linear checklist that fires before the main window has any reason to exist yet.

## Window architecture

VoxFlow is still `LSUIElement` (no Dock icon) and the hotkey/dictation flow above is untouched — the window is an additional surface, not a replacement for hold-to-talk-anywhere. The menu-bar dropdown (`MenuContent`, `VoxFlowApp.swift`) is now minimal: status line, "Open VoxFlow", Quit.

- `MainWindowContent` (`MainWindow.swift`) — a `NavigationSplitView` with a custom-styled sidebar (`MainWindowScreen`, 8 cases: Dictation, Insights, Transcript Log, Dictionary, Snippets, App Tones, Commands, Settings). Built as a `Window` scene (not `WindowGroup`) — proven not to auto-open at launch, reopen the same instance rather than duplicate, and not quit the app when closed (`LSUIElement` apps must survive their only window closing).
- `MainWindowNavigator` — a small shared singleton (`@Published var selection: MainWindowScreen`) so call sites outside the window (the dropdown's status-driven navigation) can select a screen before opening the window, without each screen needing its own presentation logic.
- Each sidebar item is its own file: `SettingsScreen`, `CommandsScreen`, `AppTonesScreen`, `DictionaryScreen`, `SnippetsScreen`, `InsightsScreen`, `TranscriptLogScreen` — each reads the same `Coordinator`/`Store` pairs the pre-window dropdown/Settings-popup UI already used (`InsightsCoordinator`+`InsightsStore`, `SnippetCoordinator`+`SnippetStore`, etc.) via `@ObservedObject`. `InsightsCoordinator` and `TranscriptLogCoordinator` used to each manage their own standalone `NSWindow`; that's gone now that both live in the shared window.
- `VoxFlowTheme.swift` centralizes the visual design (chosen from a set of mocked-up directions): light/dark-adaptive accent/background/card colors, a heading font helper using macOS's native serif (New York) instead of a bundled webfont. Applied consistently across every screen — custom pill-selected sidebar rows (a plain `List`'s native selection highlight can't be reliably restyled on macOS), soft filled rounded cards in place of `GroupBox`/flat gray backgrounds.

## Settings storage

`UserDefaults` for toggles/hotkey selection/tone map (including S11a's launch-at-login state, mirrored from `SMAppService.mainApp.status` rather than double-tracked); JSON in `~/Library/Application Support/VoxFlow/` for the dictionary; **Keychain** for API keys. Nothing secret ever in the repo.

## Known OS traps (designed-in, from reference survey + adversarial review)

- Event tap dies on sleep/wake → re-enable on `tapDisabledByTimeout`/`ByUserInput` (freeflow pattern, S3).
- Secure Input (password fields) blocks tap + synthetic paste → detect `IsSecureEventInputEnabled()`, show blocked state (S3/S4).
- Audio device switch mid-recording → handle `AVAudioEngineConfigurationChange` (S3).
- Clipboard managers race the restore → transient pasteboard type + ownership-checked restore (VoiceInk pattern, S4).
- "QWERTY ⌘" layouts remap Cmd-V → physical key code 9 path (VoiceInk pattern, S4).
- Whisper hallucinations on silence → segment no-speech filter via verbose_json (freeflow pattern, S5a).
