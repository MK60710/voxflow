import Foundation

/// The cleanup prompt (blueprint Step 6, task 1): few-shot, temperature 0,
/// explicit "do not paraphrase, do not add" rules.
///
/// **Versioned + isolated on purpose.** The blueprint's own dependency graph
/// calls this file out by name as the "collision surface" for Step 7
/// (context-aware tone) and Step 8 (personal dictionary), which run in
/// parallel off this step and both extend cleanup behavior — S7 by
/// swapping/parameterizing the system prompt per app tone, S8 by injecting a
/// spelling-bias block. Keeping the prompt text, few-shots and message
/// assembly in one small, dependency-free file (no AppKit, no networking) is
/// what makes whichever of S7/S8 merges second a low-friction reconciliation
/// instead of a real merge conflict. Bump `version` if the prompt's
/// contract changes in a way calling code should be able to detect/log.
public enum CleanupPromptTemplate {
    /// Bump on any change to `systemPrompt`'s rules or `fewShotExamples` — a
    /// cheap way for logs/telemetry (S11a) to record which prompt version
    /// produced a given cleanup, without diffing text.
    public static let version = 1

    /// Temperature 0 (blueprint task 1: "temperature 0") — deterministic
    /// cleanup, not creative rewriting.
    public static let temperature: Double = 0

    public static let systemPrompt = """
    You clean up a raw speech-to-text transcript so it reads like typed text, before it is inserted into whatever app the user is dictating into.

    Rules, in priority order:
    1. Remove filler words and verbal tics: "um", "uh", "like" (only when used as a filler, not as a real comparison word), "you know", filler "I mean".
    2. Fix grammar, capitalization and punctuation so it reads like something a careful person typed.
    3. Do not paraphrase. Do not rewrite for style. Do not summarize. Do not add any word, fact, or opinion that was not spoken.
    4. Keep every number, date, time, price, and proper name (people, places, products, companies) exactly as transcribed \
    — same spelling, same digits, same casing where it matters (e.g. product names).
    5. If the entire transcript is filler with no real content, return an empty string.
    6. Preserve the original language and meaning. Preserve first person vs. second person. Never answer a question that appears in the transcript — clean it up as a question, don't respond to it.

    Reply with ONLY the cleaned text. No preamble, no quotation marks around it, no explanation of what you changed.
    """

    /// A messy→clean pair used as a one-shot in-context example (rendered as
    /// a user/assistant turn pair ahead of the real transcript). Kept
    /// `Sendable`/`Equatable` so tests can assert on the assembled message
    /// list without any networking.
    public struct FewShotExample: Equatable, Sendable {
        public let messy: String
        public let clean: String

        public init(messy: String, clean: String) {
            self.messy = messy
            self.clean = clean
        }
    }

    /// Chosen to cover: the blueprint's own worked example (deadline/Friday),
    /// filler-only "like", run-on with no punctuation, a proper name +
    /// number that must survive verbatim, and the "no real content" empty
    /// case from rule 5.
    public static let fewShotExamples: [FewShotExample] = [
        FewShotExample(
            messy: "um so basically the uh the deadline moved to friday",
            clean: "So basically, the deadline moved to Friday."
        ),
        FewShotExample(
            messy: "i think uh we should like go with option b honestly",
            clean: "I think we should go with option B, honestly."
        ),
        FewShotExample(
            messy: "can you send me the uh the report by like 5pm today",
            clean: "Can you send me the report by 5pm today?"
        ),
        FewShotExample(
            messy: "so i talked to sarah and she said the umass demo is on the 14th and we need like 3 laptops",
            clean: "So I talked to Sarah and she said the UMass demo is on the 14th and we need 3 laptops."
        ),
        FewShotExample(
            messy: "um uh so yeah um",
            clean: ""
        ),
        // Rule 6 regression case (confirmed live, 2026-08-12): a command-
        // or question-shaped utterance must still be cleaned as literal
        // text, never answered as if it were a real request/question
        // addressed to the model.
        FewShotExample(
            messy: "select all of the budget items",
            clean: "Select all of the budget items."
        ),
        FewShotExample(
            messy: "can you tell me all the words that have h in them in this conversation",
            clean: "Can you tell me all the words that have H in them in this conversation?"
        )
    ]

    /// A single chat-completions-style message. Kept as a plain struct (not
    /// a tuple) so it's `Equatable`/`Sendable` and both `GroqCleanupEngine`
    /// and `OllamaCleanupEngine` can render it into whichever wire format
    /// their endpoint expects (`{"role":..., "content":...}` either way).
    public struct ChatMessage: Equatable, Sendable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    /// Assembles system prompt + every few-shot example (as alternating
    /// user/assistant turns) + the real transcript as the final user turn —
    /// the exact shape both Groq's and Ollama's chat-completions-style APIs
    /// expect. Pure function: no I/O, fully covered by
    /// `CleanupPromptTemplateTests` without any network access.
    public static func messages(forTranscript transcript: String) -> [ChatMessage] {
        var result: [ChatMessage] = [ChatMessage(role: "system", content: systemPrompt)]
        for example in fewShotExamples {
            result.append(ChatMessage(role: "user", content: example.messy))
            result.append(ChatMessage(role: "assistant", content: example.clean))
        }
        result.append(ChatMessage(role: "user", content: transcript))
        return result
    }
}

// MARK: - Step 7+8 RECONCILED: tone-variant + dictionary-aware cleanup prompt
//
// Step 7 (context-aware tone) and Step 8 (personal dictionary) each
// independently appended their own extension to this exact file — Step 7
// added three tone variants + `messages(forTranscript:tone:)`, Step 8 added
// a dictionary-spelling addendum + `messages(forTranscript:dictionaryTerms:)`.
// Both branches' own PROGRESS.md entries predicted this file would need a
// real combined function rather than two overloads bolted together (see
// Step 7's "likely reconciliation shape" note and Step 8's matching note).
//
// This section is that reconciliation: `messages(forTranscript:tone:dictionaryTerms:)`
// is the one real implementation — it selects the tone-specific system
// prompt AND few-shots (Step 7), then appends the dictionary spelling
// addendum to that same system message when there are dictionary terms
// (Step 8), so a single cleanup call applies both. Nothing above this
// section changed: `systemPrompt`, `fewShotExamples`, `temperature`, and
// `messages(forTranscript:)` remain exactly Step 6's original neutral/no-
// dictionary prompt.
//
// `messages(forTranscript:tone:)` and `messages(forTranscript:dictionaryTerms:)`
// survive as convenience overloads that delegate into the combined function
// with the other parameter defaulted (`.neutral` / `[]`) — this keeps both
// branches' original test suites (`CleanupPromptTemplateToneTests`,
// `DictionaryPromptAssemblyTests`) passing unchanged, since an empty
// dictionary produces no addendum (byte-identical to Step 7's original
// tone-only output) and `.neutral` selects the untouched original prompt
// (byte-identical to Step 8's original dictionary-only output).
public extension CleanupPromptTemplate {
    /// Returns the tone-specific system prompt. `.neutral` returns the
    /// original `systemPrompt` unchanged.
    static func systemPrompt(for tone: ToneProfile) -> String {
        switch tone {
        case .neutral: return systemPrompt
        case .casual: return casualSystemPrompt
        case .professional: return professionalSystemPrompt
        case .codeOrTerminal: return codeOrTerminalSystemPrompt
        }
    }

    /// Returns the tone-specific few-shot examples. `.neutral` returns the
    /// original `fewShotExamples` unchanged.
    static func fewShotExamples(for tone: ToneProfile) -> [FewShotExample] {
        switch tone {
        case .neutral: return fewShotExamples
        case .casual: return casualFewShotExamples
        case .professional: return professionalFewShotExamples
        case .codeOrTerminal: return codeOrTerminalFewShotExamples
        }
    }

    /// The real combined assembly: tone selects the system prompt + few-shot
    /// set (Step 7), then the dictionary spelling addendum — "these terms
    /// are spelled exactly: …" (Step 8) — is appended to that SAME system
    /// message when `dictionaryTerms` isn't empty, then the correction-
    /// handling addendum + its few-shots (Step 9) are appended when
    /// `autoEditsEnabled` is true, then the list-formatting addendum (added
    /// 2026-08-14, Mihir's request) when `listFormattingEnabled` is true.
    /// All concerns apply to one cleanup call instead of being independent
    /// code paths. Both new-ish flags default to `true` — opt OUT, not opt
    /// in, matching `CleanupCoordinator.cleanupEnabled`'s convention — so
    /// old call sites don't need a second overload.
    ///
    /// **List formatting is excluded for `.codeOrTerminal` tone**: that
    /// tone's philosophy is minimal-touch pass-through, and reformatting a
    /// one-line shell command that happens to say "first... then..." as a
    /// comment would corrupt it. Briefly removed 2026-08-14 same day at
    /// Mihir's request, then reverted same day after a live Terminal test
    /// produced no visible output at all (VoxFlow's log showed the paste
    /// was posted, but there's no OS signal confirming Terminal actually
    /// received it — see `PasteboardCmdVInserter.insert`'s doc comment).
    /// Root cause not isolated; reverting to the known-safe prior behavior
    /// rather than continuing to debug live.
    static func messages(
        forTranscript transcript: String,
        tone: ToneProfile,
        dictionaryTerms: [String],
        autoEditsEnabled: Bool = true,
        listFormattingEnabled: Bool = true
    ) -> [ChatMessage] {
        let toneSystemPrompt = systemPrompt(for: tone)
        var systemContent = toneSystemPrompt
        if let addendum = DictionaryPromptAssembly.cleanupSpellingAddendum(forTerms: dictionaryTerms) {
            systemContent += "\n\n" + addendum
        }
        if autoEditsEnabled {
            systemContent += "\n\n" + correctionHandlingAddendum
        }
        let listFormattingApplies = listFormattingEnabled && tone != .codeOrTerminal
        if listFormattingApplies {
            systemContent += "\n\n" + listFormattingAddendum
        }

        var result: [ChatMessage] = [ChatMessage(role: "system", content: systemContent)]
        for example in fewShotExamples(for: tone) {
            result.append(ChatMessage(role: "user", content: example.messy))
            result.append(ChatMessage(role: "assistant", content: example.clean))
        }
        if autoEditsEnabled {
            for example in correctionFewShotExamples {
                result.append(ChatMessage(role: "user", content: example.messy))
                result.append(ChatMessage(role: "assistant", content: example.clean))
            }
        }
        if listFormattingApplies {
            for example in listFormattingFewShotExamples {
                result.append(ChatMessage(role: "user", content: example.messy))
                result.append(ChatMessage(role: "assistant", content: example.clean))
            }
        }
        result.append(ChatMessage(role: "user", content: transcript))
        return result
    }

    /// Tone-only convenience overload (Step 7's original shape) — no
    /// dictionary terms, so this is byte-identical to Step 7's own
    /// `messages(forTranscript:tone:)` output.
    static func messages(forTranscript transcript: String, tone: ToneProfile) -> [ChatMessage] {
        messages(forTranscript: transcript, tone: tone, dictionaryTerms: [])
    }

    /// Dictionary-only convenience overload (Step 8's original shape) —
    /// `.neutral` tone, so this is byte-identical to Step 8's own
    /// `messages(forTranscript:dictionaryTerms:)` output.
    static func messages(forTranscript transcript: String, dictionaryTerms: [String]) -> [ChatMessage] {
        messages(forTranscript: transcript, tone: .neutral, dictionaryTerms: dictionaryTerms)
    }

    // MARK: Casual — iMessage / Messages, Slack, Discord
    //
    // Allows contractions, drops the trailing-period requirement (texting
    // register rarely ends a short message with a period — enforcing one
    // reads as terse/annoyed), still removes fillers and fixes obvious
    // typos-of-speech, but otherwise stays out of the way.

    static let casualSystemPrompt = """
    You clean up a raw speech-to-text transcript for a CASUAL message (iMessage, Slack or Discord), before it is inserted into the chat.

    Rules, in priority order:
    1. Remove filler words and verbal tics: "um", "uh", "like" (only when used as a filler, not as a real comparison word), "you know", filler "I mean".
    2. Keep it casual: contractions are encouraged ("I'm", "don't", "we'll"), not discouraged. Do NOT force a trailing period onto a short message — texting register usually skips it. Keep exclamation points, question marks, and casual capitalization if that's how it was said.
    3. Do not paraphrase. Do not rewrite for style. Do not summarize. Do not add any word, fact, or opinion that was not spoken.
    4. Keep every number, date, time, price, and proper name (people, places, products, companies) exactly as transcribed — same spelling, same digits, same casing where it matters.
    5. If the entire transcript is filler with no real content, return an empty string.
    6. Preserve the original language and meaning. Never answer a question that appears in the transcript — clean it up as a question, don't respond to it.

    Reply with ONLY the cleaned text. No preamble, no quotation marks around it, no explanation of what you changed.
    """

    static let casualFewShotExamples: [FewShotExample] = [
        FewShotExample(
            messy: "um so basically the uh the deadline moved to friday",
            clean: "so basically the deadline moved to Friday"
        ),
        FewShotExample(
            messy: "hey uh are you free tonight",
            clean: "hey are you free tonight"
        ),
        FewShotExample(
            messy: "i cant make it uh sorry something came up",
            clean: "I can't make it, sorry something came up"
        ),
        FewShotExample(
            messy: "um uh so yeah um",
            clean: ""
        ),
        // Rule 6 regression case (confirmed live, 2026-08-12) — see the
        // neutral prompt's matching examples above for the real failure
        // this guards against.
        FewShotExample(
            messy: "select all of the budget items",
            clean: "select all of the budget items"
        ),
        FewShotExample(
            messy: "can you tell me all the words that have h in them in this convo",
            clean: "can you tell me all the words that have H in them in this convo"
        )
    ]

    // MARK: Professional — Mail, Microsoft Word, Pages
    //
    // Enforces complete, capitalized sentences with terminal punctuation —
    // the opposite emphasis from casual, same do-not-paraphrase/do-not-add
    // guardrails.

    static let professionalSystemPrompt = """
    You clean up a raw speech-to-text transcript for a PROFESSIONAL document or email (Mail, Word, Pages), before it is inserted.

    Rules, in priority order:
    1. Remove filler words and verbal tics: "um", "uh", "like" (only when used as a filler, not as a real comparison word), "you know", filler "I mean".
    2. Produce complete, properly capitalized sentences. Every sentence MUST end with terminal punctuation (a period, question mark, or exclamation point) — never leave a sentence trailing off without one. Fix grammar and punctuation throughout so it reads like something a careful professional typed.
    3. Do not paraphrase. Do not rewrite for style beyond what's needed for grammar. Do not summarize. Do not add any word, fact, or opinion that was not spoken.
    4. Keep every number, date, time, price, and proper name (people, places, products, companies) exactly as transcribed — same spelling, same digits, same casing where it matters (e.g. product names).
    5. If the entire transcript is filler with no real content, return an empty string.
    6. Preserve the original language and meaning. Preserve first person vs. second person. Never answer a question that appears in the transcript — clean it up as a question, don't respond to it.

    Reply with ONLY the cleaned text. No preamble, no quotation marks around it, no explanation of what you changed.
    """

    static let professionalFewShotExamples: [FewShotExample] = [
        FewShotExample(
            messy: "um so basically the uh the deadline moved to friday",
            clean: "So basically, the deadline moved to Friday."
        ),
        FewShotExample(
            messy: "can you send me the uh the report by like 5pm today",
            clean: "Can you send me the report by 5pm today?"
        ),
        FewShotExample(
            messy: "thanks again for your time i look forward to hearing from you",
            clean: "Thanks again for your time. I look forward to hearing from you."
        ),
        FewShotExample(
            messy: "um uh so yeah um",
            clean: ""
        ),
        // Rule 6 regression case (confirmed live, 2026-08-12) — see the
        // neutral prompt's matching examples above for the real failure
        // this guards against.
        FewShotExample(
            messy: "select all of the budget items",
            clean: "Select all of the budget items."
        ),
        FewShotExample(
            messy: "can you tell me all the words that have h in them in this document",
            clean: "Can you tell me all the words that have H in them in this document?"
        )
    ]

    // MARK: Code / Terminal — Xcode, Terminal, VS Code, iTerm
    //
    // Essentially pass-through: code and shell commands are not prose, so
    // "cleaning them up" (adding capitalization, punctuation, rephrasing)
    // would actively corrupt them. Only filler-word removal survives here —
    // no punctuation enforcement, no capitalization changes, no rewriting of
    // any kind.

    static let codeOrTerminalSystemPrompt = """
    You lightly clean up a raw speech-to-text transcript that is about to be typed into a code editor or terminal (Xcode, Terminal, VS Code, or iTerm), where it is likely a variable name, file path, shell command, commit message, or code comment rather than ordinary prose.

    Rules, in priority order:
    1. Remove ONLY filler words and verbal tics: "um", "uh", filler "like", "you know", filler "I mean". Nothing else.
    2. Do NOT add capitalization, do NOT add or change punctuation, do NOT enforce sentence structure, and do NOT reformat spacing, casing, hyphens, underscores, dots or slashes — any of those could be a real identifier, path, or command that must survive character-for-character.
    3. Do not paraphrase. Do not rewrite for style. Do not summarize. Do not add any word, fact, or opinion that was not spoken.
    4. Keep every number, date, time, price, proper name, and technical term exactly as transcribed — same spelling, same digits, same casing.
    5. If the entire transcript is filler with no real content, return an empty string.
    6. Preserve the original language and meaning exactly. When in doubt, make NO change beyond filler removal — under-cleaning is always safer than over-cleaning here.

    Reply with ONLY the cleaned text. No preamble, no quotation marks around it, no explanation of what you changed.
    """

    static let codeOrTerminalFewShotExamples: [FewShotExample] = [
        FewShotExample(
            messy: "um git commit dash m uh fix the login bug",
            clean: "git commit dash m fix the login bug"
        ),
        FewShotExample(
            messy: "uh cd slash users slash mihir slash projects",
            clean: "cd slash users slash mihir slash projects"
        ),
        FewShotExample(
            messy: "like let user name equal empty string",
            clean: "let user name equal empty string"
        ),
        FewShotExample(
            messy: "um uh so yeah um",
            clean: ""
        ),
        // Rule 6 regression case (confirmed live, 2026-08-12) — see the
        // neutral prompt's matching examples above for the real failure
        // this guards against.
        FewShotExample(
            messy: "select all of the budget items",
            clean: "select all of the budget items"
        ),
        FewShotExample(
            messy: "can you list all the files that have test in the name",
            clean: "can you list all the files that have test in the name"
        )
    ]

    // MARK: Step 9 — Auto-edits ("scratch that")
    //
    // In-utterance spoken corrections, applied ON TOP of whichever tone
    // system prompt/few-shots were already selected (appended to the
    // system message, few-shots appended after the tone's own). Editing
    // text ALREADY inserted into the target app is explicitly out of
    // scope here (blueprint: "that's command-mode territory / future
    // work") — this only handles corrections spoken within the SAME
    // recorded utterance, before anything is typed.

    static let correctionHandlingAddendum = """
    CORRECTIONS: the speaker may correct themselves mid-utterance using phrases like "scratch that", "no wait", "I mean" (when it introduces an actual substitution, not just a thinking pause), or "actually make that". When this happens, keep ONLY the corrected/final version and drop the retracted material entirely — do not mention that a correction happened, do not keep both versions. This only applies to corrections spoken within this single utterance.

    Do NOT treat these as corrections when they aren't marking a real substitution: "scratch that" used literally (e.g. "don't scratch that itch") is not a correction; "I mean" used as a simple filler/thinking-pause with no actual replacement that follows is just filler (see rule 1, not this section); "actually" on its own, without "make that" or a clear substitution right after, is not necessarily a correction trigger. When in doubt about whether a correction was intended, keep the text as spoken rather than guessing.
    """

    /// 6 positive cases (blueprint task 1: "6 few-shot examples covering
    /// the four trigger phrases") + 3 negative/false-positive cases
    /// (blueprint task 2: "guard against false positives... add negative
    /// few-shots"), including the blueprint's own named case ("don't
    /// scratch that itch").
    static let correctionFewShotExamples: [FewShotExample] = [
        // Positive: "scratch that"
        FewShotExample(
            messy: "send the report monday scratch that tuesday",
            clean: "Send the report Tuesday."
        ),
        FewShotExample(
            messy: "we're launching in march scratch that april",
            clean: "We're launching in April."
        ),
        // Positive: "no wait"
        FewShotExample(
            messy: "meeting at three no wait four",
            clean: "Meeting at four."
        ),
        // Positive: "I mean" (as a real substitution, not filler)
        FewShotExample(
            messy: "can you call john i mean jake about the budget",
            clean: "Can you call Jake about the budget?"
        ),
        // Positive: "actually make that"
        FewShotExample(
            messy: "the price is 50 dollars actually make that 45",
            clean: "The price is 45 dollars."
        ),
        // Positive: a chained/nested correction
        FewShotExample(
            messy: "email sarah about it no wait actually email mike instead",
            clean: "Email Mike about it instead."
        ),
        // Negative: the blueprint's own named false-positive case
        FewShotExample(
            messy: "dont scratch that itch its driving me crazy",
            clean: "Don't scratch that itch, it's driving me crazy."
        ),
        // Negative: "I mean" as a genuine phrase, not a correction trigger
        FewShotExample(
            messy: "i mean it when i say thank you for this",
            clean: "I mean it when I say thank you for this."
        ),
        // Negative: "actually" alone, no substitution follows
        FewShotExample(
            messy: "actually i think this is a really good idea",
            clean: "Actually, I think this is a really good idea."
        )
    ]

    // MARK: - List formatting (2026-08-14, Mihir's request)
    //
    // When a dictation describes an ordered sequence of steps using
    // explicit sequential language ("first... next... then... finally"),
    // format each step on its own numbered line instead of leaving it as
    // one run-on sentence. Deliberately conservative: only fires when the
    // speaker actually used sequential marker words — ordinary dictation
    // that happens to contain "then" once (e.g. "I went to the store then
    // came home") must NOT get split into a numbered list.

    static let listFormattingAddendum = """
    STEP-BY-STEP FORMATTING: if the speaker describes an ordered sequence of steps or actions using explicit sequential marker words ("first", "second", "next", "then", "after that", "finally", "lastly"), format each distinct step as its own numbered line (1. 2. 3. ...) instead of leaving it as one run-on sentence. Drop the marker words themselves once they've been used to identify the line breaks — the numbering already conveys the sequence.

    Do NOT do this for ordinary dictation that merely contains one of these words without describing a real multi-step sequence (e.g. "I went to the store then came home" is one sentence, not a list — only one sequential word, no real enumeration of distinct steps).
    """

    /// 3 positive cases covering a range of sequential-marker phrasing + 2
    /// negative/false-positive cases (a single incidental "then", and a
    /// short two-clause sentence that isn't really an enumerated process).
    static let listFormattingFewShotExamples: [FewShotExample] = [
        FewShotExample(
            messy: "first upload the document next break it down into sections then organize it into a draft and finally give me the result",
            clean: "1. Upload the document.\n2. Break it down into sections.\n3. Organize it into a draft.\n4. Give me the result."
        ),
        FewShotExample(
            messy: "so first we need to call the client next send the updated contract and then wait for their signature",
            clean: "1. Call the client.\n2. Send the updated contract.\n3. Wait for their signature."
        ),
        FewShotExample(
            messy: "step one is to backup the database step two is to run the migration and step three is to verify the results",
            clean: "1. Backup the database.\n2. Run the migration.\n3. Verify the results."
        ),
        // Negative: a single incidental "then", not a real enumerated process.
        FewShotExample(
            messy: "i went to the store then came home",
            clean: "I went to the store, then came home."
        ),
        // Negative: short two-clause sentence, not worth listifying.
        FewShotExample(
            messy: "finish the report and then send it to sarah",
            clean: "Finish the report, and then send it to Sarah."
        )
    ]
}
