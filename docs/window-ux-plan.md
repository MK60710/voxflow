# VoxFlow Window UX Plan

Step 1 deliverable of `plans/voxflow-windowed-ui.md`. Verified against the live source (`Sources/VoxFlow/VoxFlowApp.swift`) on 2026-08-22, not just against the blueprint's own summary.

**Signed off by Mihir 2026-08-22:** sidebar structure as proposed below; Onboarding stays a standalone window. Step 2a can proceed.

## Current surface inventory (verified against live source)

**Dropdown (`MenuContent`):** status line, engine health + "Test Groq connection", cleanup status, "Insights…", "Transcript Log…" (⌘L), "Settings…" (⌘,), Quit (⌘Q).

**Settings (`SettingsView`, seven sections, confirmed by re-reading the full `Form` body):**
1. General — launch at login, hotkey picker, "Onboarding…" button
2. Transcription — prefer-local toggle
3. Cleanup — 3 toggles (cleanup on/off, auto-edits, list formatting)
4. Commands — voice commands on/off + read-only phrase list
5. App Tones (`ContextToneSettingsSection`) — per-app tone assignment editor
6. Snippets — add/remove/edit trigger→expansion pairs
7. Dictionary — add/remove/edit term + "sounds like" pairs

**Standalone windows:** Insights, Transcript Log, Onboarding (each its own hand-rolled `NSWindow`).

Everything above is accounted for below — nothing dropped.

## Proposed sidebar structure

Based on Wispr Flow's own real sidebar (Dictation, Notetaker, Insights, Dictionary, Snippets, Style, Transforms, Scratchpad — surveyed 2026-08-13; Notetaker/Transforms/Scratchpad were explicitly ruled out for VoxFlow already) plus VoxFlow's own engine-level concerns Wispr Flow doesn't have (Transcript Log, Commands, local/cloud engine settings).

```
┌─────────────────┬──────────────────────────────────┐
│  VoxFlow         │                                  │
│                  │   [Detail screen for the          │
│  ● Dictation     │    selected sidebar item]         │
│    Insights      │                                  │
│    Transcript Log│                                  │
│    Dictionary    │                                  │
│    Snippets      │                                  │
│    App Tones     │                                  │
│    Commands      │                                  │
│    Settings      │                                  │
│                  │                                  │
└─────────────────┴──────────────────────────────────┘
```

**Settings** = General + Transcription + Cleanup as sub-sections of one scrollable screen (they're infrastructure toggles, not content the way Dictionary/Snippets/App Tones are — grouping them keeps the sidebar from being dominated by technical settings).

**Dictation** is the default/landing screen — status, engine health, cleanup status (what the dropdown shows today).

## Onboarding — recommendation

`OnboardingCoordinator.showIfFirstRun()` fires before any window exists (`AppDelegate.applicationDidFinishLaunching`). Recommend: **keep Onboarding as its own lightweight standalone window**, not folded into the main window. It's a one-time, linear checklist (mic + Accessibility permissions) — forcing the full sidebar shell open for that adds complexity for zero benefit, and the standalone window already works. This is the one deliberate exception to "no standalone windows" that Step 6 of the blueprint already anticipates.

## Dropdown after the window exists

Status line + **"Open VoxFlow"** (opens the window, replaces "Insights…"/"Transcript Log…"/"Settings…") + Quit. Engine health and cleanup status lines move into the Dictation screen.

## What does NOT change

Global hotkey (hold-to-talk + tap-to-toggle), audio capture, transcription pipeline, text insertion, the recording pill overlay — none of this plan touches any of it.
