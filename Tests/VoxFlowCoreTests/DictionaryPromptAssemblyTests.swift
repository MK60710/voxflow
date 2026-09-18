import Foundation
import Testing
@testable import VoxFlowCore

/// Blueprint Step 8 task 4: "prompt assembly respects length caps" — covers
/// both bias points named in the blueprint: the STT `biasPrompt` string
/// (Whisper prompt-length cap, "truncate oldest-first") and the cleanup
/// "these terms are spelled exactly: …" addendum. Also covers
/// `CleanupPromptTemplate`'s new dictionary-aware `messages` overload
/// (Step 8's addition to that file), since it's the direct consumer of the
/// cleanup addendum. Entirely pure/offline — no networking anywhere.
@Suite("DictionaryPromptAssembly")
struct DictionaryPromptAssemblyTests {

    // MARK: - sttBiasPrompt

    @Test("an empty entry list produces nil — S5a's original always-nil behavior is preserved")
    func emptyEntriesProducesNilSTTPrompt() {
        #expect(DictionaryPromptAssembly.sttBiasPrompt(forEntries: []) == nil)
    }

    @Test("a small dictionary renders every term, well under the cap")
    func smallDictionaryRendersEveryTerm() throws {
        let entries = [
            DictionaryEntry(term: "CogniSwitch"),
            DictionaryEntry(term: "ContextOps"),
            DictionaryEntry(term: "UMass"),
            DictionaryEntry(term: "Parakeet")
        ]
        let prompt = try #require(DictionaryPromptAssembly.sttBiasPrompt(forEntries: entries))
        #expect(prompt.contains("CogniSwitch"))
        #expect(prompt.contains("ContextOps"))
        #expect(prompt.contains("UMass"))
        #expect(prompt.contains("Parakeet"))
        #expect(prompt.count <= DictionaryPromptAssembly.sttBiasPromptMaxCharacters)
    }

    @Test("a soundsLike hint is rendered alongside its term")
    func soundsLikeHintIsRendered() throws {
        let entries = [DictionaryEntry(term: "CogniSwitch", soundsLike: "cog-nih-switch")]
        let prompt = try #require(DictionaryPromptAssembly.sttBiasPrompt(forEntries: entries))
        #expect(prompt.contains("CogniSwitch"))
        #expect(prompt.contains("cog-nih-switch"))
    }

    @Test("a dictionary that would exceed the character cap is truncated OLDEST-FIRST, keeping the newest terms")
    func oversizedDictionaryTruncatesOldestFirst() throws {
        // Each term padded so a handful of them reliably blows past a small
        // test cap, without depending on the real (larger) production cap.
        let entries = (1...20).map { DictionaryEntry(term: "Term-\($0)-abcdefghijklmnopqrstuvwxyz") }
        let maxCharacters = 150

        let prompt = try #require(DictionaryPromptAssembly.sttBiasPrompt(forEntries: entries, maxCharacters: maxCharacters))

        #expect(prompt.count <= maxCharacters)
        // The newest entry must survive; the oldest must not.
        #expect(prompt.contains("Term-20-"))
        #expect(!prompt.contains("Term-1-abc"))
    }

    @Test("even a single oversized entry is hard-truncated to fit the cap, never exceeding it")
    func singleOversizedEntryIsHardTruncated() throws {
        let entries = [DictionaryEntry(term: String(repeating: "x", count: 1000))]
        let maxCharacters = 50

        let prompt = try #require(DictionaryPromptAssembly.sttBiasPrompt(forEntries: entries, maxCharacters: maxCharacters))
        #expect(prompt.count == maxCharacters)
    }

    @Test("removing dictionary entries changes the assembled prompt (proves the bias is actually keyed off current entries)")
    func removingEntriesChangesPrompt() {
        let withTerm = DictionaryPromptAssembly.sttBiasPrompt(forEntries: [DictionaryEntry(term: "CogniSwitch")])
        let withoutTerm = DictionaryPromptAssembly.sttBiasPrompt(forEntries: [])
        #expect(withTerm != withoutTerm)
        #expect(withoutTerm == nil)
    }

    // MARK: - cleanupSpellingAddendum

    @Test("an empty term list produces nil")
    func emptyTermsProducesNilCleanupAddendum() {
        #expect(DictionaryPromptAssembly.cleanupSpellingAddendum(forTerms: []) == nil)
    }

    @Test("the cleanup addendum uses the blueprint's literal wording and lists every term")
    func cleanupAddendumUsesLiteralWording() throws {
        let addendum = try #require(DictionaryPromptAssembly.cleanupSpellingAddendum(forTerms: ["CogniSwitch", "ContextOps"]))
        #expect(addendum.hasPrefix("These terms are spelled exactly:"))
        #expect(addendum.contains("CogniSwitch"))
        #expect(addendum.contains("ContextOps"))
    }

    @Test("an oversized term list is truncated oldest-first for the cleanup addendum too")
    func cleanupAddendumTruncatesOldestFirst() throws {
        let terms = (1...50).map { "Term-\($0)-abcdefghijklmnopqrstuvwxyz0123456789" }
        let maxCharacters = 200

        let addendum = try #require(DictionaryPromptAssembly.cleanupSpellingAddendum(forTerms: terms, maxCharacters: maxCharacters))
        #expect(addendum.count <= maxCharacters)
        #expect(addendum.contains("Term-50-"))
        #expect(!addendum.contains("Term-1-abc"))
    }

    // MARK: - CleanupPromptTemplate's Step 8 dictionary-aware overload

    @Test("dictionaryTerms empty falls back to the exact plain messages(forTranscript:) output")
    func emptyDictionaryTermsFallsBackToPlainMessages() {
        // `plain` is Step 6's untouched function — never includes the Step
        // 9 or list-formatting addenda. `withEmptyDictionary` is pinned to
        // both `false` to stay comparable; this test is about
        // dictionary-term handling, isolated from those other axes.
        let plain = CleanupPromptTemplate.messages(forTranscript: "um so the deadline moved")
        let withEmptyDictionary = CleanupPromptTemplate.messages(forTranscript: "um so the deadline moved", tone: .neutral, dictionaryTerms: [], autoEditsEnabled: false, listFormattingEnabled: false)
        #expect(plain == withEmptyDictionary)
    }

    @Test("non-empty dictionaryTerms adds the spelling addendum to the system message only, leaving the transcript untouched")
    func dictionaryTermsAddSpellingAddendumToSystemMessageOnly() {
        let messages = CleanupPromptTemplate.messages(
            forTranscript: "so i met with the cogniswitch team",
            dictionaryTerms: ["CogniSwitch", "ContextOps"]
        )
        #expect(messages.first?.role == "system")
        #expect(messages.first?.content.contains(CleanupPromptTemplate.systemPrompt) == true)
        #expect(messages.first?.content.contains("CogniSwitch") == true)
        #expect(messages.first?.content.contains("ContextOps") == true)
        #expect(messages.last?.role == "user")
        #expect(messages.last?.content == "so i met with the cogniswitch team")
    }

    @Test("the dictionary-aware overload still includes every few-shot example, same as the plain overload")
    func dictionaryAwareOverloadStillIncludesFewShots() {
        // autoEditsEnabled/listFormattingEnabled: false — isolates
        // dictionary-term handling from either addendum, which would
        // otherwise add its own few-shots and break this exact count.
        let messages = CleanupPromptTemplate.messages(forTranscript: "hello", tone: .neutral, dictionaryTerms: ["CogniSwitch"], autoEditsEnabled: false, listFormattingEnabled: false)
        let examples = CleanupPromptTemplate.fewShotExamples
        #expect(messages.count == 1 + examples.count * 2 + 1)
    }
}
