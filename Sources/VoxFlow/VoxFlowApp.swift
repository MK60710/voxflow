import SwiftUI
import VoxFlowCore
import os.log

@main
struct VoxFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var coordinator = DictationCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: coordinator.indicatorState.menuBarSymbolName)
        }

        // Step 6 (plans/voxflow-windowed-ui.md) removed the old `Settings`
        // scene + `SettingsView` — every section it held (General,
        // Transcription, Cleanup, Commands, App Tones, Snippets,
        // Dictionary) now lives in the window below instead.

        // Step 2b (plans/voxflow-windowed-ui.md): the real window shell.
        // `Window` (not `WindowGroup`, which is for document-style
        // multi-instance windows) is the SwiftUI-native tool for a single
        // on-demand window — Step 2a live-verified this scene type doesn't
        // auto-open at launch, reopens the same instance instead of
        // duplicating, and doesn't quit the app when closed.
        Window("VoxFlow", id: MainWindowIDs.main) {
            MainWindowContent()
        }
        .defaultSize(width: 800, height: 520)
    }
}

enum MainWindowIDs {
    static let main = "voxflow-main"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app; LSUIElement in Info.plist keeps us out of the Dock.
        DictationCoordinator.shared.start()
        TextInsertionCoordinator.shared.start()
        // Step 11a task 1: first-run onboarding, no-op after the first
        // completion. Shown after the coordinators above so the permission
        // prompts they themselves trigger (Accessibility, mostly) have
        // already fired if this is a genuinely fresh install — onboarding's
        // own "Request Access"/"Open System Settings" buttons handle the
        // rest, including a denied-then-later-granted-in-System-Settings
        // case those synchronous launch-time calls can't.
        OnboardingCoordinator.shared.showIfFirstRun()
        // Step 8: force the dictionary's Application Support load to happen
        // at launch (surfacing any `loadError` early via the log) rather
        // than lazily on the first dictation — `DictionaryCoordinator` has
        // no other `.start()`-shaped side effect, so a bare touch is enough.
        _ = DictionaryCoordinator.shared
        // Bug fix (PROGRESS.md's S5b entry): `TranscriptionCoordinator
        // .init()` no longer calls `refreshEngineStatus()` synchronously
        // (that Keychain read could hang the whole app during SwiftUI's
        // Scene-graph construction — see that file's `init()` doc
        // comment). Deferred one run-loop tick via `DispatchQueue.main
        // .async` so it's safely past that synchronous phase, keeping the
        // menu's "Groq: ..." label accurate without waiting for the user
        // to open the menu first (which already triggers the same
        // refresh via `.onAppear`, redundantly but harmlessly).
        DispatchQueue.main.async {
            TranscriptionCoordinator.shared.refreshEngineStatus()
        }
        // Perf fix (PROGRESS.md "Slow first-request transcription"): warm
        // the TLS connection to Groq now, off the hotkey path, instead of
        // paying DNS+TCP+TLS cold-start on the user's first dictation.
        GroqConnectionWarmup.warmUpIfConfigured()
        // S5b: install the local-fallback language asset in the background
        // now (Mihir approved the ~1GB one-time download) so it's already
        // ready by the time it's ever needed as a real fallback.
        AppleSpeechAssetInstaller.installIfNeededInBackground()

        // S5b headless verification hook — NOT part of normal app launch.
        // Set VOXFLOW_SELFTEST_LOCAL_STT_PATH to a real recorded WAV path
        // to run a one-shot transcription through the ACTUAL production
        // `AppleSpeechTranscriptionEngine` (not a reimplementation), log
        // the result/latency, then quit. Used once this session to verify
        // S5b against a real recording without needing Mihir's hands
        // (asset install + file-based transcription needs no mic/hotkey).
        if let selfTestPath = ProcessInfo.processInfo.environment["VOXFLOW_SELFTEST_LOCAL_STT_PATH"] {
            runLocalSTTSelfTest(audioPath: selfTestPath)
        }
    }

    private func runLocalSTTSelfTest(audioPath: String) {
        let selfTestLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "SelfTestLocalSTT")
        Task {
            do {
                os_log(.info, log: selfTestLog, "Ensuring Apple Speech asset installed…")
                let installStart = Date()
                try await AppleSpeechAssetInstaller.installIfNeeded()
                os_log(.info, log: selfTestLog, "Asset ready after %dms", LatencyInstrumentation.milliseconds(from: installStart, to: Date()))

                let engine = AppleSpeechTranscriptionEngine()
                let start = Date()
                let result = try await engine.transcribe(audioFileURL: URL(fileURLWithPath: audioPath), biasPrompt: nil)
                let elapsed = LatencyInstrumentation.milliseconds(from: start, to: Date())
                os_log(.info, log: selfTestLog, "SELFTEST_RESULT elapsedMs=%d engine=%{public}@ text=%{public}@", elapsed, result.engineName, result.text)
            } catch {
                os_log(.error, log: selfTestLog, "SELFTEST_FAILED error=%{public}@", String(describing: error))
            }
            await NSApp.terminate(nil)
        }
    }
}

/// Step 6 (plans/voxflow-windowed-ui.md): slimmed to status line + "Open
/// VoxFlow" + Quit, per docs/window-ux-plan.md's sign-off — engine health
/// and cleanup status moved into `DictationHomeScreen`; Insights/
/// Transcript Log/Settings/App Tones/Commands/Dictionary/Snippets all
/// live in the window now, reachable via its own sidebar rather than
/// separate dropdown buttons.
struct MenuContent: View {
    @ObservedObject private var coordinator = DictationCoordinator.shared
    @ObservedObject private var hotkey = HotkeyCoordinator.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("VoxFlow \(AppInfo.version)")
        statusLine
        Divider()
        Button("Open VoxFlow") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: MainWindowIDs.main)
        }
        Divider()
        Button("Quit VoxFlow") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var statusLine: some View {
        switch coordinator.indicatorState {
        case .idle:
            if let duration = coordinator.lastRecordingDuration {
                Text(String(format: "Last recording: %.1fs", duration))
                    .foregroundStyle(.secondary)
            } else {
                Text("Hold \(hotkey.selectedHotkey.displayName) anywhere to dictate")
                    .foregroundStyle(.secondary)
            }
        case .recording:
            Text("Recording…")
                .foregroundStyle(.red)
        case .toggleRecording:
            Text("Recording — tap \(hotkey.selectedHotkey.displayName) to stop")
                .foregroundStyle(.red)
        case .transcribing:
            Text("Transcribing…")
                .foregroundStyle(.secondary)
        case .secureInputBlocked:
            Text("Blocked by secure input")
                .foregroundStyle(.orange)
        case .permissionNeeded:
            // Stale-text bug fixed 2026-08-12 — see
            // `DictationCoordinator.presentPermissionGuidanceAlert`'s doc
            // comment: the actual check is Accessibility, not Input
            // Monitoring, since the 2026-07-30 NSEvent-monitor switch.
            Text("Needs Accessibility permission")
                .foregroundStyle(.orange)
        case .aborted(let reason):
            Text(reason)
                .foregroundStyle(.orange)
        }
    }
}
