import Foundation
import Testing
@testable import VoxFlowCore

/// Blueprint Step 8 task 4: "DictionaryStore round-trip (save/load/add/
/// remove)". Every test here points `DictionaryStore` at a fresh throwaway
/// temp directory (never the real `~/Library/Application Support/VoxFlow/`)
/// so `swift test` never touches Mihir's real dictionary file, and each
/// test's temp directory is removed afterward.
@Suite("DictionaryStore")
struct DictionaryStoreTests {

    /// A fresh, unique temp directory per test — never shared, never the
    /// real Application Support path.
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voxflow-dictionary-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("a fresh store with no file on disk starts empty — the privacy seed rule")
    func freshStoreStartsEmpty() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DictionaryStore(directoryURL: directory)
        #expect(store.entries.isEmpty)
    }

    @Test("add appends an entry and persists it to disk immediately")
    func addPersistsToDisk() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DictionaryStore(directoryURL: directory)
        let entry = try store.add(term: "CogniSwitch", soundsLike: "cog-nih-switch")

        #expect(entry?.term == "CogniSwitch")
        #expect(entry?.soundsLike == "cog-nih-switch")
        #expect(store.entries.count == 1)

        let fileURL = directory.appendingPathComponent("dictionary.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("a second store instance pointed at the same directory reloads exactly what was saved — the real round-trip proof")
    func reloadingFromDiskRoundTrips() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try DictionaryStore(directoryURL: directory)
        try first.add(term: "ContextOps")
        try first.add(term: "UMass", soundsLike: "you mass")

        let second = try DictionaryStore(directoryURL: directory)
        #expect(second.entries.count == 2)
        #expect(second.entries[0].term == "ContextOps")
        #expect(second.entries[0].soundsLike == nil)
        #expect(second.entries[1].term == "UMass")
        #expect(second.entries[1].soundsLike == "you mass")
    }

    @Test("remove deletes only the matching entry and persists the removal")
    func removeDeletesMatchingEntryAndPersists() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DictionaryStore(directoryURL: directory)
        let first = try #require(try store.add(term: "CogniSwitch"))
        try store.add(term: "Parakeet")
        #expect(store.entries.count == 2)

        try store.remove(id: first.id)
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.term == "Parakeet")

        // Persistence check: a fresh instance sees the removal too.
        let reloaded = try DictionaryStore(directoryURL: directory)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries.first?.term == "Parakeet")
    }

    @Test("removing an id that doesn't exist is a harmless no-op")
    func removeUnknownIdIsNoOp() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DictionaryStore(directoryURL: directory)
        try store.add(term: "CogniSwitch")
        try store.remove(id: UUID())
        #expect(store.entries.count == 1)
    }

    @Test("update changes term and soundsLike in place and persists")
    func updateChangesInPlaceAndPersists() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DictionaryStore(directoryURL: directory)
        let entry = try #require(try store.add(term: "Congniswitch"))

        try store.update(id: entry.id, term: "CogniSwitch", soundsLike: "cog-nih-switch")
        #expect(store.entries.first?.term == "CogniSwitch")
        #expect(store.entries.first?.soundsLike == "cog-nih-switch")

        let reloaded = try DictionaryStore(directoryURL: directory)
        #expect(reloaded.entries.first?.term == "CogniSwitch")
    }

    @Test("add rejects an empty/whitespace-only term as a no-op")
    func addRejectsEmptyTerm() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DictionaryStore(directoryURL: directory)
        let result = try store.add(term: "   ")
        #expect(result == nil)
        #expect(store.entries.isEmpty)
    }

    @Test("terms and sounds-like hints are trimmed of surrounding whitespace")
    func addTrimsWhitespace() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DictionaryStore(directoryURL: directory)
        let entry = try store.add(term: "  CogniSwitch  ", soundsLike: "  cog-nih-switch  ")
        #expect(entry?.term == "CogniSwitch")
        #expect(entry?.soundsLike == "cog-nih-switch")
    }

    @Test("an empty-string soundsLike is stored as nil, not an empty string")
    func emptySoundsLikeStoredAsNil() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DictionaryStore(directoryURL: directory)
        let entry = try store.add(term: "Parakeet", soundsLike: "")
        #expect(entry?.soundsLike == nil)
    }

    @Test("entries preserve insertion (oldest-first) order across add and reload")
    func entriesPreserveInsertionOrder() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DictionaryStore(directoryURL: directory)
        try store.add(term: "First")
        try store.add(term: "Second")
        try store.add(term: "Third")

        #expect(store.entries.map(\.term) == ["First", "Second", "Third"])

        let reloaded = try DictionaryStore(directoryURL: directory)
        #expect(reloaded.entries.map(\.term) == ["First", "Second", "Third"])
    }
}
