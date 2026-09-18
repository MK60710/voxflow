import Testing
@testable import VoxFlowCore

@Suite("SnippetRecognizer")
struct SnippetRecognizerTests {

    private let snippets: [SnippetEntry] = [
        SnippetEntry(trigger: "my LinkedIn", expansion: "https://www.linkedin.com/in/mihir/"),
        SnippetEntry(trigger: "intro email", expansion: "Hey, would love to find time to chat.")
    ]

    @Test("an exact trigger match returns its expansion")
    func exactMatchReturnsExpansion() {
        #expect(SnippetRecognizer.recognize("my LinkedIn", snippets: snippets) == "https://www.linkedin.com/in/mihir/")
    }

    @Test("matching is case-insensitive and punctuation/whitespace-normalized, same as CommandRecognizer")
    func matchingIsNormalized() {
        #expect(SnippetRecognizer.recognize("MY LINKEDIN.", snippets: snippets) == "https://www.linkedin.com/in/mihir/")
        #expect(SnippetRecognizer.recognize("  my   linkedin  ", snippets: snippets) == "https://www.linkedin.com/in/mihir/")
    }

    @Test("a trigger phrase embedded mid-sentence does NOT match — types as text, same safety design as commands")
    func embeddedTriggerDoesNotMatch() {
        #expect(SnippetRecognizer.recognize("check out my LinkedIn profile", snippets: snippets) == nil)
        #expect(SnippetRecognizer.recognize("can you send me an intro email later", snippets: snippets) == nil)
    }

    @Test("no match returns nil, not an empty string")
    func noMatchReturnsNil() {
        #expect(SnippetRecognizer.recognize("something completely unrelated", snippets: snippets) == nil)
    }

    @Test("an empty snippet list never matches anything")
    func emptySnippetListNeverMatches() {
        #expect(SnippetRecognizer.recognize("my LinkedIn", snippets: []) == nil)
    }

    @Test("empty transcript does not match")
    func emptyTranscriptDoesNotMatch() {
        #expect(SnippetRecognizer.recognize("", snippets: snippets) == nil)
    }

    @Test("the first matching snippet wins if triggers were somehow duplicated")
    func firstMatchWinsOnDuplicateTriggers() {
        let duplicated = [
            SnippetEntry(trigger: "my email", expansion: "first@example.com"),
            SnippetEntry(trigger: "my email", expansion: "second@example.com")
        ]
        #expect(SnippetRecognizer.recognize("my email", snippets: duplicated) == "first@example.com")
    }
}
