import AppKit
import SwiftUI
import VoxFlowCore

/// Small floating pill shown while recording, and for the
/// secure-input-blocked / permission-needed / aborted states (blueprint
/// Step 3, task 3) — and, from Step 4 onward, for text-insertion states
/// (Accessibility-permission-needed, the focus-guard's "click to insert").
/// Deliberately simple — a plain top-center NSPanel, not a notch-aware
/// multi-layout overlay (see freeflow's RecordingOverlay.swift for that
/// level of polish). S3/S4 scope is "prove the state is visible to Mihir";
/// visual polish is S11a's job.
///
/// Shared as a singleton (`shared`) rather than owned separately by
/// `DictationCoordinator` and `TextInsertionCoordinator` — there is only
/// ever one floating pill on screen, so both halves of the pipeline (input
/// and output) drive the same panel instead of risking two overlapping
/// ones.
@MainActor
final class RecordingPillController {
    static let shared = RecordingPillController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<PillView>?
    private let state = PillState()

    /// Recording-state display (Step 3) — routes through the generic
    /// `show(message:isError:onClick:)` below; recording states never take
    /// a click action.
    func show(_ indicatorState: RecordingIndicatorState) {
        show(message: indicatorState.pillMessage, isError: indicatorState.isErrorState, isIdle: indicatorState.isIdle, onClick: nil)
    }

    /// Generic display added in Step 4 so the same floating pill can also
    /// show text-insertion states without a second, possibly-overlapping
    /// NSPanel. `onClick` is used by the focus-guard's "click to insert"
    /// pill (`TextInsertionCoordinator`); every other caller passes `nil`,
    /// which keeps the panel non-interactive (`ignoresMouseEvents = true`,
    /// same as Step 3's behavior) so it never steals clicks meant for
    /// whatever's underneath.
    func show(message: String?, isError: Bool, isIdle: Bool = false, onClick: (() -> Void)?) {
        guard let message else {
            hide()
            return
        }
        state.message = message
        state.isError = isError
        state.isIdle = isIdle
        state.onClick = onClick
        presentPanelIfNeeded()
        panel?.ignoresMouseEvents = (onClick == nil)
        // Deferred one run-loop tick: `state.message` etc. just changed
        // synchronously above, but SwiftUI's re-render — and therefore
        // `hostingView.fittingSize` reflecting the NEW text — happens on
        // the next tick, not inline with this property mutation.
        DispatchQueue.main.async { [weak self] in
            self?.resizeAndRecenterPanel()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func presentPanelIfNeeded() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let hosting = NSHostingView(rootView: PillView(state: state))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting

        self.hostingView = hosting
        self.panel = panel
        panel.orderFrontRegardless()
    }

    /// Re-measures the pill's actual SwiftUI content and resizes/recenters
    /// the panel to match. Bug fix, not part of the original S3 scope: the
    /// panel used to be sized ONCE, to a hardcoded 240×36, at creation —
    /// nothing forced the SwiftUI content to actually fill that width, so
    /// longer messages ("Recording…", error text) rendered clipped down to
    /// their own intrinsic size, AND the panel's one-time centering math
    /// (built around the assumed 240pt width) no longer matched the real,
    /// narrower rendered capsule — the same root cause behind both the
    /// truncated-text and off-center reports. Re-centering on every call
    /// against the CURRENT content's real width fixes both at once.
    private func resizeAndRecenterPanel() {
        guard let panel, let hostingView else { return }
        let fitting = hostingView.fittingSize
        // Floor keeps short states ("Ready") from rendering as a
        // near-circular blob; ceiling caps how far a pathological long
        // message can stretch the pill — `PillView`'s own `maxWidth` frame
        // keeps SwiftUI's measurement within this same bound already, so
        // this ceiling is a defensive backstop, not the primary limiter.
        let width = min(max(fitting.width, 90), 420)
        let height = max(fitting.height, 32)
        let size = NSSize(width: width, height: height)

        guard let screen = NSScreen.main else {
            panel.setContentSize(size)
            return
        }
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.maxY - size.height - 8
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

@MainActor
private final class PillState: ObservableObject {
    @Published var message: String = ""
    @Published var isError: Bool = false
    /// Idle "Ready" state — rendered dimmer/smaller so an always-on pill
    /// isn't visually heavy.
    @Published var isIdle: Bool = false
    /// Not `@Published`: it doesn't affect what's drawn, only what tapping
    /// the pill does, and closures aren't Equatable/diffable anyway.
    var onClick: (() -> Void)?
}

private struct PillView: View {
    @ObservedObject var state: PillState

    private var iconName: String {
        if state.isError { return "exclamationmark.circle.fill" }
        return state.isIdle ? "waveform" : "waveform.circle.fill"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(state.isError ? Color.red : Color.white)
            Text(state.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Matches `resizeAndRecenterPanel`'s 420pt ceiling — gives SwiftUI
        // the same width budget the AppKit side enforces, so truncation
        // (when it does trigger, only for a genuinely long message) shows
        // a real ellipsis instead of the panel just clipping raw text.
        .frame(maxWidth: 420, alignment: .center)
        // Idle sits quietly at reduced opacity; active/error states are
        // fully opaque so they read clearly the instant they appear.
        .background(Capsule().fill(Color.black.opacity(state.isIdle ? 0.55 : 0.85)))
        .opacity(state.isIdle ? 0.7 : 1.0)
        .contentShape(Capsule())
        .onTapGesture {
            state.onClick?()
        }
    }
}
