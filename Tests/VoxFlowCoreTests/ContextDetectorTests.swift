import Foundation
import Testing
@testable import VoxFlowCore

/// Offline tests for Step 7 task 4: "bundle-ID → tone-profile mapping
/// logic". Pure `ContextDetector`/`ToneProfile` logic — no AppKit, no
/// network, no `NSWorkspace`.
@Suite("ContextDetector")
struct ContextDetectorTests {

    // MARK: - Default map (blueprint task 1's sensible defaults)

    @Test("messaging apps (Messages, Slack, Discord) default to casual")
    func messagingAppsDefaultToCasual() {
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.apple.MobileSMS") == .casual)
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.tinyspeck.slackmacgap") == .casual)
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.hnc.Discord") == .casual)
    }

    @Test("email/docs apps (Mail, Word, Pages) default to professional")
    func emailDocsAppsDefaultToProfessional() {
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.apple.mail") == .professional)
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.microsoft.Word") == .professional)
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.apple.iWork.Pages") == .professional)
    }

    @Test("code editors and terminals (Xcode, Terminal, VS Code, iTerm) default to codeOrTerminal")
    func codeAndTerminalAppsDefaultToCodeOrTerminal() {
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.apple.Terminal") == .codeOrTerminal)
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.googlecode.iterm2") == .codeOrTerminal)
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.microsoft.VSCode") == .codeOrTerminal)
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.apple.dt.Xcode") == .codeOrTerminal)
    }

    @Test("an unrecognized bundle identifier falls back to neutral (Step 6's original default behavior)")
    func unrecognizedBundleIdentifierFallsBackToNeutral() {
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.example.SomeRandomApp") == .neutral)
    }

    @Test("a nil bundle identifier (frontmost app couldn't be determined) fails open to neutral")
    func nilBundleIdentifierFailsOpenToNeutral() {
        #expect(ContextDetector.toneProfile(forBundleIdentifier: nil) == .neutral)
    }

    // MARK: - Custom assignment map (Settings overrides)

    @Test("a caller-supplied assignment map overrides the built-in defaults")
    func customAssignmentsOverrideDefaults() {
        // Mihir reassigns Slack to professional and Terminal to casual via
        // Settings — the lookup must reflect the override, not the default.
        let overrides: [String: ToneProfile] = [
            "com.tinyspeck.slackmacgap": .professional,
            "com.apple.Terminal": .casual
        ]
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.tinyspeck.slackmacgap", assignments: overrides) == .professional)
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.apple.Terminal", assignments: overrides) == .casual)
    }

    @Test("an empty assignment map means every bundle identifier falls back to neutral")
    func emptyAssignmentMapFallsBackToNeutralForEverything() {
        #expect(ContextDetector.toneProfile(forBundleIdentifier: "com.apple.MobileSMS", assignments: [:]) == .neutral)
    }

    // MARK: - defaultAssignments()

    @Test("defaultAssignments() contains exactly the messaging/professional/code-terminal sets, nothing else")
    func defaultAssignmentsContainsExactlyTheDocumentedSets() {
        let defaults = ContextDetector.defaultAssignments()
        for id in ContextDetector.defaultMessagingApps {
            #expect(defaults[id] == .casual)
        }
        for id in ContextDetector.defaultProfessionalApps {
            #expect(defaults[id] == .professional)
        }
        for id in ContextDetector.defaultCodeOrTerminalApps {
            #expect(defaults[id] == .codeOrTerminal)
        }
        let expectedCount = ContextDetector.defaultMessagingApps.count
            + ContextDetector.defaultProfessionalApps.count
            + ContextDetector.defaultCodeOrTerminalApps.count
        #expect(defaults.count == expectedCount)
    }

    @Test("no bundle identifier appears in two different default tone sets")
    func defaultSetsAreDisjoint() {
        let messaging = ContextDetector.defaultMessagingApps
        let professional = ContextDetector.defaultProfessionalApps
        let codeOrTerminal = ContextDetector.defaultCodeOrTerminalApps
        #expect(messaging.isDisjoint(with: professional))
        #expect(messaging.isDisjoint(with: codeOrTerminal))
        #expect(professional.isDisjoint(with: codeOrTerminal))
    }

    // MARK: - ToneProfile

    @Test("every ToneProfile case has a non-empty display name")
    func toneProfileDisplayNamesAreNonEmpty() {
        for tone in ToneProfile.allCases {
            #expect(!tone.displayName.isEmpty)
        }
    }
}
