import Foundation

/// The tone/cleanup-intensity profile Step 7 (context awareness) selects for
/// the frontmost app, per the blueprint's task 1 default map. Each case names
/// a documented prompt variant in `CleanupPromptTemplate`'s Step 7 section —
/// see `CleanupPromptTemplate.systemPrompt(for:)`.
///
/// Pure, `Codable`/`Sendable` — this is the type both `ContextDetector`
/// (bundle ID → tone) and the Settings UI's persisted assignment map use.
public enum ToneProfile: String, CaseIterable, Equatable, Sendable, Codable {
    /// iMessage/Slack/Discord-style: contractions allowed, no enforced
    /// trailing period, kept light. See `CleanupPromptTemplate.casualSystemPrompt`.
    case casual

    /// Mail/Word/Docs/Pages-style: complete, capitalized sentences with
    /// terminal punctuation enforced. See
    /// `CleanupPromptTemplate.professionalSystemPrompt`.
    case professional

    /// Xcode/Terminal/VS Code/iTerm-style: pass-through with only filler-word
    /// removal — no punctuation enforcement, no rewriting, since code/command
    /// text shouldn't be "cleaned up" into prose. See
    /// `CleanupPromptTemplate.codeOrTerminalSystemPrompt`.
    case codeOrTerminal

    /// The default/moderate tone — every app not otherwise assigned, and the
    /// exact Step 6 cleanup behavior unchanged. See
    /// `CleanupPromptTemplate.systemPrompt` (the original, untouched Step 6
    /// prompt).
    case neutral

    public var displayName: String {
        switch self {
        case .casual: return "Casual"
        case .professional: return "Professional"
        case .codeOrTerminal: return "Code / Terminal (minimal)"
        case .neutral: return "Neutral (default)"
        }
    }
}
