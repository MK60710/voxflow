import Foundation
import Testing
@testable import VoxFlowCore

@Suite("SnippetStore")
struct SnippetStoreTests {

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voxflow-snippet-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("a fresh store with no file on disk starts empty — the privacy seed rule")
    func freshStoreStartsEmpty() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SnippetStore(directoryURL: directory)
        #expect(store.entries.isEmpty)
    }

    @Test("add appends an entry and persists it to disk immediately")
    func addPersistsToDisk() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SnippetStore(directoryURL: directory)
        let entry = try store.add(trigger: "my LinkedIn", expansion: "https://www.linkedin.com/in/mihir/")

        #expect(entry?.trigger == "my LinkedIn")
        #expect(entry?.expansion == "https://www.linkedin.com/in/mihir/")
        #expect(store.entries.count == 1)

        let fileURL = directory.appendingPathComponent("snippets.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("a second store instance pointed at the same directory reloads exactly what was saved")
    func reloadingFromDiskRoundTrips() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try SnippetStore(directoryURL: directory)
        try first.add(trigger: "my email", expansion: "mihir@example.com")
        try first.add(trigger: "intro email", expansion: "Hey, would love to find time to chat.")

        let second = try SnippetStore(directoryURL: directory)
        #expect(second.entries.count == 2)
        #expect(second.entries[0].trigger == "my email")
        #expect(second.entries[1].trigger == "intro email")
    }

    @Test("remove deletes only the matching entry and persists the removal")
    func removeDeletesMatchingEntryAndPersists() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SnippetStore(directoryURL: directory)
        let first = try #require(try store.add(trigger: "my LinkedIn", expansion: "https://linkedin.com/x"))
        try store.add(trigger: "my email", expansion: "x@example.com")

        try store.remove(id: first.id)
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.trigger == "my email")
    }

    @Test("update changes trigger and expansion in place and persists")
    func updateChangesInPlaceAndPersists() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SnippetStore(directoryURL: directory)
        let entry = try #require(try store.add(trigger: "old trigger", expansion: "old text"))

        try store.update(id: entry.id, trigger: "new trigger", expansion: "new text")
        #expect(store.entries.first?.trigger == "new trigger")
        #expect(store.entries.first?.expansion == "new text")
    }

    @Test("add rejects an empty trigger as a no-op")
    func addRejectsEmptyTrigger() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SnippetStore(directoryURL: directory)
        let result = try store.add(trigger: "   ", expansion: "some text")
        #expect(result == nil)
        #expect(store.entries.isEmpty)
    }

    @Test("add rejects an empty expansion as a no-op")
    func addRejectsEmptyExpansion() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SnippetStore(directoryURL: directory)
        let result = try store.add(trigger: "my LinkedIn", expansion: "   ")
        #expect(result == nil)
        #expect(store.entries.isEmpty)
    }

    @Test("expansion internal content is preserved exactly, only surrounding whitespace trimmed")
    func expansionInternalContentPreserved() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SnippetStore(directoryURL: directory)
        let entry = try store.add(trigger: "  my prompt  ", expansion: "  Line one.\n\nLine two.  ")
        #expect(entry?.trigger == "my prompt")
        #expect(entry?.expansion == "Line one.\n\nLine two.")
    }
}
