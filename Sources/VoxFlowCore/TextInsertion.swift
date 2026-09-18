import Foundation

/// Which mechanism actually typed the text — surfaced for logging today and
/// for a future settings/engine-status UI (S11a follows the same shape for
/// STT/cleanup engines).
public enum TextInsertionStrategy: Equatable, Sendable {
    case pasteboardSwap
    case cgEventUnicode
}

/// Result of a `TextInserter.insert` call (protocol lives in
/// `Sources/VoxFlow/TextInserter.swift` since it's AppKit-facing; this
/// outcome type is pure/testable data). The AppKit glue in
/// `Sources/VoxFlow/TextInsertionCoordinator.swift` turns this into pill
/// messages and permission-guidance alerts.
public enum TextInsertionOutcome: Equatable, Sendable {
    case inserted(strategy: TextInsertionStrategy)
    case heldForFocusChange(text: String)
    case accessibilityPermissionNeeded
    case blockedBySecureInput
    case failed(reason: String)
}

/// Per-app override extension point (blueprint Step 4, task 2: "a per-app
/// override map stub — just a stub/protocol point, not a full feature — S7
/// context-awareness will use per-app behavior later"). Step 4 ships a
/// single no-op implementation that always defers to the default strategy
/// (pasteboard-swap); S7 can add a real bundle-ID → strategy map behind this
/// same protocol without touching `TextInserter`'s call sites.
public protocol PerAppInsertionOverrideProviding {
    func preferredStrategy(forBundleIdentifier bundleIdentifier: String?) -> TextInsertionStrategy?
}

/// Step 4's stub implementation: no overrides configured yet.
public struct NoOverridesConfigured: PerAppInsertionOverrideProviding {
    public init() {}

    public func preferredStrategy(forBundleIdentifier bundleIdentifier: String?) -> TextInsertionStrategy? {
        nil
    }
}
