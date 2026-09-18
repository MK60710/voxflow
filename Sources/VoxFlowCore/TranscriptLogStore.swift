import Foundation

/// One logged dictation — the final, post-cleanup text that was handed to
/// text insertion, kept regardless of whether insertion itself succeeded.
public struct TranscriptLogEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let text: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}

public enum TranscriptLogStoreError: Error, Equatable, Sendable {
    /// Mirrors `DictionaryStoreError.noApplicationSupportDirectory` — not
    /// expected on a normal macOS install, handled rather than
    /// force-unwrapped.
    case noApplicationSupportDirectory
}

/// **Persisted 2026-08-13, Mihir's explicit request** ("this transcript log
/// should be permanent, not just go when it closes"): every dictation
/// survives an app relaunch, not just the current session — the whole point
/// is a safety net for text that failed to paste, and a safety net that
/// evaporates on the next relaunch is a weaker net than it should be.
///
/// Same shape as `DictionaryStore` exactly: JSON file in
/// `~/Library/Application Support/VoxFlow/`, injectable directory for
/// testability, atomic writes, ISO8601 dates.
public final class TranscriptLogStore {
    /// Oldest entries drop off past this count on every `append` — a
    /// permanent, unbounded, never-pruned log would grow forever for a
    /// long-lived menu-bar app; 200 is generous headroom past what anyone
    /// would realistically need to recover after a failed paste while
    /// still capping real-world file size.
    public static let maxEntries = 200

    /// Newest first, matching the log window's own display order — a
    /// caller wanting oldest-first can simply reverse.
    public private(set) var entries: [TranscriptLogEntry]

    private let fileURL: URL

    public init(directoryURL: URL? = nil) throws {
        let directory = try directoryURL ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("transcript-log.json")
        self.entries = (try? Self.load(from: fileURL)) ?? []
    }

    public static func defaultDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw TranscriptLogStoreError.noApplicationSupportDirectory
        }
        return base.appendingPathComponent("VoxFlow", isDirectory: true)
    }

    private static func load(from fileURL: URL) throws -> [TranscriptLogEntry] {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TranscriptLogEntry].self, from: data)
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Inserts at the front (newest-first) and persists immediately. A
    /// no-op for empty text — nothing meaningful to recover, same
    /// "reject the degenerate case" reasoning `DictionaryStore.add` uses
    /// for an empty term.
    public func append(_ text: String) throws {
        guard !text.isEmpty else { return }
        entries.insert(TranscriptLogEntry(text: text), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        try save()
    }

    public func clear() throws {
        entries.removeAll()
        try save()
    }
}
