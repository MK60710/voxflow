import AVFoundation
import Foundation
import Speech
import os.log
import VoxFlowCore

private let appleSpeechLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "AppleSpeech")

/// S5b local fallback: transcribes via Apple's on-device `SpeechAnalyzer`/
/// `SpeechTranscriber` (the `Speech` framework, macOS 26+) — zero key, zero
/// rate limit, works fully offline. Locale fixed to en-US (Mihir's setup;
/// `docs/reference-report.md` §STT names this path as the free-tier
/// rug-pull insurance). API shapes were verified directly against this
/// machine's real SDK this session via standalone `swiftc -typecheck`
/// probes — not guessed from memory, since this framework postdates this
/// assistant's training data — and cross-checked against VoiceInk's
/// `NativeAppleTranscriptionService.swift` (GPL-3.0, pattern only, per
/// `references/VoiceInk/LICENSE`; no code copied, only the API call shape).
///
/// Does NOT auto-trigger the one-time language-asset download from inside
/// `transcribe()` — a ~1GB download mid-dictation would make the very first
/// fallback attempt hang unpredictably, which this repo's error-surface
/// philosophy explicitly rejects ("never fail silently or hang"). Instead
/// this throws a clear `.localEngineUnavailable` if the asset isn't
/// installed yet; `AppleSpeechAssetInstaller` handles the actual download
/// separately, once, in the background at app launch (Mihir approved the
/// download — see PROGRESS.md's S5b entry) — by the time this engine is
/// ever needed as a real fallback, the asset should already be there.
final class AppleSpeechTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    enum EngineError: Error {
        case resultStreamTimedOut
    }

    private let localeIdentifier: String

    init(localeIdentifier: String = "en-US") {
        self.localeIdentifier = localeIdentifier
    }

    /// `biasPrompt` (the S8 dictionary hook) is accepted for `TranscriptionEngine`
    /// conformance but deliberately NOT applied here: no Apple Speech
    /// vocabulary-biasing API was found or verified during this session's
    /// reference research (VoiceInk's own reference code has no such
    /// usage either). Flagged here as a known, honest gap rather than a
    /// fabricated API call — see PROGRESS.md's S5b entry.
    /// **Added 2026-09-09**, a real diagnostic gap: this engine never
    /// logged anything on ANY of its own failure paths, only on success —
    /// so when a live dictation's failover chain gave up entirely (Groq
    /// timed out, chain surfaces Groq's error per the first-error-wins
    /// fix), there was no way to tell from the log whether Apple Speech was
    /// even reached, let alone why it also failed. This thin wrapper
    /// guarantees every failure path (present or future) logs exactly once,
    /// without having to touch each individual `throw` site below.
    func transcribe(audioFileURL: URL, biasPrompt: String?) async throws -> TranscriptionResult {
        do {
            return try await performTranscribe(audioFileURL: audioFileURL, biasPrompt: biasPrompt)
        } catch {
            os_log(.error, log: appleSpeechLog, "Local transcription failed: %{public}@", String(describing: error))
            throw error
        }
    }

    private func performTranscribe(audioFileURL: URL, biasPrompt: String?) async throws -> TranscriptionResult {
        _ = biasPrompt

        guard let supportedLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: localeIdentifier)
        ) else {
            throw TranscriptionEngineError.localEngineUnavailable("locale \(localeIdentifier) not supported by Apple Speech")
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        try await ensureReady(transcriber: transcriber, locale: supportedLocale)

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: audioFileURL)
        } catch {
            throw TranscriptionEngineError.malformedResponse("Couldn't read the recorded audio file")
        }
        let audioDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        let modules: [any SpeechModule] = [transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        let resultTask = Task<String, Error> {
            var transcript = ""
            for try await result in transcriber.results {
                transcript += String(result.text.characters)
            }
            return transcript
        }

        do {
            let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile)
            guard let lastSampleTime else {
                resultTask.cancel()
                await analyzer.cancelAndFinishNow()
                throw TranscriptionEngineError.malformedResponse("Apple Speech received no audio samples")
            }
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } catch let error as TranscriptionEngineError {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw TranscriptionEngineError.malformedResponse("Apple Speech analysis failed: \(error.localizedDescription)")
        }

        // Timeout heuristic ported from VoiceInk's `waitForResultStream`
        // (same reference file, GPL-3.0 pattern only): scales with audio
        // length rather than a flat budget, since on-device analysis of a
        // longer recording genuinely takes longer.
        let resultTimeoutSeconds = max(20.0, audioDuration * 4.0 + 10.0)
        let text: String
        do {
            text = try await waitForResult(resultTask, timeoutSeconds: resultTimeoutSeconds)
        } catch is EngineError {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw TranscriptionEngineError.timedOut
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw TranscriptionEngineError.malformedResponse("Apple Speech result stream failed: \(error.localizedDescription)")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        os_log(.info, log: appleSpeechLog, "Transcribed %.2fs of audio locally (%d chars)", audioDuration, trimmed.count)
        return TranscriptionResult(text: trimmed, engineName: "apple-speech:\(localeIdentifier)")
    }

    /// Checks the asset is installed (throws the specific reason if not —
    /// see `AppleSpeechAssetStatusMapping`) and reserves the locale for
    /// use, mirroring VoiceInk's `reserveLocaleIfNeeded`: a `false` result
    /// while the asset is already installed isn't a real failure, only
    /// genuine reservation-limit/error cases are.
    private func ensureReady(transcriber: SpeechTranscriber, locale: Locale) async throws {
        let rawStatus = await AssetInventory.status(forModules: [transcriber])
        let mapped: AppleSpeechAssetStatus
        switch rawStatus {
        case .installed: mapped = .installed
        case .supported: mapped = .needsDownload
        case .downloading: mapped = .downloading
        case .unsupported: mapped = .unsupported
        @unknown default: mapped = .unsupported
        }

        guard case .ready = AppleSpeechAssetStatusMapping.readiness(for: mapped) else {
            if case .notReady(let error) = AppleSpeechAssetStatusMapping.readiness(for: mapped) {
                throw error
            }
            throw TranscriptionEngineError.localEngineUnavailable("unknown asset status")
        }

        do {
            let reserved = try await AssetInventory.reserve(locale: locale)
            if !reserved {
                let recheck = await AssetInventory.status(forModules: [transcriber])
                guard recheck == .installed else {
                    throw TranscriptionEngineError.localEngineUnavailable("couldn't reserve the \(localeIdentifier) language asset")
                }
            }
        } catch let error as TranscriptionEngineError {
            throw error
        } catch {
            throw TranscriptionEngineError.localEngineUnavailable("asset reservation failed: \(error.localizedDescription)")
        }
    }

    private func waitForResult(_ resultTask: Task<String, Error>, timeoutSeconds: Double) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await resultTask.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw EngineError.resultStreamTimedOut
            }
            guard let result = try await group.next() else {
                throw EngineError.resultStreamTimedOut
            }
            group.cancelAll()
            return result
        }
    }
}
