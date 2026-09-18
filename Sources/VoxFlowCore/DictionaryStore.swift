import Foundation

/// One user-added dictionary entry (blueprint Step 8 task 1): a term VoxFlow
/// should bias transcription/cleanup toward, with an optional "sounds like"
/// hint for cases where the correct spelling doesn't sound the way it's
/// spelled (e.g. term "CogniSwitch", soundsLike "cog-nih-switch").
public struct DictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var term: String
    public var soundsLike: String?
    /// Append-order timestamp. `DictionaryPromptAssembly`'s "truncate
    /// oldest-first" rule relies on `DictionaryStore.entries` already being
    /// in oldest-to-newest order (a plain `append`-only array) rather than
    /// re-sorting by this field every time — kept here mainly so the model
    /// itself is self-describing and future UI (e.g. "added 3 days ago")
    /// doesn't need a second source of truth.
    public let dateAdded: Date

    public init(id: UUID = UUID(), term: String, soundsLike: String? = nil, dateAdded: Date = Date()) {
        self.id = id
        self.term = term
        self.soundsLike = soundsLike
        self.dateAdded = dateAdded
    }
}

public enum DictionaryStoreError: Error, Equatable, Sendable {
    /// `FileManager.default.urls(for: .applicationSupportDirectory, ...)`
    /// returned no URL at all — not expected on a normal macOS install, but
    /// handled rather than force-unwrapped (see `DictionaryCoordinator`'s
    /// App-layer fallback for what happens to the app when this fires).
    case noApplicationSupportDirectory
}

/// Persisted word list (blueprint Step 8 task 1): JSON file in Application
/// Support, following `docs/architecture.md`'s "Settings storage" line
/// ("JSON in `~/Library/Application Support/VoxFlow/` for the dictionary")
/// and using the exact mechanism the blueprint names
/// (`FileManager.default.urls(for: .applicationSupportDirectory, ...)`).
///
/// **Seeded EMPTY, always** (blueprint task 2's explicit privacy rule): a
/// fresh install with no `dictionary.json` on disk starts with zero
/// entries. Nothing in this type — or anywhere else in this step — ever
/// writes a starter/default/example entry containing a real name.
///
/// The directory is an injectable initializer parameter (defaulting to the
/// real Application Support path) so the Swift Testing round-trip test can
/// point this at a throwaway temp directory instead of touching Mihir's
/// real `~/Library/Application Support/VoxFlow/` on every `swift test` run
/// — same "inject the real side effect for testability" shape as
/// `TranscriptionHTTPTransport`/`CleanupHTTPTransport` use for networking.
public final class DictionaryStore {
    public private(set) var entries: [DictionaryEntry]

    private let fileURL: URL

    public init(directoryURL: URL? = nil) throws {
        let directory = try directoryURL ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("dictionary.json")
        self.entries = (try? Self.load(from: fileURL)) ?? []
    }

    /// `~/Library/Application Support/VoxFlow/` — the exact directory
    /// `docs/architecture.md` already names for this purpose.
    public static func defaultDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DictionaryStoreError.noApplicationSupportDirectory
        }
        return base.appendingPathComponent("VoxFlow", isDirectory: true)
    }

    private static func load(from fileURL: URL) throws -> [DictionaryEntry] {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([DictionaryEntry].self, from: data)
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Appends a new entry (oldest-to-newest order, which
    /// `DictionaryPromptAssembly`'s truncation relies on) and persists
    /// immediately. Both `term` and `soundsLike` are trimmed; an
    /// empty/whitespace-only `term` is rejected as a no-op (returns `nil`)
    /// — the Settings UI is expected to disable its Add control on empty
    /// input, but this is the real guarantee, not just a UI nicety.
    @discardableResult
    public func add(term: String, soundsLike: String? = nil) throws -> DictionaryEntry? {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return nil }
        let trimmedHint = soundsLike?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = DictionaryEntry(
            term: trimmedTerm,
            soundsLike: (trimmedHint?.isEmpty ?? true) ? nil : trimmedHint
        )
        entries.append(entry)
        try save()
        return entry
    }

    /// No-op (not an error) if `id` isn't found — callers (Settings UI /
    /// tests) don't need to guard against a stale id first.
    public func remove(id: UUID) throws {
        entries.removeAll { $0.id == id }
        try save()
    }

    /// No-op if `id` isn't found or `term` is empty after trimming (same
    /// "reject empty term" rule as `add`).
    public func update(id: UUID, term: String, soundsLike: String?) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return }
        let trimmedHint = soundsLike?.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].term = trimmedTerm
        entries[index].soundsLike = (trimmedHint?.isEmpty ?? true) ? nil : trimmedHint
        try save()
    }
}
