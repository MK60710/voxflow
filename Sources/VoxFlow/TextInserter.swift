import AppKit
import ApplicationServices
import Carbon.HIToolbox
import VoxFlowCore

/// Given a String, types it into whatever app/text field currently has
/// focus (blueprint Step 4 — the "output half"; S3 gave VoxFlow the input
/// half). Two strategies, tried in order:
///
/// 1. PRIMARY — `PasteboardCmdVInserter`: pasteboard-swap + synthetic
///    Cmd-V. Fast, near-universal, and handles rich apps (Slack, browsers,
///    iMessage) the same way a real paste would.
/// 2. FALLBACK — `CGEventUnicodeInserter`: direct CGEvent unicode keyboard
///    events, chunked via `VoxFlowCore.UTF16Chunker`. Used only if the
///    pasteboard write itself fails outright.
///
/// Both require Accessibility permission (`AXIsProcessTrusted`) to post
/// synthetic events into other apps. Secure Input — already detected by
/// `HotkeyManager` for the recording pill (Step 3) — blocks synthetic
/// keystrokes the same way it blocks the hotkey tap, so it's checked here
/// too rather than re-implemented.
@MainActor
protocol TextInserter: AnyObject {
    func insert(_ text: String, expectedFrontmostApp: NSRunningApplication?) async -> TextInsertionOutcome
}

@MainActor
final class SystemTextInserter: TextInserter {

    private let pasteboardInserter: PasteboardCmdVInserter
    private let cgEventInserter: CGEventUnicodeInserter
    private let overrideProvider: PerAppInsertionOverrideProviding

    init(
        pasteboardInserter: PasteboardCmdVInserter = PasteboardCmdVInserter(),
        cgEventInserter: CGEventUnicodeInserter = CGEventUnicodeInserter(),
        overrideProvider: PerAppInsertionOverrideProviding = NoOverridesConfigured()
    ) {
        self.pasteboardInserter = pasteboardInserter
        self.cgEventInserter = cgEventInserter
        self.overrideProvider = overrideProvider
    }

    func insert(_ text: String, expectedFrontmostApp: NSRunningApplication?) async -> TextInsertionOutcome {
        guard Self.accessibilityPermissionGranted else {
            return .accessibilityPermissionNeeded
        }
        // Reuses the same detection HotkeyManager already polls for the
        // recording pill (Step 3) — Secure Input blocks synthetic Cmd-V the
        // same way it blocks the event tap, so there's no separate
        // "insertion-side" secure-input implementation to maintain.
        guard !IsSecureEventInputEnabled() else {
            return .blockedBySecureInput
        }

        let current = NSWorkspace.shared.frontmostApplication
        guard FocusGuard.shouldProceed(
            expected: expectedFrontmostApp.map(AppIdentity.init),
            current: current.map(AppIdentity.init)
        ) else {
            return .heldForFocusChange(text: text)
        }

        // Historical note: a "menu-tracking Escape" mitigation once sat here
        // on the theory that VoxFlow's own open menu swallowed the synthetic
        // keystroke. The self-test harness disproved it (the Escape itself was
        // *causing* a ~30% insertion drop), so it was removed. See
        // docs/debugging-log.md (E5) — not a real factor.

        let strategy = overrideProvider.preferredStrategy(forBundleIdentifier: current?.bundleIdentifier) ?? .pasteboardSwap

        switch strategy {
        case .pasteboardSwap:
            if await pasteboardInserter.insert(text) {
                return .inserted(strategy: .pasteboardSwap)
            }
            // Pasteboard write itself failed outright (not a partial/race
            // case — those are handled inside PasteboardCmdVInserter) —
            // fall back to the CGEvent path.
            if cgEventInserter.insert(text) {
                return .inserted(strategy: .cgEventUnicode)
            }
            return .failed(reason: "Both pasteboard-swap and CGEvent insertion failed")
        case .cgEventUnicode:
            if cgEventInserter.insert(text) {
                return .inserted(strategy: .cgEventUnicode)
            }
            return .failed(reason: "CGEvent insertion failed")
        }
    }

    /// `AXIsProcessTrusted()` — reads current state, no prompt.
    static var accessibilityPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system's own Accessibility prompt if this is the first
    /// request (a no-op once the user has already decided) — same shape as
    /// `HotkeyManager.requestInputMonitoringPermission()` from Step 3. Call
    /// once at app start so the OS prompt (if any) appears before our own
    /// guidance alert would.
    static func requestAccessibilityPermission() {
        // Deliberately using the documented raw string "AXTrustedCheckOptionPrompt"
        // instead of the `kAXTrustedCheckOptionPrompt` CFStringRef constant:
        // Swift 6's strict concurrency checking flags that C-imported global
        // as unsafe shared mutable state (it's an `extern CFStringRef`, not
        // a `const`), even though its value never changes at runtime. Apple
        // documents this exact string as the key's value, so using it
        // directly avoids a false-positive data-race diagnostic without
        // reaching for an `unsafe` escape hatch.
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

private extension AppIdentity {
    init(_ app: NSRunningApplication) {
        self.init(processIdentifier: app.processIdentifier, bundleIdentifier: app.bundleIdentifier)
    }
}
