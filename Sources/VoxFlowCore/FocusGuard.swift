import Foundation

/// Minimal identity used to compare "the app that was frontmost when
/// insertion was requested" against "the app that's frontmost right now",
/// without pulling AppKit's `NSRunningApplication` into VoxFlowCore (same
/// module-boundary convention as AudioBufferConversion.swift). The AppKit
/// glue (`Sources/VoxFlow/TextInserter.swift`) converts a real
/// `NSRunningApplication` to this type at the boundary.
public struct AppIdentity: Equatable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?

    public init(processIdentifier: Int32, bundleIdentifier: String?) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Pure decision logic for Step 4's focus-guard (blueprint task 3): compares
/// the app captured at insertion-REQUEST time against whatever's frontmost
/// right when we're actually about to type. If they differ, insertion must
/// be held (a "click to insert" pill) rather than typed into the wrong
/// window.
///
/// Step 4 captures at insertion-request time (when
/// `TextInsertionCoordinator` is asked to insert). The blueprint notes S5a
/// will instead pass the app captured at HOTKEY-PRESS time — this
/// comparison doesn't need to know which moment its `expected` parameter
/// was captured at, so that later change is purely a caller-side wiring
/// change, not a change to this logic.
public enum FocusGuard {
    /// `true` if it's safe to type now, `false` if the frontmost app has
    /// changed and insertion should be held instead.
    ///
    /// Fails OPEN (returns `true`) when `expected` is `nil` — e.g. if
    /// `NSWorkspace` couldn't report a frontmost app at request time — so a
    /// missing signal never permanently blocks insertion.
    public static func shouldProceed(expected: AppIdentity?, current: AppIdentity?) -> Bool {
        guard let expected else { return true }
        return expected == current
    }
}
