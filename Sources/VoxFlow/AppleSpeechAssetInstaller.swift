import Foundation
import Speech
import os.log
import VoxFlowCore

private let assetInstallerLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "AppleSpeechAsset")

/// Triggers the one-time Apple Speech en-US language-asset download in the
/// background at app launch — Mihir approved this download explicitly
/// before S5b was built (~1GB, OS-managed, see PROGRESS.md's S5b entry).
/// Deliberately NOT triggered from inside `AppleSpeechTranscriptionEngine
/// .transcribe()` — see that file's doc comment for why a mid-dictation
/// download would be bad UX. Doing it here means that by the time the
/// local engine is ever actually needed as a real fallback, the asset
/// should already be installed.
enum AppleSpeechAssetInstaller {
    static let localeIdentifier = "en-US"

    /// Fire-and-forget, non-blocking, non-fatal on failure — mirrors
    /// `GroqConnectionWarmup.warmUpIfConfigured()`'s exact shape (same
    /// launch-time warm-up philosophy, same "failure just means the first
    /// real use pays the cost this was meant to avoid" reasoning).
    static func installIfNeededInBackground() {
        Task.detached(priority: .utility) {
            do {
                try await installIfNeeded()
            } catch {
                os_log(.info, log: assetInstallerLog, "Apple Speech asset install check failed (non-fatal): %{public}@", error.localizedDescription)
            }
        }
    }

    /// Not `private`: also called directly (awaited, not fire-and-forget)
    /// by the `VOXFLOW_SELFTEST_LOCAL_STT_PATH` launch hook in
    /// `VoxFlowApp.swift`, so a headless verification run can be sure the
    /// asset is actually installed before attempting a real transcription,
    /// rather than racing the background install.
    static func installIfNeeded() async throws {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: localeIdentifier)
        ) else {
            os_log(.info, log: assetInstallerLog, "Locale %{public}@ not supported by Apple Speech on this OS", localeIdentifier)
            return
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .installed else {
            os_log(.info, log: assetInstallerLog, "Apple Speech %{public}@ asset already installed", localeIdentifier)
            return
        }

        os_log(.info, log: assetInstallerLog, "Apple Speech %{public}@ asset not installed (status: %{public}@) — starting background install", localeIdentifier, String(describing: status))
        let start = Date()
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            os_log(.info, log: assetInstallerLog, "No installation request available for %{public}@ (already installed or unsupported)", localeIdentifier)
            return
        }
        try await request.downloadAndInstall()
        let elapsed = LatencyInstrumentation.milliseconds(from: start, to: Date())
        os_log(.info, log: assetInstallerLog, "Apple Speech %{public}@ asset installed in %dms", localeIdentifier, elapsed)
    }
}
