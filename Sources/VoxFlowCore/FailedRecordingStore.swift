import Foundation

/// **Added 2026-09-08** (Mihir's report: "even when it times out, you don't
/// even give me anything... have a fallback"): when EVERY transcription
/// engine fails for one dictation (Groq and the Apple Speech fallback both),
/// there's no raw text to fall back to — neither engine ever produced one —
/// but the recorded WAV itself was never actually deleted anywhere in this
/// codebase; it just sat forgotten in the OS temp directory with nothing
/// pointing at it, at the mercy of the OS's own temp-cleanup timing. This
/// moves that WAV somewhere permanent and findable instead of a silent
/// total loss. Same directory convention as `TranscriptLogStore`.
public enum FailedRecordingStoreError: Error, Equatable, Sendable {
    case noApplicationSupportDirectory
}

public enum FailedRecordingStore {
    public static func defaultDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw FailedRecordingStoreError.noApplicationSupportDirectory
        }
        return base
            .appendingPathComponent("VoxFlow", isDirectory: true)
            .appendingPathComponent("failed-recordings", isDirectory: true)
    }

    /// Moves (not copies — the temp original is disposable either way) the
    /// WAV at `sourceURL` into the failed-recordings directory, prefixed
    /// with the failure time so multiple failures sort and scan naturally.
    /// Returns the destination filename on success, `nil` on any failure —
    /// this is a best-effort safety net, not worth a second error path of
    /// its own; the ORIGINAL transcription error is still the one that
    /// matters to the user.
    @discardableResult
    public static func preserve(_ sourceURL: URL, directoryURL: URL? = nil, now: Date = Date()) -> String? {
        do {
            let directory = try directoryURL ?? Self.defaultDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let filename = "\(Self.timestampString(for: now))-\(sourceURL.lastPathComponent)"
            let destination = directory.appendingPathComponent(filename)
            try FileManager.default.moveItem(at: sourceURL, to: destination)
            return filename
        } catch {
            return nil
        }
    }

    private static func timestampString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
