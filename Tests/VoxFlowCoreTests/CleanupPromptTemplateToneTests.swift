import Foundation
import Testing
@testable import VoxFlowCore

/// Offline tests for Step 7 task 4's other half: "prompt-variant selection
/// logic". Kept as a SEPARATE test file from `CleanupPromptTemplateTests`
/// (Step 6's, untouched) rather than editing it — mirrors the production
/// file's own additive-section approach, so this is a clean, isolated diff
/// for whichever of Step 7/Step 8 merges second to reconcile against.
@Suite("CleanupPromptTemplate tone variants")
struct CleanupPromptTemplateToneTests {

    // MARK: - .neutral is byte-identical to the original Step 6 prompt

    @Test(".neutral's systemPrompt(for:) returns the exact original systemPrompt, unchanged")
    func neutralSystemPromptMatchesOriginal() {
        #expect(CleanupPromptTemplate.systemPrompt(for: .neutral) == CleanupPromptTemplate.systemPrompt)
    }

    @Test(".neutral's fewShotExamples(for:) returns the exact original fewShotExamples, unchanged")
    func neutralFewShotExamplesMatchOriginal() {
        #expect(CleanupPromptTemplate.fewShotExamples(for: .neutral) == CleanupPromptTemplate.fewShotExamples)
    }

    @Test("messages(forTranscript:tone: .neutral) is identical to the original messages(forTranscript:)")
    func neutralMessagesMatchOriginalMessages() {
        let transcript = "um so basically the uh the deadline moved to friday"
        // `original` is Step 6's untouched, non-reconciled function — never
        // includes the Step 9 correction addendum or the list-formatting
        // addendum. `toned` must be pinned to both `false` to stay
        // comparable; this test is about tone selection, isolated from
        // those separate axes (covered by their own tests elsewhere).
        let original = CleanupPromptTemplate.messages(forTranscript: transcript)
        let toned = CleanupPromptTemplate.messages(forTranscript: transcript, tone: .neutral, dictionaryTerms: [], autoEditsEnabled: false, listFormattingEnabled: false)
        #expect(original == toned)
    }

    // MARK: - Each tone selects its own distinct prompt

    @Test("each tone profile selects a distinct, non-empty system prompt")
    func eachToneSelectsADistinctSystemPrompt() {
        var seen = Set<String>()
        for tone in ToneProfile.allCases {
            let prompt = CleanupPromptTemplate.systemPrompt(for: tone)
            #expect(!prompt.isEmpty)
            #expect(!seen.contains(prompt), "tone \(tone) produced a prompt identical to an earlier tone's")
            seen.insert(prompt)
        }
    }

    @Test("each tone profile has at least one few-shot example, and none are empty")
    func eachToneHasFewShotExamples() {
        for tone in ToneProfile.allCases {
            let examples = CleanupPromptTemplate.fewShotExamples(for: tone)
            #expect(!examples.isEmpty)
            for example in examples {
                #expect(!example.messy.isEmpty)
            }
        }
    }

    // MARK: - The falsifiable behavioral differences the blueprint's own
    // verification criteria name explicitly (task 2): casual allows
    // contractions and drops the trailing-period rule; professional enforces
    // complete capitalized sentences with terminal punctuation; code/terminal
    // is minimal-touch.

    @Test("casual prompt explicitly allows contractions and does not require a trailing period")
    func casualPromptAllowsContractionsAndSkipsTrailingPeriod() {
        let prompt = CleanupPromptTemplate.casualSystemPrompt.lowercased()
        #expect(prompt.contains("contraction"))
        #expect(prompt.contains("not force a trailing period") || prompt.contains("skip"))
    }

    @Test("professional prompt enforces terminal punctuation on every sentence")
    func professionalPromptEnforcesTerminalPunctuation() {
        let prompt = CleanupPromptTemplate.professionalSystemPrompt.lowercased()
        #expect(prompt.contains("terminal punctuation"))
        #expect(prompt.contains("must end"))
    }

    @Test("code/terminal prompt is explicitly minimal-touch: no punctuation/capitalization enforcement")
    func codeOrTerminalPromptIsMinimalTouch() {
        let prompt = CleanupPromptTemplate.codeOrTerminalSystemPrompt.lowercased()
        #expect(prompt.contains("do not add capitalization") || prompt.contains("not add capitalization"))
        #expect(prompt.contains("do not add or change punctuation") || prompt.contains("not add or change punctuation"))
        #expect(prompt.contains("filler"))
    }

    @Test("all four prompts keep the shared do-not-paraphrase / do-not-add guardrail")
    func allPromptsKeepDoNotParaphraseGuardrail() {
        for tone in ToneProfile.allCases {
            let prompt = CleanupPromptTemplate.systemPrompt(for: tone).lowercased()
            #expect(prompt.contains("do not paraphrase"))
            #expect(prompt.contains("do not add"))
        }
    }

    // MARK: - messages(forTranscript:tone:) assembly, per tone

    @Test("messages(forTranscript:tone:) starts with exactly one system message matching that tone's prompt")
    func toneMessagesStartWithMatchingSystemPrompt() {
        for tone in ToneProfile.allCases {
            // autoEditsEnabled/listFormattingEnabled: false — isolates tone
            // selection from either addendum, which would otherwise append
            // to the system message and break this exact-match assertion.
            let messages = CleanupPromptTemplate.messages(forTranscript: "hello", tone: tone, dictionaryTerms: [], autoEditsEnabled: false, listFormattingEnabled: false)
            #expect(messages.first?.role == "system")
            #expect(messages.first?.content == CleanupPromptTemplate.systemPrompt(for: tone))
            #expect(messages.filter { $0.role == "system" }.count == 1)
        }
    }

    @Test("messages(forTranscript:tone:) ends with the real transcript as the final user turn, for every tone")
    func toneMessagesEndWithRealTranscript() {
        let transcript = "the real raw transcript for this tone"
        for tone in ToneProfile.allCases {
            let messages = CleanupPromptTemplate.messages(forTranscript: transcript, tone: tone)
            #expect(messages.last?.role == "user")
            #expect(messages.last?.content == transcript)
        }
    }

    @Test("messages(forTranscript:tone:) includes exactly that tone's few-shot examples as alternating turns")
    func toneMessagesIncludeThatTonesFewShots() {
        for tone in ToneProfile.allCases {
            // autoEditsEnabled/listFormattingEnabled: false — otherwise
            // either's own few-shots would also be appended, breaking the
            // exact count.
            let messages = CleanupPromptTemplate.messages(forTranscript: "the transcript", tone: tone, dictionaryTerms: [], autoEditsEnabled: false, listFormattingEnabled: false)
            let examples = CleanupPromptTemplate.fewShotExamples(for: tone)
            #expect(messages.count == 1 + examples.count * 2 + 1)
            for (index, example) in examples.enumerated() {
                let userMessage = messages[1 + index * 2]
                let assistantMessage = messages[2 + index * 2]
                #expect(userMessage.content == example.messy)
                #expect(assistantMessage.content == example.clean)
            }
        }
    }
}
