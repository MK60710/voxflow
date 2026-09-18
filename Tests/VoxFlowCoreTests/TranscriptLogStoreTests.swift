import Foundation
import Testing
@testable import VoxFlowCore

/// Mirrors `DictionaryStoreTests`' exact shape: every test points
/// `TranscriptLogStore` at a fresh throwaway temp directory (never the real
/// `~/Library/Application Support/VoxFlow/`) so `swift test` never touches
/// Mihir's real transcript log file.
@Suite("TranscriptLogStore")
struct TranscriptLogStoreTests {

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voxflow-transcriptlog-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("a fresh store with no file on disk starts empty")
    func freshStoreStartsEmpty() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TranscriptLogStore(directoryURL: directory)
        #expect(store.entries.isEmpty)
    }

    @Test("append inserts at the front (newest-first) and persists to disk immediately")
    func appendInsertsNewestFirstAndPersists() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TranscriptLogStore(directoryURL: directory)
        try store.append("First dictation")
        try store.append("Second dictation")

        #expect(store.entries.count == 2)
        #expect(store.entries[0].text == "Second dictation")
        #expect(store.entries[1].text == "First dictation")

        let fileURL = directory.appendingPathComponent("transcript-log.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("a second store instance pointed at the same directory reloads exactly what was saved — the real permanence proof, matching Mihir's explicit request")
    func reloadingFromDiskRoundTrips() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try TranscriptLogStore(directoryURL: directory)
        try first.append("Hello world")
        try first.append("Second thing I said")

        let second = try TranscriptLogStore(directoryURL: directory)
        #expect(second.entries.count == 2)
        #expect(second.entries[0].text == "Second thing I said")
        #expect(second.entries[1].text == "Hello world")
    }

    @Test("append rejects empty text as a no-op")
    func appendRejectsEmptyText() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TranscriptLogStore(directoryURL: directory)
        try store.append("")
        #expect(store.entries.isEmpty)
    }

    @Test("clear removes every entry and persists the removal")
    func clearRemovesEverythingAndPersists() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TranscriptLogStore(directoryURL: directory)
        try store.append("Something")
        try store.clear()
        #expect(store.entries.isEmpty)

        let reloaded = try TranscriptLogStore(directoryURL: directory)
        #expect(reloaded.entries.isEmpty)
    }

    @Test("appending past maxEntries drops the oldest entry, keeps the newest")
    func appendingPastCapDropsOldest() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TranscriptLogStore(directoryURL: directory)
        for index in 1...(TranscriptLogStore.maxEntries + 5) {
            try store.append("Entry \(index)")
        }

        #expect(store.entries.count == TranscriptLogStore.maxEntries)
        // Newest-first: the very last appended entry is at index 0, and the
        // oldest 5 (Entry 1 through Entry 5) should have been dropped.
        #expect(store.entries.first?.text == "Entry \(TranscriptLogStore.maxEntries + 5)")
        #expect(!store.entries.contains { $0.text == "Entry 1" })
        #expect(!store.entries.contains { $0.text == "Entry 5" })
        #expect(store.entries.contains { $0.text == "Entry 6" })
    }
}
