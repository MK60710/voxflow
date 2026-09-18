import Foundation

/// One logged dictation, for the Insights feature (Wispr Flow's "Your
/// usage" tab, confirmed against a real screenshot 2026-08-13 — the
/// percentile ranking and AI-classified "task type" breakdown from that
/// screenshot are deliberately NOT reproduced here: percentile needs a
/// user base to rank against, which a single-user local app doesn't have,
/// and task-type classification is a lot of added complexity for a mostly
/// cosmetic number. "Your voice" — Wispr's LLM-generated personality
/// profile tab — was explicitly ruled unnecessary by Mihir, not built at
/// all).
public struct InsightsEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let wordCount: Int
    public let audioDurationSeconds: Double
    /// `nil` when the frontmost app couldn't be determined — kept as a real
    /// optional rather than an empty-string sentinel.
    public let bundleIdentifier: String?
    /// Whether `CleanupCoordinator` actually cleaned this dictation
    /// (`.cleaned`) vs. fell back to the raw transcript (`.raw`, any
    /// reason) — drives the "fixes made" count.
    public let wasCleanedUp: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        wordCount: Int,
        audioDurationSeconds: Double,
        bundleIdentifier: String?,
        wasCleanedUp: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.wordCount = wordCount
        self.audioDurationSeconds = audioDurationSeconds
        self.bundleIdentifier = bundleIdentifier
        self.wasCleanedUp = wasCleanedUp
    }
}

public enum InsightsStoreError: Error, Equatable, Sendable {
    case noApplicationSupportDirectory
}

/// Persisted dictation history — same shape as `DictionaryStore`/
/// `TranscriptLogStore`/`SnippetStore`: JSON file in
/// `~/Library/Application Support/VoxFlow/`, injectable directory for
/// testability, atomic writes, ISO8601 dates.
public final class InsightsStore {
    /// Generous cap — small individual records (a handful of fields each),
    /// and the whole point is real historical stats (streaks, totals), so
    /// this is sized to hold months of realistic daily usage rather than
    /// the much tighter caps `TranscriptLogStore`/command history use for
    /// their own, different, "recent recovery" purpose.
    public static let maxEntries = 10_000

    /// Newest first, matching every other store's own convention in this
    /// codebase.
    public private(set) var entries: [InsightsEntry]

    private let fileURL: URL

    public init(directoryURL: URL? = nil) throws {
        let directory = try directoryURL ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("insights.json")
        self.entries = (try? Self.load(from: fileURL)) ?? []
    }

    public static func defaultDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw InsightsStoreError.noApplicationSupportDirectory
        }
        return base.appendingPathComponent("VoxFlow", isDirectory: true)
    }

    private static func load(from fileURL: URL) throws -> [InsightsEntry] {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([InsightsEntry].self, from: data)
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    /// A zero/negative word count or duration is a caller bug (there is
    /// nothing meaningful to log), rejected as a no-op rather than
    /// polluting the stats with a degenerate record.
    public func append(
        wordCount: Int,
        audioDurationSeconds: Double,
        bundleIdentifier: String?,
        wasCleanedUp: Bool
    ) throws {
        guard wordCount > 0, audioDurationSeconds > 0 else { return }
        entries.insert(
            InsightsEntry(
                wordCount: wordCount,
                audioDurationSeconds: audioDurationSeconds,
                bundleIdentifier: bundleIdentifier,
                wasCleanedUp: wasCleanedUp
            ),
            at: 0
        )
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
