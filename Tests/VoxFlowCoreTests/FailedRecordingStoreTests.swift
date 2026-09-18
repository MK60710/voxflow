import Foundation
import Testing
@testable import VoxFlowCore

/// Mirrors `TranscriptLogStoreTests`' exact shape: every test points
/// `FailedRecordingStore` at a fresh throwaway temp directory (never the
/// real `~/Library/Application Support/VoxFlow/`) so `swift test` never
/// touches Mihir's real files.
@Suite("FailedRecordingStore")
struct FailedRecordingStoreTests {

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voxflow-failedrecording-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeSourceWAV(named name: String = "voxflow-\(UUID().uuidString).wav") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data([0x01, 0x02, 0x03]).write(to: url)
        return url
    }

    @Test("preserve moves the source file into the target directory and returns its new filename")
    func preserveMovesFileAndReturnsFilename() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSourceWAV()

        let filename = FailedRecordingStore.preserve(source, directoryURL: directory)

        #expect(filename != nil)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let destination = directory.appendingPathComponent(filename!)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("preserve creates the target directory if it doesn't exist yet")
    func preserveCreatesDirectoryIfNeeded() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let source = try makeSourceWAV()

        _ = FailedRecordingStore.preserve(source, directoryURL: directory)

        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("preserve returns nil, not a crash, when the source file doesn't exist")
    func preserveReturnsNilForMissingSource() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingSource = FileManager.default.temporaryDirectory.appendingPathComponent("voxflow-\(UUID().uuidString).wav")

        let filename = FailedRecordingStore.preserve(missingSource, directoryURL: directory)

        #expect(filename == nil)
    }

    @Test("preserved filename is timestamp-prefixed and preserves the original name")
    func preservedFilenameIncludesTimestampAndOriginalName() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSourceWAV(named: "voxflow-ABCDEF.wav")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let filename = FailedRecordingStore.preserve(source, directoryURL: directory, now: fixedDate)

        #expect(filename != nil)
        #expect(filename!.hasSuffix("voxflow-ABCDEF.wav"))
        #expect(filename! != "voxflow-ABCDEF.wav")
    }

    @Test("two failures in the same directory both survive as distinct files")
    func twoFailuresBothSurvive() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeSourceWAV(named: "voxflow-first.wav")
        let second = try makeSourceWAV(named: "voxflow-second.wav")

        let firstFilename = FailedRecordingStore.preserve(first, directoryURL: directory, now: Date(timeIntervalSince1970: 1_700_000_000))
        let secondFilename = FailedRecordingStore.preserve(second, directoryURL: directory, now: Date(timeIntervalSince1970: 1_700_000_060))

        #expect(firstFilename != secondFilename)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents.count == 2)
    }
}
