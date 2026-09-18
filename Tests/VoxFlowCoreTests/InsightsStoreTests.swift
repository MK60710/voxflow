import Foundation
import Testing
@testable import VoxFlowCore

@Suite("InsightsStore")
struct InsightsStoreTests {

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voxflow-insights-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("a fresh store with no file on disk starts empty")
    func freshStoreStartsEmpty() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try InsightsStore(directoryURL: directory)
        #expect(store.entries.isEmpty)
    }

    @Test("append inserts at the front (newest-first) and persists to disk immediately")
    func appendInsertsNewestFirstAndPersists() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try InsightsStore(directoryURL: directory)
        try store.append(wordCount: 10, audioDurationSeconds: 5, bundleIdentifier: "com.apple.Terminal", wasCleanedUp: true)
        try store.append(wordCount: 20, audioDurationSeconds: 8, bundleIdentifier: "com.apple.mail", wasCleanedUp: false)

        #expect(store.entries.count == 2)
        #expect(store.entries[0].wordCount == 20)
        #expect(store.entries[1].wordCount == 10)

        let fileURL = directory.appendingPathComponent("insights.json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("a second store instance pointed at the same directory reloads exactly what was saved")
    func reloadingFromDiskRoundTrips() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try InsightsStore(directoryURL: directory)
        try first.append(wordCount: 15, audioDurationSeconds: 6, bundleIdentifier: "com.apple.Terminal", wasCleanedUp: true)

        let second = try InsightsStore(directoryURL: directory)
        #expect(second.entries.count == 1)
        #expect(second.entries.first?.wordCount == 15)
        #expect(second.entries.first?.bundleIdentifier == "com.apple.Terminal")
        #expect(second.entries.first?.wasCleanedUp == true)
    }

    @Test("append rejects a zero or negative word count as a no-op")
    func appendRejectsZeroWordCount() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try InsightsStore(directoryURL: directory)
        try store.append(wordCount: 0, audioDurationSeconds: 5, bundleIdentifier: nil, wasCleanedUp: true)
        #expect(store.entries.isEmpty)
    }

    @Test("append rejects a zero or negative audio duration as a no-op")
    func appendRejectsZeroDuration() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try InsightsStore(directoryURL: directory)
        try store.append(wordCount: 10, audioDurationSeconds: 0, bundleIdentifier: nil, wasCleanedUp: true)
        #expect(store.entries.isEmpty)
    }

    @Test("a nil bundleIdentifier round-trips correctly, not coerced to empty string")
    func nilBundleIdentifierRoundTrips() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try InsightsStore(directoryURL: directory)
        try store.append(wordCount: 10, audioDurationSeconds: 5, bundleIdentifier: nil, wasCleanedUp: true)

        let reloaded = try InsightsStore(directoryURL: directory)
        #expect(reloaded.entries.first?.bundleIdentifier == nil)
    }

    @Test("clear removes every entry and persists the removal")
    func clearRemovesEverythingAndPersists() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try InsightsStore(directoryURL: directory)
        try store.append(wordCount: 10, audioDurationSeconds: 5, bundleIdentifier: nil, wasCleanedUp: true)
        try store.clear()
        #expect(store.entries.isEmpty)

        let reloaded = try InsightsStore(directoryURL: directory)
        #expect(reloaded.entries.isEmpty)
    }
}
