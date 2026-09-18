import AVFoundation
import AppKit
import SwiftUI
import VoxFlowCore

/// First-run onboarding (blueprint Step 11a, task 1): a real window (not a
/// menu or alert, unlike every other piece of guidance UI so far) walking
/// through the two permissions VoxFlow actually needs — Microphone
/// (`AudioRecorder`) and Accessibility (`HotkeyManager` + `SystemTextInserter`
/// both key off `AXIsProcessTrusted`, confirmed while building this: Input
/// Monitoring is NOT a real VoxFlow requirement despite two now-fixed stale
/// UI strings that used to claim otherwise — see
/// `DictationCoordinator.presentPermissionGuidanceAlert`'s doc comment).
///
/// Shown once automatically (gated on `hasCompletedOnboarding` in
/// `UserDefaults`) and reachable again anytime via the menu's "Onboarding…"
/// item, same "revisit anytime" precedent as Settings.
@MainActor
final class OnboardingCoordinator: ObservableObject {
    static let shared = OnboardingCoordinator()

    private static let hasCompletedOnboardingDefaultsKey = "voxflow.hasCompletedOnboarding"

    private var window: NSWindow?

    private init() {}

    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: hasCompletedOnboardingDefaultsKey)
    }

    /// Called once at launch (`AppDelegate.applicationDidFinishLaunching`).
    /// A no-op on every launch after the first real completion.
    func showIfFirstRun() {
        guard !Self.hasCompletedOnboarding else { return }
        show()
    }

    /// Also the menu's "Onboarding…" entry point — revisiting doesn't reset
    /// `hasCompletedOnboarding`, so leaving via the window's own close
    /// button (not "Get Started") doesn't strand a returning user in
    /// first-run state forever.
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: OnboardingView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Welcome to VoxFlow"
        newWindow.contentView = hosting
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        // LSUIElement apps don't automatically become key/frontmost when a
        // window opens — same reasoning `RecordingPillController` documents
        // for why its panel uses `.statusBar` level; here `activate` is the
        // right tool instead, since this IS a real, focusable window the
        // user should be typing/clicking into, not a passive overlay.
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// "Get Started" — marks onboarding complete (never shown automatically
    /// again) and closes the window.
    func finish() {
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingDefaultsKey)
        window?.close()
    }
}

/// Live permission state for both checklist rows, polled the same way
/// `HotkeyManager` polls Secure Input (`IsSecureEventInputEnabled` has no
/// change notification either) — 500ms is responsive enough for a user
/// alt-tabbing back from System Settings after granting, without being a
/// meaningful cost for a window that's only ever open briefly.
@MainActor
private final class OnboardingPermissionState: ObservableObject {
    @Published var microphoneGranted = false
    @Published var accessibilityGranted = false

    private var timer: Timer?

    init() {
        refresh()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // No `deinit` cleanup — same reasoning as `HotkeyManager`'s own doc
    // comment: this object lives as long as the onboarding window does
    // (effectively app lifetime, since `OnboardingCoordinator` never nils
    // out the window after close), a nonisolated deinit can't touch
    // `@MainActor` timer state in Swift 6 mode anyway, and the OS reclaims
    // the timer on process exit.

    private func refresh() {
        microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        accessibilityGranted = HotkeyManager.hotkeyPermissionGranted()
    }
}

private struct OnboardingView: View {
    @StateObject private var state = OnboardingPermissionState()
    @ObservedObject private var hotkey = HotkeyCoordinator.shared

    private var allGranted: Bool { state.microphoneGranted && state.accessibilityGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to VoxFlow")
                    .font(.title2.bold())
                Text("Hold \(hotkey.selectedHotkey.displayName) anywhere to dictate. VoxFlow needs two permissions to work.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            PermissionRow(
                title: "Microphone",
                detail: "So VoxFlow can hear what you say while you hold the hotkey.",
                granted: state.microphoneGranted,
                action: {
                    AudioRecorder.requestMicrophonePermissionIfNeeded { _ in }
                },
                actionLabel: "Request Access"
            )

            PermissionRow(
                title: "Accessibility",
                detail: "So VoxFlow can detect the hotkey system-wide and type into whatever app has focus.",
                granted: state.accessibilityGranted,
                action: {
                    HotkeyManager.requestAccessibilityPermission()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                },
                actionLabel: "Open System Settings"
            )

            Spacer()

            HStack {
                Button("Skip for now") {
                    OnboardingCoordinator.shared.finish()
                }
                Spacer()
                Button(allGranted ? "Get Started" : "Continue Anyway") {
                    OnboardingCoordinator.shared.finish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 400)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .font(.title3)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !granted {
                Button(actionLabel, action: action)
            }
        }
    }
}
