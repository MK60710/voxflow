# VoxFlow — Software Error Log

A log of the software errors hit while building VoxFlow, for learning. Every
entry has the same three fields:

- **Error** — what went wrong (the observable symptom).
- **Caused by** — the origin: who/what created it (self-inflicted fix, wrong
  assumption, original code defect, OS/platform behavior, library limitation,
  or stale state).
- **Solution** — how it was actually fixed.

Period covered: 2026-07-23 → 2026-07-30. Newest arc (the hotkey) first.

---

## Hotkey: "only records when the cursor is over the menu bar"

### E1 — Global hotkey didn't fire unless VoxFlow was active
- **Error:** Holding Right Option with the cursor away from the menu bar did
  nothing; recording only started when the menu was open.
- **Caused by:** OS/platform behavior. The `CGEvent` tap was being disabled by
  macOS with `kCGEventTapDisabledByUserInput` on this menu-bar-only
  (`LSUIElement`) agent app. Events only flowed while VoxFlow was active
  (opening the menu makes it active).
- **Solution:** Replaced the `CGEvent` tap with `NSEvent` global + local
  monitors — the AppKit API intended for global hotkeys, not subject to that
  disable. `HotkeyManager` made `@MainActor`. Commit `12dd8d6`. Live-confirmed
  working from anywhere.

### E2 — Hotkey suppressed by a false "permission not granted"
- **Error:** After the NSEvent switch, the hotkey wouldn't install at all; log
  said "Input Monitoring / Accessibility not granted."
- **Caused by:** Self-inflicted. My permission pre-check queried **Input
  Monitoring** (`IOHIDCheckAccess`), the wrong permission for `NSEvent`
  (which needs **Accessibility**, already granted). Worse, the check *threw*
  and skipped installing the monitors entirely.
- **Solution:** Check **Accessibility** (`AXIsProcessTrusted`) instead, and
  install the monitors **unconditionally** — a missing grant is a guidance
  case, not a reason to leave the hotkey uninstalled. Commit `12dd8d6`.

### E3 — Two fixes that didn't fix it (wasted effort)
- **Error:** Hotkey still failed after (a) a ~180x callback-speed optimization
  and (b) moving the tap to a dedicated background thread.
- **Caused by:** Wrong assumptions. (a) assumed slow callbacks were disabling
  the tap; (b) assumed the main run loop wasn't servicing it. The real cause
  (E1) was the OS *disabling* the tap — neither hypothesis addressed that.
- **Solution:** Stop patching the low-level primitive; switch APIs (E1). The
  wasted rounds are the lesson: two failed patches on the same primitive was
  the signal to change approach, not patch a third time.

### E4 — Recording started with the menu open, masking whether fixes worked
- **Error:** Couldn't tell if a fix worked because tests were run with the menu
  open, cursor position uncontrolled, or against a stale app instance running
  27h through sleep/wake (its tap long dead).
- **Caused by:** Uncontrolled test conditions (process discipline).
- **Solution:** Kill stale instances, relaunch fresh, control cursor/menu
  state, start a fresh log stream immediately before each action, one variable
  at a time.

---

## Text insertion

### E5 — ~30% of pastes silently didn't land (self-inflicted)
- **Error:** Dictated/inserted text landed only ~70% of the time, even into a
  plain TextEdit field; VoxFlow logged "inserted" every time.
- **Caused by:** **Self-inflicted.** I had earlier added a "menu-tracking"
  mitigation (post a synthetic Escape before insertion) on an *unproven*
  theory. A `MenuBarExtra` `.onDisappear` never fired, so its state stuck
  `true` and the Escape fired before **every** paste, corrupting ~30% of them.
- **Solution:** Removed the mitigation. Verified with a new self-test harness
  (10× auto-verified via the Accessibility API): failure rate went from ~30%
  to 10/10. Commit `a25a2dd`.

### E6 — Long pastes landed only partially
- **Error:** Long dictations inserted only the first chunk of text.
- **Caused by:** Original code defect. A fixed 0.12s clipboard-restore dwell
  clobbered the transient clipboard before terminal/pty apps finished reading
  a large paste; the synthetic Cmd-V was also two instantaneous events with no
  pacing.
- **Solution:** `PasteboardDwellTiming` scales the dwell with text length
  (toward VoiceInk's proven 2.0s ceiling); Cmd-V is now four paced events
  (Cmd-down, V-down, V-up, Cmd-up, 10ms apart). Pattern read from VoiceInk's
  `CursorPaster.swift`. Commit `59963d3`.

### E7 — Self-test harness miscounted its own results
- **Error:** The harness reported 6/10 landed when the real answer was 7/10.
- **Caused by:** The harness's own AX verification did a single-shot read that
  raced the target app and returned transient-empty values.
- **Solution:** Poll the AX read until it stabilizes on the unique marker
  instead of a single read. Commit `a25a2dd`.

---

## Cleanup (LLM post-processing)

### E8 — Cleanup silently dropped half of a long transcript
- **Error:** "I spoke longer but only this much came." A 16s clip transcribed
  fully but cleanup returned only the first half.
- **Caused by:** Library/model behavior. Groq `llama-3.1-8b-instant` violated
  its own "do not drop content" prompt (likely anchored by the Code/Terminal
  tone's short few-shot examples). The existing empty-string check didn't catch
  a *partial* loss. Confirmed by replaying the exact transcript against the API.
- **Solution:** `ContentPreservationGuard` — a word-count retention check that
  falls back to the raw transcript when cleanup drops too much. Commit
  `500876f`.

---

## Audio

### E9 — Recordings uploaded at double the needed size
- **Error:** Every recording was 2x larger than necessary, slowing uploads.
- **Caused by:** Original code defect. `AudioRecorder` wrote the WAV as 32-bit
  float; Whisper only needs 16-bit PCM.
- **Solution:** `PCM16Conversion` (clamp to ±1.0 first — real mic input
  exceeds it — then scale by 32767, not 32768, to avoid Int16 overflow),
  reusing the existing `WAVEncoder`. 50% size reduction. Commit `c88d038`.

### E10 — A fast key-release could be dropped
- **Error:** Occasionally a quick tap started recording but never stopped (or
  vice-versa).
- **Caused by:** Original code defect (race). `requestMicrophonePermissionIfNeeded`
  hopped through `Task { @MainActor }` even when permission was already
  granted, opening a window where a fast key-up landed before recording
  started and was dropped by the `isRecording` guard.
- **Solution:** Made it `@MainActor` so the granted/denied cases run inline,
  closing the race. Commit `64c423b`.

---

## Environment / tooling / process

### E11 — Keychain re-prompted on every rebuild
- **Error:** macOS asked for the login password to access the Groq key on
  every launch after a rebuild.
- **Caused by:** Each rebuild changed the binary; the Keychain item's ACL only
  authorized the exact previous binary. (Note: the codesign *designated
  requirement* is cert-based/stable, so *TCC* grants persist — it was
  specifically the Keychain ACL.)
- **Solution:** Set the item's ACL to allow-all (`security add-generic-password
  -A`). Mihir ran it (the classifier blocks the agent from `security`).

### E12 — `log show`/`log stream` silently failed
- **Error:** Log commands returned nothing / "too many arguments."
- **Caused by:** The `log` command was shadowed by a zsh builtin.
- **Solution:** Call `/usr/bin/log` explicitly.

### E13 — Empty logs when read after a delay
- **Error:** Diagnostic logs came back empty even though activity had happened.
- **Caused by:** The system log-stream buffer evicts VoxFlow's entries quickly,
  and across multi-day gaps the stream process died.
- **Solution:** Start a fresh `log stream` immediately before each test and
  read it right after.

### E14 — Compile error on `NSMenu.cancelTracking()`
- **Error:** Build failed: "instance member cannot be used on type."
- **Caused by:** Self-inflicted — used an instance method as if static.
- **Solution:** Abandoned that approach (the whole menu-tracking mitigation was
  later removed anyway — see E5).

### E15 — Python couldn't read the WAVs / call the API
- **Error:** `wave` module errored on float32 WAVs; `urllib` hit SSL cert
  verification failures.
- **Caused by:** Library limitations (`wave` doesn't support float; Python's
  cert store).
- **Solution:** Manual WAV header parsing; `curl` instead of `urllib`.

### E16 — Stale memory sent an agent to redo finished work
- **Error:** An agent was dispatched to "execute Step 1" of the build plan.
- **Caused by:** Stale state — project memory said "next: Step 1" when Steps
  1–2 were already committed weeks earlier.
- **Solution:** The agent checked `git log` first, found the work done, and
  stopped instead of duplicating it. Memory now says "read PROGRESS.md first."

### E17 — Background agents stalled / hit stream errors mid-task
- **Error:** A build agent stalled twice on a slow command; another hit a
  transient API stream error while writing files.
- **Caused by:** Agent/infra flakiness and long-running unattended steps.
- **Solution:** Resumed from the uncommitted working-tree state; instructed
  agents to commit incrementally so partial progress survives.

---

## The three patterns worth internalizing

Across the entries above, three origins account for the most wasted time:

1. **Self-inflicted fixes on unproven theories** (E5, E2, E14) — a "fix" for a
   theory you haven't confirmed becomes a new bug or a confounding variable.
   Prove the mechanism first.
2. **Patching the wrong layer** (E3) — two failed patches on the same low-level
   primitive means switch to the higher-level API, don't patch again.
3. **Reasoning from too little data** (E1/E3 before the harness existed) —
   build the measurement harness early; a real failure *rate* cracks
   intermittent bugs that anecdotes never will.

---

## Operator critique — prompting, hooks & skills (harsh, by request)

Mihir asked for unsparing, specific criticism of his own prompting and setup,
cited to real prompts. No softening. The goal is learning, so each point ends
with what better looks like.

### P1 — Chronic under-specification. Your default prompt was one word.
Across this multi-day session the most common inputs were `"yes"`, `"next"`,
`"continue"`, `"open"`, `"no"`, `"nope"`. `"open"` alone appeared ~10 times,
each time ambiguously meaning "I quit the app, relaunch it." One-word replies
to *diagnostic* questions were the expensive ones: when I asked what happened
on a hotkey hold you answered `"nope"` and `"no"` with nothing else, so I had
to spend another full round-trip extracting the actual observation. **Better:**
one extra clause. "no — pill stayed on Ready, nothing in the log" is one line
that saves a whole exchange.

### P2 — Vague bug reports were the single biggest time sink.
`"step 3 is not working"` → (asked for detail) → `"nothing appeard"`.
`"its not putting the text in"`. `"the recording part not sure"`.
`"so its re recording, but it's not translating or transcribing that into
text."` None of these say *what you did, what you expected, what happened* —
the three things a bug report needs. Your own `CLAUDE.md` has a rule to demand
a screenshot on vague feedback; you were the one giving the vague feedback.
The irony: once you *did* start pasting screenshots and the actual typed text
(the `café ☕️ naïve` result, the Keychain dialog, the Wispr window), diagnosis
sped up dramatically. **Better:** lead with the screenshot/observation, not
"it's not working."

### P3 — You dumped a huge low-value payload, then complained about cost.
Twice you pasted the **entire** Wispr Flow marketing blog article — thousands
of tokens of "Wispr Flow enables communication at speaking speed" fluff — with
`"does thi shelp["`. It had zero technical value; I had to tell you so. That
paste (x2) is a direct contributor to the `~598k uncached` context you later
flagged as a cost concern. You created the bloat you complained about.
**Better:** paste a link or one sentence ("Wispr's site says X, can we do
that?"), never a full marketing page.

### P4 — You didn't answer the questions you were asked.
When I put up a structured choice about how the autonomous loop should behave,
you replied `"see i am going to be away from the laptop for about half an
hour"` — context, not an answer, forcing me to infer the decision. Several
`AskUserQuestion` prompts got a tangent instead of a pick. **Better:** pick the
option, then add context. The tools exist to make your intent unambiguous;
sidestepping them re-introduces the ambiguity they remove.

### P5 — You context-switched in the middle of delicate diagnosis.
Mid-hotkey-debug, in consecutive turns, you jumped to: model choice
(`"if change model to pus 5 will you do a better job"`), cost
(`"~598k uncached what does this mean"`), a product pivot
(`"can we make the menu bar always open like wispr flow"`), and self-doubt
(`"also did i make a mistake by asking you to ad dthis pill"`). Each is a fair
question, but fired *during* a live root-cause hunt they fragmented focus and
padded context. **Better:** batch the meta-questions for a break point; when
we're mid-diagnosis, keep the thread.

### P6 — Garbled prompts cost parse time and risk misexecution.
`"is it possible to do thi sas a loop"`, `"who were the error created from"`,
`"can i give you some perission to just bypass it"`, `"add a section... harsh
cristicism about my prompting hookes skills"`. Mostly recoverable, but a few
were genuinely ambiguous and I had to guess or re-ask. On a task where a
misread instruction can trigger a wrong build, typo density is a real risk,
not a cosmetic one. **Better:** a 5-second re-read before send on anything
consequential.

### P7 — You asked for full autonomy on a task that is inherently hands-on.
Your second prompt was `"is it possible to do thi sas a loop so that you test
and iterate and at the final product just let me know."` The blueprint is
riddled with human gates — install approvals, live mic/keyboard demos,
privacy decisions. "Just let me know at the end" was structurally impossible,
and I had to push back. Good instinct to want leverage; wrong shape for this
work. **Better:** ask "which parts can run unattended vs need me?" instead of
assuming end-to-end autonomy.

### P8 — Model churn.
Multiple `/model` flips, `"if change model to pus 5"` (there is no Opus 5),
then `"should i switch to sonnet 5 or is opus 4.8 better"`. Deliberation is
fine; the back-and-forth mid-task was churn. **Better:** pick the strong model
for hard debugging and leave it.

### Hooks — your safety hook fought your own workflow all session.
`bash-safety.sh` blocks *all* `git push` (one carve-out), all file deletion,
and `security`. On a **solo, private** repo that meant: I couldn't push `main`
(you ran it), couldn't fix the Keychain ACL (you ran it), couldn't clean up
files. That's a lot of manual `!`-prefix interventions for a personal project.
The hook is a blunt instrument applying "sensitive client work" caution to a
throwaway-friendly personal repo. **Better:** scope the push-block by repo (you
already did this for VoxFlow *after* it bit us — do it up front), or relax it
for personal projects.

### Skills — you built the exact tool for your weakness and never used it.
You have a `/race` skill that "restructures any vague prompt using the RACE
framework." Your prompting was consistently vague (P1, P2). You never once
reached for it. You also have `/brain-dump`, `/wrap`, `/status`, `/today` — in
a week-long session none were used until `/wrap` came up at the very end, and
only because I suggested it. You have an unusually large, well-built skill
library and you operate as if it doesn't exist. **Better:** when you catch
yourself about to send `"it's not working"`, that's the moment to run `/race`
or just write the three-line bug report it would have produced.

### What actually worked (kept short, since you wanted harsh).
Persistence through a genuinely miserable week-long bug; screenshots once
prompted; the right call to fix the blocker over pivoting to mac-dictation;
choosing Opus for the hard part; and asking for *this* critique at all —
that's real metacognition. The gap isn't judgment, it's input discipline:
your decisions were sound, your prompts were lazy, and the lazy prompts taxed
the sound decisions.
