# VoxFlow Reference Report — Step 1 (2026-07-13)

Survey of open-source Wispr Flow alternatives + free STT/LLM stack selection.
Machine (verified): Apple M4, 16 GB RAM, macOS 26.3, Swift 6.3.1 CLT-only, Ollama installed.

## 1. Project comparison

| Project | Lang | License | Stars | Last push | Standout |
|---|---|---|---|---|---|
| **FluidVoice** (altic-dev) | Swift | GPL-3.0 | 7.7k | 2026-07-13 | SwiftPM build (no Xcode project!); custom-trained on-device enhancement model; CoreML ASR (FluidAudio) |
| **VoiceInk** (Beingpax) | Swift | GPL-3.0¹ | 5.5k | 2026-07-12 | Most complete Wispr parity: modes/per-app "power modes", native SpeechAnalyzer service, hardened paste layer |
| **freeflow** (zachlatta) | Swift | **MIT** | 2.2k | 2026-07-10 | Small, clean, SwiftPM; exact architecture we want (Groq Whisper + LLM post-process); MIT = code copying permitted |
| Handy (cjpais) | Rust/Tauri | MIT | 26k | 2026-07-12 | Huge community, fully offline, cross-platform; not Swift so patterns only |
| OpenSuperWhisper (Starmel) | Swift | MIT | 2.1k | 2026-07-09 | Simple whisper.cpp wrapper; less feature depth |
| OpenWhispr | TypeScript/Electron | MIT | 4.5k | 2026-07-12 | Parakeet + BYOK cloud; Electron, patterns only |
| whisper-writer (savbell) | Python | GPL-3.0 | 1.1k | **2024-08** (stale) | Skip |

¹ GitHub API shows NOASSERTION but LICENSE file is verbatim GPL-3.0 (checked).

**Cloned into `references/` (gitignored):** FluidVoice, VoiceInk, freeflow.
**License rule:** copy freely from **freeflow (MIT)** with attribution; **patterns only** from FluidVoice/VoiceInk (GPL-3.0 — copying code would force VoxFlow to be GPL; keep it clean).

## 2. How they solve the four hard problems

### (a) Global hold-to-talk hotkey
- **freeflow `GlobalShortcutBackend.swift`** (MIT — copyable): `CGEvent.tapCreate` on `.cgSessionEventTap` with mask `flagsChanged|keyDown|keyUp`; handles `tapDisabledByTimeout` / `tapDisabledByUserInput` by calling `CGEvent.tapEnable` + re-reading modifier state (exactly the sleep/wake bug our review flagged — solved here, lines ~85-95). Fn-key state tracked via `ModifierKeyEventState`.
- VoiceInk `Shortcuts/ShortcutMonitor.swift` similar; FluidVoice `Services/GlobalHotkeyManager.swift`.
- **Adopt:** freeflow's backend nearly verbatim (MIT), including its tap re-enable and escape-key cancel hook.

### (b) Mic/audio pipeline
- freeflow `AudioRecorder.swift`: AVAudioEngine, with `LiveAudioLevelNormalizer` for the pill's level meter.
- VoiceInk has a `CoreAudioRecorder.swift` fallback for AVAudioEngine edge cases + `SoundPlaybackEngine` for start/stop cues.
- **Adopt:** freeflow's recorder; add VoiceInk's config-change handling pattern (device switches).

### (c) Transcription
- **freeflow `TranscriptionService.swift`** (MIT — copyable): Groq OpenAI-compatible `/audio/transcriptions`, default `whisper-large-v3`, `verbose_json` to get segment metadata used by a **hallucination filter** (drops segments with high no-speech probability — a real-world Whisper gotcha we'd have hit later). Timeout race handling included. Also has `RealtimeTranscriptionService.swift` worth studying.
- FluidVoice: on-device CoreML ASR via their FluidAudio package (`B/cohere-coreml-asr` branch) + `transcribe-cpp-swift` (whisper.cpp binding). Heavy; GPL.
- **VoiceInk `Transcription/Native/NativeAppleTranscriptionService.swift`**: the macOS 26 **SpeechAnalyzer/SpeechTranscriber** path — confirms the API shape: locale asset check (`assetContext.status == .installed`), OS-managed language-model download, `#available(macOS 26, *)`. On our 26.3 machine this compiles without their feature gate.
- **Adopt:** freeflow's service as the cloud engine; VoiceInk's native service as the *shape* of our SpeechAnalyzer fallback (pattern only, GPL).

### (d) Text insertion into focused app
- **VoiceInk `Paste/CursorPaster.swift`** is the most hardened implementation surveyed (pattern only, GPL): full multi-item clipboard snapshot → transient-marked write with session ID → Cmd-V via `CGEventSource(stateID: .privateState)` with 10 ms inter-event delays → **ownership-checked restore** (only restores if the pasteboard still holds our session's content — solves the clipboard-manager race). Handles the "QWERTY ⌘" layout trap by using physical key code 9 via AppleScript when needed. Accessibility check via `AXIsProcessTrusted()`.
- **Adopt:** re-implement this design in our own code (it matches our plan's S4 spec almost point-for-point, plus two traps we hadn't listed: privateState event source, and the ⌘-layout key code fix).

## 3. STT options (free), verified 2026-07-13

| Option | Type | Quality | Latency (10 s clip) | Free limits | Dictionary bias | Integration |
|---|---|---|---|---|---|---|
| **Groq `whisper-large-v3-turbo`** | Cloud | Excellent, strong on technical vocab | ~0.3–0.7 s typical | 2,000 req/day, 7,200 audio-sec/hour, 25 MB/file ([docs](https://console.groq.com/docs/rate-limits), [analysis](https://www.grizzlypeaksoftware.com/articles/p/groq-api-free-tier-limits-in-2026-what-you-actually-get-uwysd6mb)) | `prompt` param ✓ | URLSession multipart — zero installs |
| **Apple SpeechAnalyzer** (macOS 26) | Local (on-device) | Very good; Apple's new large model | Fast, streaming-capable | **None. No key, no limit** | Custom vocabulary API | Native `Speech` framework — zero installs; one-time OS-managed language asset download (size shown by OS; needs Mihir's OK) |
| Gemini free-tier audio | Cloud | Good | ~1–2 s | ~10 RPM / model-dependent RPD ([docs](https://ai.google.dev/gemini-api/docs/rate-limits)) | Via prompt | REST |
| whisper.cpp (Metal) | Local | Excellent (large-v3) | ~1–3 s on M4 | None | `initial_prompt` ✓ | C lib via SwiftPM **or** prebuilt — build step + ~1.5–3 GB model download (approval) |
| Parakeet via MLX | Local | Very good, very fast | <1 s | None | Limited | **Python sidecar process** — most complex integration |

**Daily-heavy-dictation check (~200 × 10 s = ~33 min audio/day):** Groq free tier allows 2,000 req/day and 2 h audio *per hour* — 10× headroom. Fits easily.

## 4. Cleanup-LLM options (free), verified 2026-07-13

Cleanup call ≈ 300 in + 150 out ≈ 450 tokens.

| Option | Free limits | 200 calls/day fits? | Latency | Notes |
|---|---|---|---|---|
| **Groq `llama-3.1-8b-instant`** | ~14.4k req/day, ~500k TPD tier ([limits](https://console.groq.com/docs/rate-limits), [analysis](https://tokenmix.ai/blog/groq-free-tier-limits-2026)) | ✓ (5×+ headroom) | ~200–400 ms | 8B is plenty for filler-removal/punctuation; same API key as STT |
| Groq `llama-3.3-70b-versatile` | 1k req/day but **100k TPD** → ~220 calls/day effective | Barely | ~500 ms | Binding token cap; overkill for cleanup |
| **Gemini Flash free** | ~1,500 req/day, 10 RPM ([docs](https://ai.google.dev/gemini-api/docs/rate-limits)) | ✓ (10 RPM can pinch bursts) | ~500–900 ms | Good secondary; separate vendor = real failover |
| **Ollama local (qwen2.5:3b or llama3.2:3b)** | None | ✓ | ~300–800 ms on M4 16 GB | ~1.9–2 GB model pull (approval needed); offline path |

## 5. Privacy notes (feeds Mihir's cloud-vs-local choice at S5a)

- **Groq:** states API inputs/outputs are not used for model training; data may be transiently processed/retained for abuse monitoring. Verify current terms at key-creation time (console.groq.com → Terms). Dictated audio (including CogniSwitch work content) transits Groq's US cloud.
- **Google Gemini free tier:** Google documents that **free-tier API content may be used to improve products** (human review possible). Do not dictate sensitive work content through the free Gemini path. Paid tier changes this, but paid is out of scope.
- **Apple SpeechAnalyzer / Ollama:** fully on-device. Nothing leaves the Mac.

## 6. Recommended stack

- **STT primary: Groq `whisper-large-v3-turbo`** — best quality-per-latency, `prompt` param for the S8 dictionary, zero install, one free key. freeflow's MIT service is a copy-ready starting point (incl. hallucination filter).
- **STT fallback: Apple SpeechAnalyzer** (S5b) — zero key, zero rate limit, on-device, streaming-capable; the free-tier rug-pull insurance. Needs one OS-managed en-US asset download (Mihir approves at S5b).
- **Cleanup primary: Groq `llama-3.1-8b-instant`** (same key as STT); **secondary: Gemini Flash free** (separate vendor); **local fallback: Ollama `qwen2.5:3b`** (~1.9 GB pull, approval at S6).
- If Mihir chooses **local-only** at S5a for privacy: SpeechAnalyzer becomes primary, Groq becomes the secondary, quality bar likely still met.

## 7. Honest "unrealistic for free" list

1. **Wispr's custom-trained enhancement model** — FluidVoice trained their own; we approximate with prompt-engineered general LLMs. Expect ~90% of the polish, not 100%.
2. **True streaming partials from the cloud engine** — Groq's endpoint is file-based. SpeechAnalyzer can stream locally; cloud path stays release-then-transcribe (matches Wispr's visible behavior anyway).
3. **Notarized distribution** — needs a $99/yr Apple Developer account. Self-signed local build only (already in plan, S11a).
4. **Editing text already inserted in another app** — Wispr's deep AX-tree editing is a large separate project; our S9 covers in-utterance corrections only (already scoped).

## 8. Install list (NOTHING installed yet — each needs Mihir's approval when its step arrives)

| When | What | Size | Why |
|---|---|---|---|
| S5a | none | — | Milestone 1 is zero-install (Groq cloud + built-in frameworks) |
| S5b | SpeechAnalyzer en-US language asset (OS-managed) | OS shows size at download (order of ~1 GB) | Local STT fallback |
| S6 | `ollama pull qwen2.5:3b` | ~1.9 GB | Local cleanup fallback |
| optional | whisper.cpp + large-v3 model | ~1.5–3 GB | Only if SpeechAnalyzer quality disappoints |
