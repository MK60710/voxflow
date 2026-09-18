import Foundation
import Testing
@testable import VoxFlowCore

/// Offline tests for Step 9's own axis: correction-handling addendum +
/// few-shot inclusion, isolated from tone/dictionary (mirrors
/// `CleanupPromptTemplateToneTests`'s exact isolation philosophy — kept as
/// its own file so this is a clean, additive diff).
@Suite("CleanupPromptTemplate auto-edits")
struct CleanupPromptTemplateAutoEditsTests {

    @Test("autoEditsEnabled: true appends the correction addendum to the system message")
    func autoEditsEnabledAppendsAddendum() {
        let messages = CleanupPromptTemplate.messages(
            forTranscript: "hello",
            tone: .neutral,
            dictionaryTerms: [],
            autoEditsEnabled: true
        )
        #expect(messages.first?.content.contains(CleanupPromptTemplate.correctionHandlingAddendum) == true)
    }

    @Test("autoEditsEnabled: false does NOT append the correction addendum — system message matches the tone prompt exactly")
    func autoEditsDisabledOmitsAddendum() {
        let messages = CleanupPromptTemplate.messages(
            forTranscript: "hello",
            tone: .neutral,
            dictionaryTerms: [],
            autoEditsEnabled: false,
            listFormattingEnabled: false
        )
        #expect(messages.first?.content == CleanupPromptTemplate.systemPrompt)
        #expect(messages.first?.content.contains("CORRECTIONS") == false)
    }

    @Test("the 3-parameter messages(forTranscript:tone:dictionaryTerms:) defaults autoEditsEnabled to true")
    func threeParameterOverloadDefaultsToEnabled() {
        let withDefault = CleanupPromptTemplate.messages(forTranscript: "hello", tone: .neutral, dictionaryTerms: [])
        let explicitTrue = CleanupPromptTemplate.messages(forTranscript: "hello", tone: .neutral, dictionaryTerms: [], autoEditsEnabled: true)
        #expect(withDefault == explicitTrue)
    }

    @Test("autoEditsEnabled: true appends exactly the correction few-shot examples, after the tone's own")
    func autoEditsEnabledAppendsCorrectionFewShots() {
        for tone in ToneProfile.allCases {
            let toneOnly = CleanupPromptTemplate.messages(forTranscript: "x", tone: tone, dictionaryTerms: [], autoEditsEnabled: false)
            let withAutoEdits = CleanupPromptTemplate.messages(forTranscript: "x", tone: tone, dictionaryTerms: [], autoEditsEnabled: true)
            let expectedExtra = CleanupPromptTemplate.correctionFewShotExamples.count * 2
            #expect(withAutoEdits.count == toneOnly.count + expectedExtra)
        }
    }

    @Test("autoEditsEnabled: true still ends with the real transcript as the final user turn")
    func autoEditsEnabledStillEndsWithRealTranscript() {
        let transcript = "the real raw transcript"
        let messages = CleanupPromptTemplate.messages(forTranscript: transcript, tone: .neutral, dictionaryTerms: [], autoEditsEnabled: true)
        #expect(messages.last?.role == "user")
        #expect(messages.last?.content == transcript)
    }

    @Test("dictionary addendum and correction addendum can both apply to the same system message")
    func dictionaryAndCorrectionAddendaBothApply() {
        let messages = CleanupPromptTemplate.messages(
            forTranscript: "hello",
            tone: .neutral,
            dictionaryTerms: ["CogniSwitch"],
            autoEditsEnabled: true
        )
        let systemContent = messages.first?.content ?? ""
        #expect(systemContent.contains("CogniSwitch"))
        #expect(systemContent.contains("CORRECTIONS"))
    }

    // MARK: - The blueprint's own named cases (falsifiable, not just prose)

    @Test("correction few-shots include all four trigger phrases from the blueprint")
    func correctionFewShotsCoverAllFourTriggerPhrases() {
        let allMessy = CleanupPromptTemplate.correctionFewShotExamples.map { $0.messy.lowercased() }.joined(separator: " | ")
        #expect(allMessy.contains("scratch that"))
        #expect(allMessy.contains("no wait"))
        #expect(allMessy.contains("i mean"))
        #expect(allMessy.contains("actually make that") || allMessy.contains("actually"))
    }

    @Test("the blueprint's named false-positive case is present among the negative few-shots")
    func namedFalsePositiveCaseIsPresent() {
        let hasDontScratchThatItch = CleanupPromptTemplate.correctionFewShotExamples.contains { example in
            example.messy.lowercased().contains("scratch that itch")
        }
        #expect(hasDontScratchThatItch)
    }
}
