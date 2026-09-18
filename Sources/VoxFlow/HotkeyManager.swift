import AppKit
import ApplicationServices
import Carbon.HIToolbox
import IOKit.hid
import os.log
import VoxFlowCore

private let hotkeyLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "Hotkey")

/// Detects hold/release of VoxFlow's configured hotkey system-wide — which
/// specific modifier key is user-selectable as of Step 11a task 2, via
/// `HotkeyCoordinator.shared.selectedHotkey` (defaults to Right Option,
/// this file's original and only option before Step 11a).
///
/// **2026-07-30 — switched from a `CGEvent` tap to `NSEvent` global + local
/// monitors.** The old `CGEventTapCreate` approach was repeatedly disabled by
/// the OS with `kCGEventTapDisabledByUserInput` on a menu-bar-only agent app
/// (`LSUIElement`): live logging showed Right Option presses producing a tap-
/// disable instead of being delivered, which is why the hotkey only fired
/// while VoxFlow's menu was open (opening it makes VoxFlow active, briefly
/// dodging the disabled-tap state). Neither the fast-callback fix (2026-07-23)
/// nor moving the tap to a dedicated thread (2026-07-29) helped, because the
/// failure was the tap being *disabled*, not slow callbacks or run-loop
/// starvation. `NSEvent`'s monitor API is the higher-level, AppKit-managed
/// mechanism the platform intends for global hotkeys; it is not subject to
/// `tapDisabledByUserInput`:
///
///  - `addGlobalMonitorForEvents` receives copies of events posted to OTHER
///    apps — i.e. exactly when VoxFlow is inactive (the normal case for a
///    hold-to-talk menu-bar app).
///  - `addLocalMonitorForEvents` covers the case where VoxFlow itself is the
///    active app (e.g. its menu or Settings window is open).
///
/// Both require the app to be trusted for Accessibility / Input Monitoring
/// (granted via the same TCC prompt as before) and both are delivered on the
/// main thread, so the `@MainActor` handlers can be called directly (via
/// `MainActor.assumeIsolated`).
///
/// Secure Input mode (password fields, Terminal's Secure Keyboard Entry)
/// blocks global keyboard monitoring the same way it blocked the tap; it has
/// no change notification, so it's polled on a timer to surface the "blocked"
/// pill state.
///
/// `@MainActor` because the `NSEvent` monitors deliver on the main thread and
/// all the state/handlers are main-actor-bound — this also makes `self`
/// `Sendable`, so it can be captured in the monitors' `@Sendable` handler
/// closures.
@MainActor
final class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isHotkeyDown = false
    /// Tracks the chord key (Right Command) independently of the primary
    /// hotkey — needed because tap-to-toggle (below) has to detect the
    /// chord regardless of which key physically registers first when
    /// pressed together.
    private var isChordKeyDown = false
    private var secureInputTimer: Timer?
    private var lastSecureInputState = false

    /// `true` = key held down, `false` = released. `shiftHeld` reflects
    /// whether Shift is ALSO down at the moment of this exact event —
    /// meaningful only on release, where it drives Step 6's "raw mode"
    /// modifier (blueprint task 3: "hold Shift too while releasing the
    /// hotkey → insert raw transcript"). Read directly off the same
    /// `flagsChanged` event that reports the Right Option transition, not a
    /// separate poll, so there's no race between "Shift state" and "the
    /// exact instant Right Option released". Always called on the main thread.
    var onHoldStateChanged: (@MainActor (Bool, Bool) -> Void)?
    /// Fires whenever Secure Input engages/disengages. Always called on the
    /// main thread.
    var onSecureInputStateChanged: (@MainActor (Bool) -> Void)?
    /// Tap-to-toggle mode (2026-08-13/14, Mihir's request, confirmed
    /// against Wispr Flow's own real Fn+Space behavior via screenshot: a
    /// CHORD — press both together, release, recording keeps going until a
    /// single subsequent tap of the hotkey alone).
    ///
    /// **Chord key revised 2026-08-14 from Space to Right Command, Mihir's
    /// direct request, after an extensive live debugging session found
    /// Space's `keyDown` event never once reached this monitor across
    /// dozens of attempts** — even after confirming Input Monitoring was
    /// granted, ruling out Wispr Flow (a competing app with its own
    /// Fn+Space global hotkey) as an interceptor, and confirming the
    /// physical space bar worked fine for normal typing. The remaining,
    /// unconfirmed suspicion was a macOS-level Input Source-switching
    /// shortcut consuming Option+Space before any app ever sees it — not
    /// fully proven, but a modifier key sidesteps the whole question
    /// entirely: unlike Space, a modifier is detected through the exact
    /// same `flagsChanged` mechanism already proven reliable all session
    /// for the primary hotkey itself — no `keyDown`/`keyUp` monitoring
    /// involved anywhere in chord detection anymore.
    ///
    /// **Companion key made same-side-computed 2026-08-24** (was hardcoded
    /// to `.rightCommand`): the companion is now `HotkeyOption
    /// .tapToggleCompanion` — the other Option/Command key on the SAME
    /// side as whichever primary hotkey is configured (Right Option ↔
    /// Right Command, Left Option ↔ Left Command). The old hardcoded
    /// version silently disabled tap-to-toggle entirely whenever Right
    /// Command was picked as the primary hotkey (needed an explicit guard
    /// to avoid the primary and chord checks both firing on the same
    /// physical key) — a real bug Mihir hit live. Fires the instant BOTH
    /// the primary hotkey and its companion are detected down AT THE SAME
    /// TIME, regardless of which one physically registers first — see
    /// `handleFlagsChanged`'s two checks below. `DictationCoordinator`
    /// converts the in-progress hold-recording into a toggle session on
    /// this signal — see its `handleToggleModeRequested`.
    var onToggleModeRequested: (@MainActor () -> Void)?

    /// Installs the monitors (always) and starts secure-input polling.
    /// Returns `true` if the app currently appears to have the permission the
    /// monitors need to actually fire; `false` means the monitors are still
    /// installed but the caller should surface permission guidance. Never
    /// throws — a missing grant is a guidance case, not an install failure.
    @discardableResult
    func start() -> Bool {
        stop()
        installMonitors()
        startSecureInputPolling()
        // Step 11a task 2: if the Settings picker changes the configured
        // hotkey mid-hold, `HotkeyFlagsDecoder` immediately stops matching
        // the OLD key's events (it only checks the newly-selected key's
        // keycode) — without this, the old key's eventual release would go
        // unseen and `DictationCoordinator` would be stuck "recording"
        // forever. Resetting here forces a clean synthetic release the
        // instant the selection changes, same shape as `stop()`'s own.
        HotkeyCoordinator.shared.onSelectionChanged = { [weak self] in
            self?.resetHoldStateIfNeeded()
        }
        return Self.hotkeyPermissionGranted()
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        secureInputTimer?.invalidate()
        secureInputTimer = nil
        resetHoldStateIfNeeded()
    }

    /// Synthetic release — no live modifier state to read (monitors torn
    /// down, or the hotkey selection just changed out from under an
    /// in-progress hold), so Shift is reported as not-held. Both call sites
    /// (`stop()`, `HotkeyCoordinator.onSelectionChanged`) are already
    /// `@MainActor`, so the handler is called directly (no
    /// `assumeIsolated` hop needed).
    private func resetHoldStateIfNeeded() {
        // Also clears `isChordKeyDown` unconditionally — monitors tearing
        // down mid-chord (or the hotkey selection changing) shouldn't
        // leave a stale "chord key is down" belief that could misfire a
        // future chord detection after monitors restart.
        isChordKeyDown = false
        guard isHotkeyDown else { return }
        isHotkeyDown = false
        onHoldStateChanged?(false, false)
    }

    // No `deinit` cleanup: `HotkeyManager` is owned by the lifetime-of-app
    // `DictationCoordinator` singleton, so it's never deallocated in
    // practice, and `stop()` (main-actor) is the real teardown path. A
    // nonisolated `deinit` can't touch the `@MainActor` monitor/timer state
    // anyway, and the OS reclaims the monitors on process exit.

    // MARK: - Permission

    /// Whether the hotkey monitors' required permission is granted.
    ///
    /// **2026-07-30 — this checks ACCESSIBILITY (`AXIsProcessTrusted`), not
    /// Input Monitoring.** `NSEvent`'s global keyboard monitors ("key-related
    /// events may only be monitored if the process is trusted for
    /// accessibility", per Apple's docs) need Accessibility, which VoxFlow
    /// already requests for synthetic text insertion (`SystemTextInserter`) —
    /// so this is very likely already granted. The previous
    /// `IOHIDCheckAccess`/Input-Monitoring check was wrong for the `NSEvent`
    /// approach and caused a false "not granted" that suppressed the whole
    /// hotkey.
    static func hotkeyPermissionGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system's Accessibility prompt if undecided (a no-op once
    /// the user has decided). `SystemTextInserter.requestAccessibilityPermission`
    /// already does this at launch for text insertion; kept here so the
    /// hotkey path is self-sufficient if that ever changes. Uses the
    /// documented raw option-key string to sidestep Swift 6's false-positive
    /// data-race diagnostic on the imported `kAXTrustedCheckOptionPrompt`
    /// global (same reasoning as `SystemTextInserter`).
    static func requestAccessibilityPermission() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Event monitors

    /// Installs the monitors UNCONDITIONALLY and never throws. A missing
    /// permission is NOT a reason to skip installation: `addGlobalMonitorForEvents`
    /// returns a monitor that simply doesn't fire until the grant appears, and
    /// gating on a pre-flight check was actively harmful — a rebuild that
    /// momentarily lost the (self-signed, unstable-signature) TCC grant would
    /// leave the monitors uninstalled even after the user re-granted. Callers
    /// check `hotkeyPermissionGranted()` separately to decide whether
    /// to show guidance; the monitors are always present and start delivering
    /// the moment permission is granted.
    private func installMonitors() {
        // Global monitor: events posted to OTHER apps (VoxFlow inactive — the
        // normal hold-to-talk case). Local monitor: events delivered to
        // VoxFlow itself (its menu / Settings window active); it must return
        // the event so it isn't swallowed. Both funnel through `forward`.
        // Back to `.flagsChanged`-only (2026-08-14): the chord key is now
        // Right Command, a modifier — see `onToggleModeRequested`'s doc
        // comment for why this is simpler AND more reliable than the
        // Space-based `keyDown`/`keyUp` approach it replaces.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.forward(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.forward(event)
            return event
        }

        os_log(.info, log: hotkeyLog, "Hotkey monitors installed (global + local, NSEvent)")
    }

    /// Shared body for both monitor closures. `nonisolated` because the
    /// `NSEvent` monitor handlers aren't statically main-actor-isolated, even
    /// though they deliver on the main thread. Extracts the Sendable value
    /// fields (`UInt16`/`UInt`) before hopping via `assumeIsolated`, so the
    /// non-`Sendable` `NSEvent` never crosses an isolation boundary.
    nonisolated private func forward(_ event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.rawValue
        MainActor.assumeIsolated {
            self.handleFlagsChanged(keyCode: keyCode, flags: flags)
        }
    }

    private func handleFlagsChanged(keyCode: UInt16, flags: UInt) {
        // The primary hotkey — reuses the same pure decoder the CGEvent
        // path used, per `HotkeyFlagsDecoder`'s own doc comment.
        if let transition = HotkeyFlagsDecoder.decode(
            keyCode: Int64(keyCode),
            flags: UInt64(flags),
            hotkey: HotkeyCoordinator.shared.selectedHotkey
        ), transition.isDown != isHotkeyDown {
            isHotkeyDown = transition.isDown
            // Ordinary hold-to-talk start/stop always fires first — the
            // chord check below only ADDS toggle-mode on top of a normal
            // recording that's already starting via this same call.
            onHoldStateChanged?(transition.isDown, transition.shiftHeld)

            // Chord detection, hotkey-held-first ordering: the hotkey just
            // went down while the chord key (Right Command) was ALREADY
            // held. The mirror-image ordering is the block below; between
            // the two, either physical press order engages toggle mode.
            if transition.isDown, isChordKeyDown {
                os_log(.info, log: hotkeyLog, "Hotkey pressed while chord key already held — toggle mode requested")
                onToggleModeRequested?()
            }
        }

        // The chord key — decoded via the SAME `HotkeyFlagsDecoder`
        // mechanism, against the primary hotkey's own `tapToggleCompanion`
        // (same-side Option/Command pairing) instead of a fixed
        // `.rightCommand`. **2026-08-24 fix:** the old fixed-`.rightCommand`
        // version needed an explicit guard against the primary hotkey
        // ALSO being Right Command (otherwise this block and the one above
        // would both react to the same physical key, firing toggle mode on
        // every ordinary press) — that guard silently disabled tap-to-toggle
        // entirely whenever Right Command was the chosen primary hotkey, a
        // real bug Mihir hit live. `tapToggleCompanion` makes primary and
        // companion structurally different keys always, so no guard is
        // needed anymore.
        if let chordTransition = HotkeyFlagsDecoder.decode(
            keyCode: Int64(keyCode),
            flags: UInt64(flags),
            hotkey: HotkeyCoordinator.shared.selectedHotkey.tapToggleCompanion
        ), chordTransition.isDown != isChordKeyDown {
            isChordKeyDown = chordTransition.isDown
            if chordTransition.isDown, isHotkeyDown {
                os_log(.info, log: hotkeyLog, "Chord key pressed while hotkey already held — toggle mode requested")
                onToggleModeRequested?()
            }
        }
    }

    // MARK: - Secure Input polling

    /// `IsSecureEventInputEnabled()` has no change notification, so this
    /// polls. 250ms keeps the pill's "blocked" state feeling responsive
    /// without meaningfully taxing the run loop.
    private func startSecureInputPolling() {
        lastSecureInputState = IsSecureEventInputEnabled()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = IsSecureEventInputEnabled()
            guard current != self.lastSecureInputState else { return }
            self.lastSecureInputState = current
            let handler = self.onSecureInputStateChanged
            MainActor.assumeIsolated {
                handler?(current)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        secureInputTimer = timer
    }
}
