import Testing
@testable import VoxFlowCore

@Suite("CommandRecognizer")
struct CommandRecognizerTests {

    // MARK: - Exact matches, every command

    @Test("exact phrase matches for every command")
    func exactPhrasesMatch() {
        #expect(CommandRecognizer.recognize("new line") == .newLine)
        #expect(CommandRecognizer.recognize("new paragraph") == .newParagraph)
        #expect(CommandRecognizer.recognize("undo that") == .undo)
        #expect(CommandRecognizer.recognize("select all") == .selectAll)
    }

    @Test("recognition is case-insensitive")
    func caseInsensitive() {
        #expect(CommandRecognizer.recognize("UNDO THAT") == .undo)
        #expect(CommandRecognizer.recognize("Select All") == .selectAll)
    }

    @Test("trailing punctuation from STT is stripped before matching")
    func trailingPunctuationStripped() {
        #expect(CommandRecognizer.recognize("undo that.") == .undo)
        #expect(CommandRecognizer.recognize("new line!") == .newLine)
        #expect(CommandRecognizer.recognize("select all?") == .selectAll)
    }

    @Test("extra whitespace is collapsed before matching")
    func extraWhitespaceCollapsed() {
        #expect(CommandRecognizer.recognize("  undo   that  ") == .undo)
        #expect(CommandRecognizer.recognize("new    paragraph") == .newParagraph)
    }

    // MARK: - Near-misses that must NOT match (blueprint task 5's own example)

    @Test("a command phrase embedded mid-sentence does NOT match — types as text")
    func embeddedCommandPhraseDoesNotMatch() {
        #expect(CommandRecognizer.recognize("undo that thing I said") == nil)
        #expect(CommandRecognizer.recognize("select all of the budget items") == nil)
        #expect(CommandRecognizer.recognize("can you start a new line here") == nil)
        #expect(CommandRecognizer.recognize("let's start a new paragraph about pricing") == nil)
    }

    @Test("a near-miss single-word variant does NOT match")
    func nearMissSingleWordDoesNotMatch() {
        #expect(CommandRecognizer.recognize("undo") == nil)
        #expect(CommandRecognizer.recognize("select") == nil)
        #expect(CommandRecognizer.recognize("new") == nil)
    }

    @Test("ordinary dictation that happens to share a word does NOT match")
    func ordinaryDictationDoesNotMatch() {
        #expect(CommandRecognizer.recognize("the new design looks great") == nil)
        #expect(CommandRecognizer.recognize("please select the best option") == nil)
    }

    @Test("empty or whitespace-only transcript does NOT match")
    func emptyTranscriptDoesNotMatch() {
        #expect(CommandRecognizer.recognize("") == nil)
        #expect(CommandRecognizer.recognize("   ") == nil)
    }

    // MARK: - Every command has a distinct phrase and display name

    @Test("every command has a unique phrase")
    func everyCommandHasUniquePhrase() {
        let phrases = VoiceCommand.allCases.map { $0.phrase }
        #expect(Set(phrases).count == VoiceCommand.allCases.count)
    }

    @Test("every command's own phrase round-trips through recognize")
    func everyCommandPhraseRoundTrips() {
        for command in VoiceCommand.allCases {
            #expect(CommandRecognizer.recognize(command.phrase) == command)
        }
    }
}
