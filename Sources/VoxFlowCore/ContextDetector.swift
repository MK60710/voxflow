import Foundation

/// Bundle ID → tone-profile mapping (blueprint Step 7, task 1). Pure,
/// testable, AppKit-free — the AppKit glue
/// (`Sources/VoxFlow/ContextSettingsStore.swift`) turns
/// `NSWorkspace.shared.frontmostApplication` into a bundle identifier string
/// and calls `toneProfile(forBundleIdentifier:assignments:)` here.
///
/// Frontmost-app capture itself is NOT this file's job: per the blueprint,
/// Step 7 reuses `DictationCoordinator`'s existing `frontmostAppAtKeyPress`
/// (captured at hotkey-PRESS time, the same capture Step 4/5a use for the
/// text-insertion focus-guard) rather than re-querying `NSWorkspace` after
/// transcription. See `TranscriptionCoordinator.transcribeAndInsert` for
/// where that captured app's bundle ID is turned into a tone via this type.
public enum ContextDetector {
    /// Messaging apps → casual (blueprint task 1). Bundle IDs are each app's
    /// real, documented identifier.
    public static let defaultMessagingApps: Set<String> = [
        "com.apple.MobileSMS",        // Messages/iMessage (macOS)
        "com.tinyspeck.slackmacgap",  // Slack desktop app
        "com.hnc.Discord"             // Discord desktop app
    ]

    /// Email/docs apps → professional (blueprint task 1).
    ///
    /// **Known gap, not silently ignored:** the blueprint also names "Google
    /// Docs in a browser" here, but a bundle ID identifies the BROWSER
    /// process, not which tab/site is open — there is no bundle-ID-level way
    /// to tell a Google Docs tab apart from any other tab in the same
    /// browser. Not solved in this step. Mihir can still assign his browser's
    /// own bundle ID to `.professional` via the Settings UI if he mostly
    /// dictates into Docs there, understanding that this would then apply to
    /// every tab in that browser, not just Docs. Flagged in PROGRESS.md too.
    public static let defaultProfessionalApps: Set<String> = [
        "com.apple.mail",       // Mail
        "com.microsoft.Word",   // Microsoft Word
        "com.apple.iWork.Pages" // Pages
    ]

    /// Code editors/terminals → codeOrTerminal, raw-or-minimal cleanup
    /// (blueprint task 1).
    public static let defaultCodeOrTerminalApps: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode"
    ]

    /// The full bundle-ID → tone default map, built fresh from the sets
    /// above. This is both what `toneProfile(forBundleIdentifier:)` falls
    /// back to when no user assignment map is supplied, and what a "Reset to
    /// defaults" Settings action restores.
    public static func defaultAssignments() -> [String: ToneProfile] {
        var map: [String: ToneProfile] = [:]
        for id in defaultMessagingApps { map[id] = .casual }
        for id in defaultProfessionalApps { map[id] = .professional }
        for id in defaultCodeOrTerminalApps { map[id] = .codeOrTerminal }
        return map
    }

    /// Pure lookup: bundle identifier → tone profile, given an assignment
    /// map (defaults merged with any user overrides — the App layer's
    /// `ContextSettingsStore` owns building that merged map). Fails open to
    /// `.neutral` (the exact Step 6 default cleanup behavior) both when
    /// `bundleIdentifier` is `nil` (frontmost app couldn't be determined —
    /// same "fail open" convention as `FocusGuard.shouldProceed`) and when
    /// the identifier simply has no assignment.
    public static func toneProfile(
        forBundleIdentifier bundleIdentifier: String?,
        assignments: [String: ToneProfile] = ContextDetector.defaultAssignments()
    ) -> ToneProfile {
        guard let bundleIdentifier, let assigned = assignments[bundleIdentifier] else {
            return .neutral
        }
        return assigned
    }
}
