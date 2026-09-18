import Foundation

/// The 4 basic voice commands (blueprint Step 10): executed as key events
/// instead of typed text.
public enum VoiceCommand: String, CaseIterable, Sendable {
    case newLine
    case newParagraph
    case undo
    case selectAll

    /// The exact phrase this command matches — also the read-only phrase
    /// list shown in Settings (task 4).
    public var phrase: String {
        switch self {
        case .newLine: return "new line"
        case .newParagraph: return "new paragraph"
        case .undo: return "undo that"
        case .selectAll: return "select all"
        }
    }

    /// Shown in the recording pill when a command executes (task 3: "pill
    /// shows the command name").
    public var displayName: String {
        switch self {
        case .newLine: return "New line"
        case .newParagraph: return "New paragraph"
        case .undo: return "Undo"
        case .selectAll: return "Select all"
        }
    }
}

/// Recognizes an EXACT (fuzzy-normalized) match against the command phrase
/// table — pure, offline-testable. Deliberately conservative, per the
/// blueprint's explicit design decision: "utterances that are EXACTLY a
/// command execute; commands embedded mid-dictation are typed as words" —
/// e.g. "select all of the budget items" must NOT execute Select All, it
/// must type as text. This is why recognition is a full-string dictionary
/// lookup after normalization, not a substring/contains check — a
/// substring check would make every command a false-positive trap for
/// anyone who happens to dictate that phrase as part of a longer sentence.
public enum CommandRecognizer {
    private static let phraseTable: [String: VoiceCommand] = Dictionary(
        uniqueKeysWithValues: VoiceCommand.allCases.map { ($0.phrase, $0) }
    )

    /// `nil` means "not a command — type it as text", the safe default for
    /// anything that isn't an exact match.
    public static func recognize(_ transcript: String) -> VoiceCommand? {
        phraseTable[normalize(transcript)]
    }

    /// Lowercases, strips punctuation, collapses whitespace, and trims —
    /// so "Undo that.", "undo  that", and "UNDO THAT" all match "undo
    /// that", but the match stays EXACT (full-string) after normalization,
    /// not fuzzy/partial.
    static func normalize(_ transcript: String) -> String {
        let lowered = transcript.lowercased()
        let strippedPunctuation = lowered.unicodeScalars
            .filter { !CharacterSet.punctuationCharacters.contains($0) }
        let collapsed = String(String.UnicodeScalarView(strippedPunctuation))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed
    }
}
