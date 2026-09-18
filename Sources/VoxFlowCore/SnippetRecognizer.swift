import Foundation

/// Recognizes an EXACT (fuzzy-normalized) match against the user's snippet
/// triggers — reuses `CommandRecognizer.normalize` (same module, same
/// normalization: lowercase, strip punctuation, collapse whitespace) so
/// "My LinkedIn.", "my linkedin", and "MY LINKEDIN" all match a saved
/// trigger "my LinkedIn" identically. Same conservative design as
/// `CommandRecognizer`: a trigger phrase embedded mid-sentence does NOT
/// match — "check out my LinkedIn profile" must type as text, not fire the
/// snippet — for the identical false-positive-safety reason.
///
/// Unlike `CommandRecognizer`'s fixed 4-entry table, the trigger set here
/// is user-defined and changes at runtime, so this takes the current
/// snippet list as a parameter rather than owning a static table.
public enum SnippetRecognizer {
    /// `nil` means "not a snippet trigger — type/clean it normally", same
    /// safe-default philosophy as `CommandRecognizer.recognize`.
    public static func recognize(_ transcript: String, snippets: [SnippetEntry]) -> String? {
        let normalizedTranscript = CommandRecognizer.normalize(transcript)
        guard !normalizedTranscript.isEmpty else { return nil }
        return snippets.first { CommandRecognizer.normalize($0.trigger) == normalizedTranscript }?.expansion
    }
}
