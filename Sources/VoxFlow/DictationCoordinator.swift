import AppKit
import AVFoundation
import os.log
import VoxFlowCore

private let coordinatorLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "Coordinator")

/// Wires `HotkeyManager` (S3) to `AudioRecorder` (S3), and both to the
/// menu-bar icon + floating pill. Future steps extend this: S4 adds
/// `TextInserter`, S5a adds `TranscriptionEngine` — see
/// docs/architecture.md → "Components and data flow".
///
/// Owned as a singleton (`shared`) so both `AppDelegate` (starts it) and the
/// SwiftUI menu (`MenuContent`, observes it) refer to the same instance.
@MainActor
final class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    // Shared with TextInsertionCoordinator (Step 4) — one floating pill for
    // the whole pipeline, not one per coordinator. See RecordingPill.swift.
    private let pill = RecordingPillController.shared
    private var audioPlayer: AVAudioPlayer?
    private var abortDismissWorkItem: DispatchWorkItem?
    // S5a: captured at key-PRESS (not insertion-request time) — see
    // docs/architecture.md's "Engine protocols" + PROGRESS.md's Step 4
    // deviations note. `keyReleaseTime` is stage 1 of the latency
    // instrumentation the blueprint's Step 5a task 2 asks for.
    private var frontmostAppAtKeyPress: NSRunningApplication?
    private var keyReleaseTime: Date?
    // Step 6 raw-mode modifier (task 3): Shift's state at the exact
    // flagsChanged event that released Right Option — see
    // `HotkeyManager.onHoldStateChanged`'s updated doc comment.
    private var shiftHeldAtKeyRelease = false
    // Tap-to-toggle (2026-08-13): true from the moment Space is pressed
    // while the hotkey is held, until the NEXT hotkey press stops it.
    // While true, releasing the hotkey does NOT stop recording — see
    // `handleHoldStateChanged`.
    private var isToggleRecording = false
    private var toggleSafetyTimer: DispatchWorkItem?
    /// Matches Wispr Flow's own cap (confirmed with Mihir before building:
    /// an unbounded toggle-recording session is a real risk — a missed
    /// stop-tap, focus loss, anything — with no natural end otherwise).
    private static let toggleSafetyTimeoutSeconds: TimeInterval = 8 * 60

    @Published private(set) var indicatorState: RecordingIndicatorState = .idle
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var lastRecordingDuration: TimeInterval?

    private init() {}

    func start() {
        audioRecorder.onRecordingFinished = { [weak self] buffer, url in
            self?.handleRecordingFinished(buffer: buffer, url: url)
        }
        audioRecorder.onRecordingAborted = { [weak self] reason in
            self?.handleRecordingAborted(reason: reason)
        }

        hotkeyManager.onHoldStateChanged = { [weak self] isDown, shiftHeld in
            self?.handleHoldStateChanged(isDown: isDown, shiftHeld: shiftHeld)
        }
        hotkeyManager.onSecureInputStateChanged = { [weak self] isActive in
            self?.handleSecureInputChanged(isActive: isActive)
        }
        hotkeyManager.onToggleModeRequested = { [weak self] in
            self?.handleToggleModeRequested()
        }

        // Perf fix (PROGRESS.md "~2s audio-engine cold start"): pay
        // CoreAudio's once-per-process hardware-acquisition cost now,
        // instead of on the user's first hold-to-talk press. Gated on
        // permission already being `.granted` — if it's `.undetermined` or
        // `.denied`, warming up would either trigger an unexpected mic
        // prompt before the user ever touches the hotkey or just fail
        // outright; either way, the first real press already handles both
        // cases correctly on its own via `requestMicrophonePermissionIfNeeded`.
        if AVAudioApplication.shared.recordPermission == .granted {
            audioRecorder.warmUp()
        }

        // Trigger the system's Accessibility prompt (if undecided) before we
        // ever try our own guidance alert — Accessibility is what the NSEvent
        // hotkey monitors need.
        HotkeyManager.requestAccessibilityPermission()

        // Monitors install unconditionally now (see HotkeyManager); start()
        // never throws — it reports whether the permission the monitors need
        // is currently granted. Either way the monitors are live and will
        // fire the moment permission appears.
        let permissionGranted = hotkeyManager.start()
        if permissionGranted {
            // Persistent "Ready" pill (2026-07-27) — constant confirmation
            // VoxFlow is live and listening, and the baseline the
            // hold-to-talk states swap in and out of.
            setIndicatorState(.idle)
        } else {
            os_log(.error, log: coordinatorLog, "Hotkey permission not yet granted — monitors installed, showing guidance")
            setIndicatorState(.permissionNeeded)
            presentPermissionGuidanceAlert()
        }
    }

    // MARK: - Hold-to-talk

    private func handleHoldStateChanged(isDown: Bool, shiftHeld: Bool) {
        if isDown {
            // Tap-to-toggle: a toggle session is active, so THIS press is
            // the stop signal, not a request to start a new recording —
            // `audioRecorder.isRecording` is still true from before (the
            // earlier release was suppressed below), so the normal start
            // path must not run.
            guard !isToggleRecording else {
                stopToggleRecording()
                return
            }
            guard indicatorState != .secureInputBlocked else { return }
            // Capture NOW — at key-press, before recording/permission checks
            // — so S5a's insertion focus-guard reflects where Mihir was
            // looking when he started talking, not wherever focus drifted
            // to by the time transcription comes back.
            frontmostAppAtKeyPress = NSWorkspace.shared.frontmostApplication
            AudioRecorder.requestMicrophonePermissionIfNeeded { [weak self] granted in
                guard let self else { return }
                guard granted else {
                    self.setIndicatorState(.permissionNeeded)
                    return
                }
                do {
                    try self.audioRecorder.start()
                    self.setIndicatorState(.recording)
                } catch {
                    os_log(.error, log: coordinatorLog, "Recording failed to start: %{public}@", error.localizedDescription)
                    self.presentAbortedState(reason: "Couldn't start recording")
                }
            }
        } else {
            guard audioRecorder.isRecording else { return }
            // Tap-to-toggle: releasing the hotkey does NOT stop recording
            // once toggle mode is engaged — the recording keeps going until
            // the next hotkey press (handled above) or the safety timeout.
            guard !isToggleRecording else { return }
            keyReleaseTime = Date()
            // Step 6 task 3: Shift held at THIS release means "raw mode" —
            // bypass cleanup entirely for this utterance. Captured here,
            // read by handleRecordingFinished below once the buffer is
            // ready, then reset for the next utterance.
            shiftHeldAtKeyRelease = shiftHeld
            audioRecorder.stop()
        }
    }

    // MARK: - Tap-to-toggle (2026-08-13)

    /// Fires when Space is pressed while the hotkey is held — converts the
    /// ALREADY-IN-PROGRESS hold-recording (started normally above) into a
    /// toggle session that survives the hotkey's release.
    private func handleToggleModeRequested() {
        guard audioRecorder.isRecording, !isToggleRecording else { return }
        isToggleRecording = true
        os_log(.info, log: coordinatorLog, "Toggle mode engaged — recording continues after hotkey release")
        setIndicatorState(.toggleRecording)
        scheduleToggleSafetyTimeout()
    }

    private func scheduleToggleSafetyTimeout() {
        toggleSafetyTimer?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isToggleRecording else { return }
            os_log(.info, log: coordinatorLog, "Toggle recording hit the %.0f-minute safety cap — auto-stopping", Self.toggleSafetyTimeoutSeconds / 60)
            self.stopToggleRecording()
        }
        toggleSafetyTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.toggleSafetyTimeoutSeconds, execute: workItem)
    }

    private func stopToggleRecording() {
        resetToggleState()
        guard audioRecorder.isRecording else { return }
        keyReleaseTime = Date()
        shiftHeldAtKeyRelease = false
        audioRecorder.stop()
    }

    private func handleRecordingFinished(buffer: MonoPCMBuffer, url: URL) {
        lastRecordingURL = url
        lastRecordingDuration = buffer.duration
        setIndicatorState(.idle)

        // Stage 1 of S5a's latency instrumentation: fall back to "now" only
        // if somehow no release timestamp was captured (shouldn't happen —
        // stop() is always preceded by setting keyReleaseTime above).
        let releaseTime = keyReleaseTime ?? Date()
        let expectedApp = frontmostAppAtKeyPress
        let rawModeRequested = shiftHeldAtKeyRelease
        keyReleaseTime = nil
        frontmostAppAtKeyPress = nil
        shiftHeldAtKeyRelease = false

        // Local pre-check added after Step 5a's real-API verification found
        // Groq's server-side hallucination filter doesn't catch true
        // silence: a 1.5s all-zero WAV came back "Thank you." with
        // no_speech_prob 0. Catching it here (from the samples we already
        // have) skips the network call entirely instead of relying on a
        // signal that's demonstrably unreliable for this exact case — see
        // VoxFlowCore.SilenceDetector's doc comment + PROGRESS.md.
        guard !SilenceDetector.isSilent(buffer.samples) else {
            os_log(.info, log: coordinatorLog, "Buffer is near-silent (peak below threshold) — skipping transcription")
            presentTranscriptionNotice("No speech detected", isError: false)
            return
        }

        // Second, ORTHOGONAL pre-network guard (2026-08-13, real incident:
        // rapidly tapping the hotkey produced 20+ Whisper-hallucinated
        // "Thank you."-style insertions) — a quick tap can carry enough
        // room noise to clear the amplitude check above while still having
        // no real speech in it. Duration catches what amplitude can't.
        guard !MinimumUtteranceDurationGuard.isTooShortForRealSpeech(buffer.duration) else {
            os_log(.info, log: coordinatorLog, "Buffer too short for real speech (%.2fs) — skipping transcription", buffer.duration)
            presentTranscriptionNotice("Too short — hold a little longer", isError: false)
            return
        }

        os_log(.info, log: coordinatorLog, "Buffer ready: %.2fs (%d samples) — handing off to TranscriptionCoordinator", buffer.duration, buffer.samples.count)
        setIndicatorState(.transcribing)
        TranscriptionCoordinator.shared.transcribeAndInsert(
            audioFileURL: url,
            keyReleaseTime: releaseTime,
            expectedFrontmostApp: expectedApp,
            rawModeRequested: rawModeRequested,
            audioDuration: buffer.duration
        )
    }

    private func handleRecordingAborted(reason: String) {
        // A real edge case, not just theoretical: if this fires while a
        // toggle session is active (e.g. an audio device change aborts the
        // recording), `isToggleRecording` would otherwise stay stuck true
        // forever — the NEXT normal hold-to-talk press would then be
        // misread as "stop the toggle session" instead of starting a new
        // recording, since `audioRecorder.isRecording` is already false by
        // then and there's nothing left to stop.
        resetToggleState()
        presentAbortedState(reason: reason)
    }

    private func handleSecureInputChanged(isActive: Bool) {
        if isActive {
            if audioRecorder.isRecording {
                audioRecorder.stop()
            }
            // Same reasoning as `handleRecordingAborted` above — Secure
            // Input engaging ends the recording outside the normal
            // toggle-stop path, so the flag must be cleared here too.
            resetToggleState()
            setIndicatorState(.secureInputBlocked)
        } else if indicatorState == .secureInputBlocked {
            setIndicatorState(.idle)
        }
    }

    private func resetToggleState() {
        isToggleRecording = false
        toggleSafetyTimer?.cancel()
        toggleSafetyTimer = nil
    }

    private func setIndicatorState(_ newState: RecordingIndicatorState) {
        abortDismissWorkItem?.cancel()
        indicatorState = newState
        pill.show(newState)
    }

    private func presentAbortedState(reason: String) {
        setIndicatorState(.aborted(reason: reason))
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if case .aborted = self.indicatorState {
                self.setIndicatorState(.idle)
            }
        }
        abortDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    /// Called by `TranscriptionCoordinator` once a dictation's pipeline has
    /// handed off to insertion (or, for a recognized command/snippet, has
    /// otherwise concluded) — returns the pill from `.transcribing` to the
    /// persistent `.idle` "Ready" state. Guarded on the CURRENT state
    /// actually being `.transcribing` so a stray/late call can't stomp a
    /// state that changed for an unrelated reason in the meantime (e.g.
    /// Secure Input engaging mid-transcription).
    func dictationFinished() {
        if case .transcribing = indicatorState {
            setIndicatorState(.idle)
        }
    }

    // MARK: - Transcription notices (S5a)

    /// Entry point `TranscriptionCoordinator` uses to surface STT outcomes
    /// through the same pill Step 3/4 already built — "never fail silently"
    /// per the blueprint's error-surface requirement. Errors reuse the
    /// existing `.aborted(reason:)` state (pill + menu status line + 3s
    /// auto-dismiss, all already wired); non-error notices (e.g. "No speech
    /// detected") show the pill directly without flipping the menu bar icon
    /// to its warning glyph, since silence isn't a failure.
    func presentTranscriptionNotice(_ message: String, isError: Bool) {
        if isError {
            presentAbortedState(reason: message)
            return
        }
        abortDismissWorkItem?.cancel()
        pill.show(message: message, isError: false, onClick: nil)
        let workItem = DispatchWorkItem { [weak self] in
            // Return to the persistent "Ready" pill rather than hiding it.
            self?.setIndicatorState(.idle)
        }
        abortDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    // MARK: - Debug affordance

    func playLastRecording() {
        guard let url = lastRecordingURL else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            player.play()
        } catch {
            os_log(.error, log: coordinatorLog, "Playback failed: %{public}@", error.localizedDescription)
        }
    }

    // MARK: - Permission guidance

    /// **Stale-text bug fixed 2026-08-12 (Step 11a):** this alert said
    /// "Input Monitoring" and deep-linked to `Privacy_ListenEvent` even
    /// though `HotkeyManager.hotkeyPermissionGranted()` has checked
    /// ACCESSIBILITY (`AXIsProcessTrusted`) since 2026-07-30 — the switch
    /// from `CGEventTap` to `NSEvent` monitors changed which permission is
    /// actually needed, but this alert (and the menu's matching status
    /// line in `VoxFlowApp.swift`) never got updated to match, so it was
    /// sending users to the wrong System Settings pane. Now matches
    /// `TextInsertionCoordinator.presentAccessibilityGuidanceAlert`'s
    /// already-correct wording/deep-link exactly.
    private func presentPermissionGuidanceAlert() {
        let alert = NSAlert()
        alert.messageText = "VoxFlow needs Accessibility permission"
        alert.informativeText = "Open System Settings → Privacy & Security → Accessibility, enable VoxFlow, then relaunch it."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
