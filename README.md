# VoxFlow

Hi! I'm Mihir and this is VoxFlow.

I really like how Wispr Flow works and how good it is. I wanted a free and open source version out there. So I built one. Hold a hotkey anywhere on your Mac, talk, let go and clean text shows up wherever your cursor is.

Hopefully it helps you out. I'd be thrilled if people used it. Even happier if someone went and built their own version off of it. Go nuts with it, it's MIT licensed.

## What's actually happening under the hood

Groq's Whisper model turns your speech into text. If you're offline or Groq's down, it quietly falls back to Apple's own Speech framework running right on your Mac. So it never just stops working. Then Groq's gpt-oss-20b cleans that raw text up (fixes the "umm"s and the rambling, all that), with a local Ollama model as backup if Groq's cleanup step ever goes down.

Where it's at right now: fully built out. Hold a key to talk, text gets typed straight into whatever app you're in, cloud and local failover on both the transcription and cleanup steps, a tone you can set per app, a personal dictionary for words it keeps messing up, snippets for stuff you say a lot, voice commands, a log of everything you've dictated and some stats on your usage, all inside a real window with a sidebar instead of just a menu bar dropdown.

## What you need

- macOS 26 or later
- Xcode Command Line Tools with Swift 6.3.1+ (`xcode-select --install`). You don't need full Xcode for this
- A free [Groq](https://console.groq.com) API key. Without one, VoxFlow still works, it just leans on the Apple Speech fallback and the cleanup isn't as sharp
- Optional: [Ollama](https://ollama.com) running locally. It's just a backup for the cleanup step if Groq is ever down, feel free to skip it

## Setting it up

```
git clone <this repo>
cd VoxFlow

# First run only: this sets up the cert VoxFlow signs itself with so its
# identity stays stable across rebuilds and macOS doesn't keep asking for
# permissions again. Fine to run more than once, it just no-ops after.
Scripts/setup-signing-cert.sh

# First run only: puts your Groq key in your login Keychain. VoxFlow only
# reads it at runtime, there's nowhere in the app to type it in and it
# never gets written to a file anywhere in this repo.
security add-generic-password -a "groq-api-key" -s "com.mihirk.voxflow" -w "<your-groq-key>" -U

# Optional, only if you want the local cleanup backup:
ollama pull llama3.2:3b
ollama serve

# Build it, sign it, launch it
Scripts/run.sh
```

First time you open it, it walks you through the two permissions it needs. After that you're good: hold the hotkey (Right Option by default, though a few other keys work too) anywhere to dictate. Or click the menu bar icon and hit "Open VoxFlow" for the full window instead.

```
Scripts/run.sh     # build, sign and launch
Scripts/test.sh    # run the tests (plain `swift test` won't work here, docs/architecture.md has why)
```

## Permissions it asks for

- **Microphone** so it can actually hear you
- **Accessibility** so the hotkey works anywhere and so it can type text into whatever app you're using

That's it, no screen recording, no camera, nothing else.

## Architecture, quick version

It's a menu bar app (no Dock icon) plus a real window for everything else. When you hold the hotkey, it grabs audio, sends it off to get transcribed, runs the result through cleanup, then types it into whatever app was focused when you started talking, with a cloud option and a local fallback on both the transcription and cleanup steps so one bad network day doesn't take the whole thing down. There's also a command mode that catches specific phrases before cleanup and fires off a real keyboard shortcut instead of typing anything.

Full breakdown, including the actual data flow diagram, is in `docs/architecture.md` if you want to dig in.

## Where everything lives

- `Sources/VoxFlow`: the app itself, hotkey/audio capture, text insertion, the window and its screens, onboarding, anything that touches AppKit, Keychain or the Speech framework
- `Sources/VoxFlowCore`: the pure logic, no AppKit or networking in here, just the transcription/cleanup engines and their failover, prompt assembly and command recognition. This is what actually has tests
- `Tests/`: the test suite
- `Scripts/`: build, run, test, signing setup, icon generation, an eval script for cleanup prompt quality
- `Resources/`: the app icon
- `docs/`: the architecture doc and some reference notes

## Contributing

PRs welcome. It started as a personal project so don't expect a huge roadmap. But if you want to add something or fix a bug, go for it.

## License

MIT, see [LICENSE](LICENSE).
