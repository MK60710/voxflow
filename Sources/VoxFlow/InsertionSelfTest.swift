import AppKit
import ApplicationServices
import os.log
import VoxFlowCore

private let selfTestLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "InsertionSelfTest")

/// A measurement harness for the still-open "dictated text sometimes doesn't
/// land in the target app" bug (2026-07-26/27). The failure is intermittent
/// and timing-dependent, and every hypothesis tested so far rested on one or
/// two ambiguous live samples. This fires the REAL insertion path many times
/// in a row and AUTO-VERIFIES each one via the Accessibility API — reading
/// the target text field's contents back to see whether the marker actually
/// arrived — instead of trusting `SystemTextInserter`'s own "inserted"
/// return (which reports success even when a synthetic Cmd-V lands nowhere,
/// the exact blind spot that made this bug so hard to pin down).
///
/// Runs INSIDE the app on purpose: the whole point is to reproduce the real
/// in-app conditions (menu-tracking state, the CGEvent tap, the focus-guard)
/// that a standalone executable couldn't. It creates its own
/// `SystemTextInserter` — which is stateless (default sub-inserters +
/// override provider) — so it drives byte-for-byte the same code path a real
/// dictation does.
///
/// Usage: focus a plain, AX-readable text field (TextEdit is ideal; Terminal
/// does NOT expose its contents through `AXValue`, so it can't be
/// auto-verified — that limitation is itself worth knowing), then trigger
/// "Run insertion self-test" from the menu. Watch the log
/// (`log stream --predicate 'subsystem == "com.mihirk.voxflow"'`) for the
/// per-attempt `landed=` lines and the final tally; the pill shows the
/// summary too.
@MainActor
enum InsertionSelfTest {
    /// Raw AX attribute strings rather than the `kAX*` CFString constants,
    /// same reasoning as `SystemTextInserter.requestAccessibilityPermission`:
    /// Swift 6 flags the imported `extern CFStringRef` globals as unsafe
    /// shared mutable state. Apple documents these exact string values.
    private static let axFocusedUIElement = "AXFocusedUIElement"
    private static let axValue = "AXValue"

    /// Seconds to wait after the menu item is clicked before the run starts —
    /// long enough for VoxFlow's own menu to fully close and the previously
    /// frontmost app (e.g. TextEdit) to regain focus, so the run targets it
    /// and not a transient menu window.
    private static let startupSettle: TimeInterval = 2.0

    /// Seconds after each insertion before reading the field back — the
    /// paste has to actually reach and be rendered by the target first.
    private static let postInsertSettle: TimeInterval = 0.5

    /// Gap between attempts, on top of `postInsertSettle`.
    private static let interAttemptGap: TimeInterval = 0.8

    static func run(iterations: Int = 10) {
        let inserter = SystemTextInserter()

        RecordingPillController.shared.show(
            message: "Self-test in \(Int(startupSettle))s — focus a text field (TextEdit)",
            isError: false,
            onClick: nil
        )

        Task {
            try? await Task.sleep(nanoseconds: UInt64(startupSettle * 1_000_000_000))

            let target = NSWorkspace.shared.frontmostApplication
            os_log(
                .info, log: selfTestLog,
                "Self-test start — target app: %{public}@ (pid %d), %d iterations",
                target?.bundleIdentifier ?? "nil", target?.processIdentifier ?? -1, iterations
            )

            guard readFocusedText() != nil else {
                os_log(.error, log: selfTestLog, "Self-test aborted — can't read the focused element via AX. Focus a plain text field (TextEdit); Terminal is not AX-readable.")
                RecordingPillController.shared.show(
                    message: "Self-test: target not AX-readable — use TextEdit",
                    isError: true,
                    onClick: nil
                )
                return
            }

            var landedCount = 0
            for index in 1...iterations {
                // Unique, ordered, visually distinct, one per line so a human
                // can also eyeball TextEdit afterward as a cross-check.
                let marker = "VXT-\(index)-\(UUID().uuidString.prefix(4))"

                let outcome = await inserter.insert(marker + "\n", expectedFrontmostApp: target)
                try? await Task.sleep(nanoseconds: UInt64(postInsertSettle * 1_000_000_000))

                // Verify by polling the AX read until it STABILIZES rather
                // than trusting a single read — the previous single-shot read
                // raced TextEdit and returned transient-empty values (e.g.
                // "33→0"), producing false negatives in the count. A unique
                // marker means substring presence alone is sufficient; no
                // before/after diff needed.
                let landed = await markerLanded(marker)
                if landed { landedCount += 1 }

                os_log(
                    .info, log: selfTestLog,
                    "attempt %d/%d — landed=%{public}@ outcome=%{public}@ marker=%{public}@",
                    index, iterations, String(landed), String(describing: outcome), marker
                )

                try? await Task.sleep(nanoseconds: UInt64(interAttemptGap * 1_000_000_000))
            }

            os_log(
                .info, log: selfTestLog,
                "Self-test done — %d/%d actually landed (auto-verified via AX)",
                landedCount, iterations
            )
            RecordingPillController.shared.show(
                message: "Self-test: \(landedCount)/\(iterations) landed",
                isError: landedCount < iterations,
                onClick: nil
            )
        }
    }

    /// Polls the focused field until the read stabilizes, then reports
    /// whether `marker` is present — robust against the transient-empty AX
    /// reads that made a single-shot check miscount. Retries up to ~2s: a
    /// marker that truly landed will be found well before then; one that
    /// never landed reads a stable field without it and returns false.
    private static func markerLanded(_ marker: String) async -> Bool {
        for _ in 0..<10 {
            if let text = readFocusedText(), text.contains(marker) {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return false
    }

    /// Reads the system-wide focused UI element's text via the Accessibility
    /// API. Returns `nil` if there's no focused element, it isn't an
    /// `AXUIElement`, or it doesn't expose a String `AXValue` (e.g. Terminal,
    /// or a non-text control) — callers treat `nil` as "can't verify here".
    private static func readFocusedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, axFocusedUIElement as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        // Safe: the CFTypeID check above proves this is an AXUIElement.
        let element = focusedRef as! AXUIElement
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, axValue as CFString, &valueRef) == .success,
              let text = valueRef as? String else {
            return nil
        }
        return text
    }
}
