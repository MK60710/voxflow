import Foundation
import Testing
@testable import VoxFlowCore

/// Offline tests for the list-formatting axis (2026-08-14, Mihir's
/// request), isolated from tone/dictionary/auto-edits — mirrors
/// `CleanupPromptTemplateAutoEditsTests`'s exact isolation philosophy.
@Suite("CleanupPromptTemplate list formatting")
struct CleanupPromptTemplateListFormattingTests {

    @Test("listFormattingEnabled: true appends the list-formatting addendum to the system message, for a non-code tone")
    func listFormattingEnabledAppendsAddendum() {
        let messages = CleanupPromptTemplate.messages(
            forTranscript: "hello",
            tone: .neutral,
            dictionaryTerms: [],
            autoEditsEnabled: false,
            listFormattingEnabled: true
        )
        #expect(messages.first?.content.contains(CleanupPromptTemplate.listFormattingAddendum) == true)
    }

    @Test("listFormattingEnabled: false does NOT append the list-formatting addendum")
    func listFormattingDisabledOmitsAddendum() {
        let messages = CleanupPromptTemplate.messages(
            forTranscript: "hello",
            tone: .neutral,
            dictionaryTerms: [],
            autoEditsEnabled: false,
            listFormattingEnabled: false
        )
        #expect(messages.first?.content == CleanupPromptTemplate.systemPrompt)
        #expect(messages.first?.content.contains("STEP-BY-STEP") == false)
    }

    @Test("the 4-parameter messages(forTranscript:tone:dictionaryTerms:autoEditsEnabled:) defaults listFormattingEnabled to true")
    func fourParameterOverloadDefaultsToEnabled() {
        let withDefault = CleanupPromptTemplate.messages(forTranscript: "hello", tone: .neutral, dictionaryTerms: [], autoEditsEnabled: false)
        let explicitTrue = CleanupPromptTemplate.messages(forTranscript: "hello", tone: .neutral, dictionaryTerms: [], autoEditsEnabled: false, listFormattingEnabled: true)
        #expect(withDefault == explicitTrue)
    }

    @Test("listFormattingEnabled: true appends exactly the list-formatting few-shot examples, after the tone's own, for every tone EXCEPT .codeOrTerminal")
    func listFormattingEnabledAppendsFewShots() {
        for tone in ToneProfile.allCases where tone != .codeOrTerminal {
            let toneOnly = CleanupPromptTemplate.messages(forTranscript: "x", tone: tone, dictionaryTerms: [], autoEditsEnabled: false, listFormattingEnabled: false)
            let withListFormatting = CleanupPromptTemplate.messages(forTranscript: "x", tone: tone, dictionaryTerms: [], autoEditsEnabled: false, listFormattingEnabled: true)
            let expectedExtra = CleanupPromptTemplate.listFormattingFewShotExamples.count * 2
            #expect(withListFormatting.count == toneOnly.count + expectedExtra)
        }
    }

    @Test("listFormattingEnabled: true still ends with the real transcript as the final user turn")
    func listFormattingEnabledStillEndsWithRealTranscript() {
        let transcript = "the real raw transcript"
        let messages = CleanupPromptTemplate.messages(forTranscript: transcript, tone: .neutral, dictionaryTerms: [], autoEditsEnabled: false, listFormattingEnabled: true)
        #expect(messages.last?.role == "user")
        #expect(messages.last?.content == transcript)
    }

    @Test("dictionary, correction, and list-formatting addenda can all apply to the same system message")
    func allThreeAddendaCanApply() {
        let messages = CleanupPromptTemplate.messages(
            forTranscript: "hello",
            tone: .neutral,
            dictionaryTerms: ["CogniSwitch"],
            autoEditsEnabled: true,
            listFormattingEnabled: true
        )
        let systemContent = messages.first?.content ?? ""
        #expect(systemContent.contains("CogniSwitch"))
        #expect(systemContent.contains("CORRECTIONS"))
        #expect(systemContent.contains("STEP-BY-STEP"))
    }

    // MARK: - List formatting NEVER applies to .codeOrTerminal tone.
    // Briefly removed 2026-08-14 at Mihir's request, then reverted same day
    // after a live Terminal test produced no visible output — see the doc
    // comment on `messages(forTranscript:tone:dictionaryTerms:autoEditsEnabled:listFormattingEnabled:)`.

    @Test("listFormattingEnabled: true never applies for .codeOrTerminal tone — the addendum does not appear")
    func listFormattingFewShotsNeverAppliedForCodeOrTerminalTone() {
        let messages = CleanupPromptTemplate.messages(
            forTranscript: "first check the file then delete it",
            tone: .codeOrTerminal,
            dictionaryTerms: [],
            autoEditsEnabled: false,
            listFormattingEnabled: true
        )
        #expect(messages.first?.content.contains("STEP-BY-STEP") == false)
    }

    @Test("listFormattingEnabled: false still omits the addendum for .codeOrTerminal tone, same as every other tone")
    func listFormattingDisabledOmitsForCodeOrTerminalToneToo() {
        let messages = CleanupPromptTemplate.messages(
            forTranscript: "first check the file then delete it",
            tone: .codeOrTerminal,
            dictionaryTerms: [],
            autoEditsEnabled: false,
            listFormattingEnabled: false
        )
        #expect(messages.first?.content == CleanupPromptTemplate.systemPrompt(for: .codeOrTerminal))
        #expect(messages.first?.content.contains("STEP-BY-STEP") == false)
    }

    // MARK: - Few-shot content spot checks — the real examples must
    // actually demonstrate the numbered-list behavior, and the negative
    // cases must survive as ordinary prose.

    @Test("the positive few-shot examples produce real multi-line numbered output")
    func positiveFewShotsProduceNumberedLines() {
        for example in CleanupPromptTemplate.listFormattingFewShotExamples where example.clean.hasPrefix("1.") {
            #expect(example.clean.contains("\n2."))
        }
    }

    @Test("the negative few-shot examples stay as one-line prose, not a list")
    func negativeFewShotsStayAsProse() {
        let negativeExamples = CleanupPromptTemplate.listFormattingFewShotExamples.filter { !$0.clean.hasPrefix("1.") }
        #expect(!negativeExamples.isEmpty)
        for example in negativeExamples {
            #expect(!example.clean.contains("\n"))
        }
    }
}
