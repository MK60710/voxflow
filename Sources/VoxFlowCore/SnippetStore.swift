import Foundation

/// One user-defined snippet: say `trigger` exactly and `expansion` gets
/// inserted instead — Wispr Flow's own "Snippets" feature (confirmed
/// against a real screenshot of it, 2026-08-13), same shape as VoxFlow's
/// existing personal dictionary but for whole reusable blocks of text
/// (an email signature, a LinkedIn URL, a rewrite prompt) instead of single
/// terms.
public struct SnippetEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var trigger: String
    public var expansion: String
    public let dateAdded: Date

    public init(id: UUID = UUID(), trigger: String, expansion: String, dateAdded: Date = Date()) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.dateAdded = dateAdded
    }
}

public enum SnippetStoreError: Error, Equatable, Sendable {
    case noApplicationSupportDirectory
}

/// Persisted snippet list — same shape as `DictionaryStore`/
/// `TranscriptLogStore`/`InsightsStore`: JSON file in
/// `~/Library/Application Support/VoxFlow/`, injectable directory for
/// testability, atomic writes, ISO8601 dates. Seeded empty, always — same
/// privacy rule `DictionaryStore` follows, no starter/example snippet ships
/// with a fresh install.
public final class SnippetStore {
    public private(set) var entries: [SnippetEntry]

    private let fileURL: URL

    public init(directoryURL: URL? = nil) throws {
        let directory = try directoryURL ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("snippets.json")
        self.entries = (try? Self.load(from: fileURL)) ?? []
    }

    public static func defaultDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SnippetStoreError.noApplicationSupportDirectory
        }
        return base.appendingPathComponent("VoxFlow", isDirectory: true)
    }

    private static func load(from fileURL: URL) throws -> [SnippetEntry] {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SnippetEntry].self, from: data)
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Trigger and expansion are both trimmed of SURROUNDING whitespace
    /// only — internal content of the expansion is preserved exactly,
    /// since a snippet's whole point is inserting exactly what was saved.
    /// An empty trigger OR empty expansion is rejected as a no-op — a
    /// snippet that matches nothing or inserts nothing isn't a real one.
    @discardableResult
    public func add(trigger: String, expansion: String) throws -> SnippetEntry? {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrigger.isEmpty, !trimmedExpansion.isEmpty else { return nil }
        let entry = SnippetEntry(trigger: trimmedTrigger, expansion: trimmedExpansion)
        entries.append(entry)
        try save()
        return entry
    }

    public func remove(id: UUID) throws {
        entries.removeAll { $0.id == id }
        try save()
    }

    public func update(id: UUID, trigger: String, expansion: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrigger.isEmpty, !trimmedExpansion.isEmpty else { return }
        entries[index].trigger = trimmedTrigger
        entries[index].expansion = trimmedExpansion
        try save()
    }
}
