import AppKit
import os.log
import VoxFlowCore

private let insertionLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "TextInsertion")

/// Wires the output half of the pipeline (blueprint Step 4) to the shared
/// pill UI: captures the frontmost app at insertion-REQUEST time (the
/// blueprint notes S5a will instead pass the app captured at hotkey-PRESS
/// time — see `VoxFlowCore.FocusGuard`'s doc comment; that wiring is not
/// Step 4's job), calls `TextInserter`, and turns its `TextInsertionOutcome`
/// into pill messages / permission guidance, following the same UX shape S3
/// used for Input Monitoring.
///
/// Owned as a singleton (`shared`), same pattern as `DictationCoordinator`,
/// so both the menu's test-insertion item today and (from S5a onward) the
/// real dictation pipeline share one inserter and one pill.
@MainActor
final class TextInsertionCoordinator: ObservableObject {
    static let shared = TextInsertionCoordinator()

    /// Fixed test string (blueprint Step 4, task 5): "café" and "naïve"
    /// exercise accented characters, "☕️" (U+2615 HOT BEVERAGE + U+FE0F
    /// variation selector) exercises a multi-unit grapheme cluster through
    /// the CGEvent fallback's chunker. True surrogate-pair coverage (e.g.
    /// 😀, U+1F600) is exercised directly by `UTF16ChunkerTests` in
    /// VoxFlowCore, since correctness there doesn't depend on any live app.
    static let testInsertionString = "café ☕️ naïve"
    static let testInsertionDelay: TimeInterval = 3.0

    private let inserter: TextInserter
    private var pendingInsertionText: String?

    @Published private(set) var lastOutcome: TextInsertionOutcome?

    private init(inserter: TextInserter = SystemTextInserter()) {
        self.inserter = inserter
    }

    /// Triggers the system's own Accessibility prompt (if undecided) before
    /// any insertion is attempted — same shape as
    /// `DictationCoordinator.start()` requesting Input Monitoring up front.
    func start() {
        SystemTextInserter.requestAccessibilityPermission()
    }

    /// Entry point future steps use: capture-then-insert with no artificial
    /// delay. S5a will call this directly, passing the app it captured at
    /// hotkey-press time instead of letting this re-capture it.
    func requestInsertion(_ text: String, expectedFrontmostApp: NSRunningApplication? = nil) {
        let expected = expectedFrontmostApp ?? NSWorkspace.shared.frontmostApplication
        Task { await performInsertion(text, expectedFrontmostApp: expected) }
    }

    /// Debug/test harness (blueprint Step 4, task 5): captures the
    /// frontmost app NOW (insertion-request time), waits
    /// `testInsertionDelay`, then attempts insertion of the fixed test
    /// string — so switching apps during the wait is a real, reproducible
    /// way to trigger the focus-guard's "click to insert" pill instead of
    /// typing into the wrong window.
    func runTestInsertion() {
        let expected = NSWorkspace.shared.frontmostApplication
        RecordingPillController.shared.show(
            message: "Test insertion in \(Int(Self.testInsertionDelay))s… switch apps to test the focus guard",
            isError: false,
            onClick: nil
        )
        os_log(.info, log: insertionLog, "Test insertion armed; captured frontmost app: %{public}@", expected?.bundleIdentifier ?? "unknown")
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.testInsertionDelay * 1_000_000_000))
            await performInsertion(Self.testInsertionString, expectedFrontmostApp: expected)
        }
    }

    private func performInsertion(_ text: String, expectedFrontmostApp: NSRunningApplication?) async {
        let outcome = await inserter.insert(text, expectedFrontmostApp: expectedFrontmostApp)
        lastOutcome = outcome
        handle(outcome, originalText: text)
    }

    private func handle(_ outcome: TextInsertionOutcome, originalText: String) {
        switch outcome {
        case .inserted(let strategy):
            os_log(.info, log: insertionLog, "Inserted via %{public}@", String(describing: strategy))
            // Return to the persistent "Ready" pill instead of hiding it.
            RecordingPillController.shared.show(.idle)

        case .heldForFocusChange:
            os_log(.info, log: insertionLog, "Frontmost app changed since request — holding for confirmation")
            pendingInsertionText = originalText
            RecordingPillController.shared.show(
                message: "Click to insert",
                isError: false,
                onClick: { [weak self] in self?.confirmPendingInsertion() }
            )

        case .accessibilityPermissionNeeded:
            os_log(.error, log: insertionLog, "Accessibility permission not granted")
            RecordingPillController.shared.show(message: "Needs Accessibility permission", isError: true, onClick: nil)
            presentAccessibilityGuidanceAlert()

        case .blockedBySecureInput:
            os_log(.info, log: insertionLog, "Insertion blocked by secure input")
            RecordingPillController.shared.show(message: "Blocked by secure input", isError: true, onClick: nil)

        case .failed(let reason):
            os_log(.error, log: insertionLog, "Insertion failed: %{public}@", reason)
            RecordingPillController.shared.show(message: reason, isError: true, onClick: nil)
        }
    }

    /// Fires when the user clicks the "click to insert" pill: re-captures
    /// the (now-current) frontmost app as the new expectation and retries
    /// once. If the user switches away again between the click and the
    /// (near-instant) retry, they'll just see another "click to insert" —
    /// no silent misfire either way.
    private func confirmPendingInsertion() {
        guard let pending = pendingInsertionText else { return }
        pendingInsertionText = nil
        let expected = NSWorkspace.shared.frontmostApplication
        Task { await performInsertion(pending, expectedFrontmostApp: expected) }
    }

    // MARK: - Accessibility permission guidance

    /// Same UX shape as `DictationCoordinator.presentPermissionGuidanceAlert`
    /// (Step 3) — an NSAlert with a System Settings deep link — extended
    /// here for Accessibility instead of Input Monitoring.
    private func presentAccessibilityGuidanceAlert() {
        let alert = NSAlert()
        alert.messageText = "VoxFlow needs Accessibility permission"
        alert.informativeText = "Open System Settings → Privacy & Security → Accessibility, enable VoxFlow, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
