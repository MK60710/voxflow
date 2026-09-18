# VoxFlow

A free macOS dictation app, built as a Wispr Flow replacement. Hold a hotkey anywhere, speak, release — cleaned-up text appears in whatever app has focus. SwiftPM + Command Line Tools (no Xcode project, no Xcode required).

**Stack:** Groq Whisper large-v3-turbo (STT primary) with Apple SpeechAnalyzer as an on-device fallback; Groq gpt-oss-20b (cleanup primary) with a local Ollama model as fallback.

**Status:** feature-complete — hold-to-talk dictation, text insertion, cloud + local STT failover, LLM cleanup, per-app tone, personal dictionary, snippets, voice commands, Insights, Transcript Log — with a full app window (sidebar navigation) replacing the original menu-bar-only UI.

## Requirements

- macOS 26 or later.
- Xcode Command Line Tools with Swift 6.3.1+ (`xcode-select --install`) — full Xcode is not needed and is not installed for this project.
- A free [Groq](https://console.groq.com) API key (used for both speech-to-text and cleanup; VoxFlow still works offline without one via the on-device Apple Speech fallback, just with reduced cleanup quality).

## Setup from a fresh clone

```
git clone <this repo>
cd VoxFlow

# One-time: create and trust the self-signed code-signing certificate that
# keeps VoxFlow's identity stable across rebuilds (see docs/architecture.md's
# "Code signing" section for why this matters). Safe to re-run — it's a
# no-op if the certificate already exists.
Scripts/setup-signing-cert.sh

# One-time: store your Groq key in the login Keychain. VoxFlow only ever
# reads this key at runtime (Sources/VoxFlow/KeychainCredentialStore.swift)
# — there is no in-app field to paste it into, and it is never written to
# any file in this repo.
security add-generic-password -a "groq-api-key" -s "com.mihirk.voxflow" -w "<your-groq-key>" -U

# Build, sign, and launch
Scripts/run.sh
```

On first launch, VoxFlow shows a short onboarding window walking through the two permissions it needs (Microphone, Accessibility) with live status and System Settings links. Hold the hotkey (Right Option by default — Left Option, Left Command and Right Command are also selectable) anywhere to dictate; click the waveform menu-bar icon and choose "Open VoxFlow" for the full app window (Insights, Transcript Log, Dictionary, Snippets, App Tones, Commands, Settings).

## Build and run

```
Scripts/run.sh     # build, sign and launch the app
Scripts/test.sh    # run the Swift Testing suite (bare `swift test` fails under Command Line Tools — see docs/architecture.md)
```

## Structure

- `Sources/VoxFlow` — menu bar app + main window: hotkey/audio capture, text insertion, the window's sidebar screens (`MainWindow.swift` and the per-screen `*Screen.swift` files), `VoxFlowTheme.swift`, onboarding, all live system-integration code (AppKit, Keychain, Speech framework).
- `Sources/VoxFlowCore` — pure logic: transcription/cleanup engine protocols and failover chains, prompt assembly, command recognition, latency budgets. No AppKit or networking — this is what's unit-tested.
- `Tests/` — Swift Testing suite (`Scripts/test.sh` to run).
- `Scripts/` — build (`bundle.sh`), run (`run.sh`), test (`test.sh`), signing-cert setup (`setup-signing-cert.sh`), icon generation (`generate-icon.swift`, `test-icon.sh`), and cleanup-prompt quality eval (`eval-cleanup.sh`).
- `Resources/` — the app icon (`AppIcon.icns`).
- `docs/` — architecture (`architecture.md`) and reference research notes.

## License

MIT — see [LICENSE](LICENSE).
