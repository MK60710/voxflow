import Foundation

public enum AppInfo {
    public static let version = "0.1.0"
    public static let bundleIdentifier = "com.mihirk.voxflow"
}

/// Canonical latency budget for one dictation, in milliseconds.
/// Owned by docs/architecture.md — keep the two in sync.
public enum LatencyBudget {
    public static let sttMs = 900
    public static let cleanupMs = 600
    public static var totalMs: Int { sttMs + cleanupMs }
}
