@preconcurrency import AVFoundation
import os.log
import VoxFlowCore

private let audioLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "AudioRecorder")

enum AudioRecorderError: LocalizedError {
    case converterCreationFailed
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .converterCreationFailed:
            return "Couldn't set up audio format conversion for the input device."
        case .engineStartFailed(let details):
            return "Couldn't start the audio engine: \(details)"
        }
    }
}

/// Records mic audio on key-down, stops on key-up, and produces a 16 kHz
/// mono Float32 buffer (`MonoPCMBuffer`, VoxFlowCore) — the format
/// Whisper-family STT engines want (S5a). Also writes a WAV copy to disk so
/// the menu's "Play last recording" debug item works before any STT engine
/// exists (blueprint Step 3, task 4), AND so `TranscriptionCoordinator` has
/// a file to upload to Groq.
///
/// **The on-disk WAV is 16-bit signed PCM, not 32-bit float** (perf fix,
/// not a blueprint step — see PROGRESS.md's "WAV 16-bit PCM" entry). The
/// live capture/downsample pipeline below is unchanged: `AVAudioEngine` +
/// `AVAudioConverter` still produce 16 kHz mono **Float32** samples exactly
/// as Step 3 built them, accumulated into `accumulatedSamples`/
/// `MonoPCMBuffer` for `SilenceDetector` and "Play last recording"'s
/// in-memory path untouched. Only the bytes actually written to disk (and
/// therefore uploaded to Groq's `/audio/transcriptions`) are converted to
/// Int16 via `PCM16Conversion`, once, in `stop()` — half the bytes over the
/// wire for the exact same audio, since Whisper-family STT wants 16-bit PCM
/// and gets no benefit from float32 precision on speech.
///
/// Handles `AVAudioEngineConfigurationChange` (AirPods connecting, default
/// device switching mid-recording) by **aborting** the in-flight recording
/// rather than attempting a live restart: resuming into a possibly-different
/// input format mid-buffer is the riskier path for a first cut, and a clean
/// abort + pill message ("device changed, try again") is honest, simple,
/// and never leaves a corrupted buffer half-converted. This is a deliberate
/// Step 3 scope decision, not a shortcut — see PROGRESS.md.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var isTapInstalled = false
    private var configChangeObserver: NSObjectProtocol?
    private let samplesLock = NSLock()
    private var accumulatedSamples: [Float] = []

    private(set) var isRecording = false
    private(set) var lastRecordingURL: URL?

    /// Fires on key-up once the buffer is finalized. Always called on the
    /// main thread (see `stop()`).
    var onRecordingFinished: (@MainActor (MonoPCMBuffer, URL) -> Void)?
    /// Fires if recording could not start, or was aborted mid-flight.
    /// Always called on the main thread.
    var onRecordingAborted: (@MainActor (String) -> Void)?

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: TargetAudioFormat.sampleRate,
            channels: AVAudioChannelCount(TargetAudioFormat.channelCount),
            interleaved: false
        )!
        observeConfigurationChanges()
    }

    deinit {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        tearDownTap()
        if engine.isRunning {
            engine.stop()
        }
    }

    // MARK: - Permission

    /// `@MainActor`, not just documented as such: the `.granted`/`.denied`/
    /// `@unknown default` branches used to hop through `Task { @MainActor in
    /// ... }` even though the permission state was already known — a real,
    /// avoidable async gap between key-down and `AudioRecorder.start()`
    /// actually being called. If a key-up (release) landed in that gap,
    /// `DictationCoordinator.handleHoldStateChanged`'s `guard
    /// audioRecorder.isRecording else { return }` would see recording as not
    /// yet started and silently drop the release — then the still-pending
    /// `Task` would start recording moments later, after the key was already
    /// up, with nothing left to stop it. Being `@MainActor` here lets the
    /// already-`@MainActor` call site (`DictationCoordinator`) invoke this
    /// synchronously, so for the common already-decided cases (`.granted`,
    /// the overwhelming majority of real usage after first grant; `.denied`)
    /// `completion` runs inline, in the same synchronous call stack as the
    /// key-down event itself — closing the race entirely for those cases,
    /// since nothing else can run on the main thread (including a
    /// subsequent key-up) until that stack unwinds. Only `.undetermined`
    /// (first-ever launch, before the system permission dialog resolves)
    /// still needs an async hop, since it's genuinely waiting on the user.
    @MainActor
    static func requestMicrophonePermissionIfNeeded(completion: @escaping @MainActor (Bool) -> Void) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in completion(granted) }
            }
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Configuration change (device switch mid-recording)

    private func observeConfigurationChanges() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func handleConfigurationChange() {
        guard isRecording else { return }
        os_log(.info, log: audioLog, "Audio engine configuration changed mid-recording (device switch / AirPods) — aborting")
        abortRecording(reason: "Audio device changed — recording stopped, try again")
    }

    // MARK: - Warm-up (perf fix — see PROGRESS.md "~2s audio-engine cold start")

    /// Primes CoreAudio's input hardware once, at app launch, off the
    /// hotkey path — not a blueprint step. A live log confirmed the first
    /// `engine.start()` in the process's lifetime pays a real hardware-
    /// acquisition cost (CoreAudio HAL/IO-thread spin-up is a documented
    /// once-per-process cost, not a once-per-`start()` cost); every start
    /// after that first one is fast. Without this, that ~2s cost landed on
    /// the user's very first hold-to-talk press instead of at launch where
    /// nobody's waiting on it.
    ///
    /// Installs a real tap (mirrors `start()`'s exact input-acquisition
    /// path) but discards every buffer instead of accumulating it, then
    /// stops immediately — no sample is kept, no file is written,
    /// `onRecordingFinished`/`onRecordingAborted` never fire, and
    /// `isRecording` never flips to true, so a warm-up can never be
    /// mistaken for or collide with a real recording. Synchronous start-
    /// then-stop, deliberately not deferred: an async teardown here would
    /// capture `self` across an actor boundary for no real benefit — the
    /// cost this fixes is `engine.start()`'s one-time hardware-acquisition
    /// call itself, which already happens (and is already paid for)
    /// synchronously before `stop()` runs.
    func warmUp() {
        guard !isRecording else { return }
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { _, _ in
            // Deliberately discarded — warm-up never accumulates samples.
        }

        engine.prepare()
        do {
            try engine.start()
            engine.stop()
            inputNode.removeTap(onBus: 0)
            os_log(.info, log: audioLog, "Audio engine warmed up at launch")
        } catch {
            inputNode.removeTap(onBus: 0)
            os_log(.info, log: audioLog, "Audio engine warm-up failed (non-fatal — first real recording will pay the cold-start cost instead): %{public}@", error.localizedDescription)
        }
    }

    // MARK: - Recording

    func start() throws {
        guard !isRecording else { return }
        samplesLock.withLock { accumulatedSamples.removeAll(keepingCapacity: true) }
        converter = nil

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.converterCreationFailed
        }
        self.converter = converter

        // The WAV file itself isn't written until `stop()` (see comment
        // there) — this just reserves the destination path. No file exists
        // on disk between `start()` and `stop()`.
        let url = Self.newRecordingURL()
        lastRecordingURL = url

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer, inputFormat: inputFormat)
        }
        isTapInstalled = true

        engine.prepare()
        do {
            try startEngineWithOneRetry()
        } catch {
            tearDownTap()
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }

        isRecording = true
        os_log(.info, log: audioLog, "Recording started (input: %.0f Hz, %d ch)", inputFormat.sampleRate, inputFormat.channelCount)
    }

    /// **Added 2026-09-08**, a real incident: `engine.start()` threw a
    /// generic CoreAudio error (`avfaudio error 2003329396`, i.e. `'what'`
    /// — no more specific reason given) mid-session with no other change
    /// around it; the very next hotkey press, seconds later, started
    /// cleanly. That shape — a bare, unexplained CoreAudio failure that
    /// clears itself moments later — is a transient hardware-acquisition
    /// hiccup, not a real unrecoverable state, so retrying once beats
    /// wasting the entire hotkey press over it.
    ///
    /// A blocking `Thread.sleep`, deliberately not an async retry: this
    /// whole call stack (key-down → permission check → `start()`) is
    /// synchronous specifically to close the key-up race documented on
    /// `requestMicrophonePermissionIfNeeded` above — a real key-up landing
    /// during an async retry gap would be silently dropped the same way.
    /// 200ms of blocked main thread on the rare failure path is a better
    /// trade than reopening that race.
    private func startEngineWithOneRetry() throws {
        do {
            try engine.start()
        } catch {
            os_log(.info, log: audioLog, "engine.start() failed (%{public}@) — retrying once", error.localizedDescription)
            Thread.sleep(forTimeInterval: 0.2)
            try engine.start()
        }
    }

    /// Stops the engine and hands back the finished buffer via
    /// `onRecordingFinished`. Order matters: `tearDownTap()` synchronously
    /// removes the tap (AVAudioEngine guarantees no further callbacks fire
    /// after `removeTap` returns) *before* we read `accumulatedSamples`, so
    /// the read always sees the final, fully-written buffer with no race
    /// against the audio I/O thread.
    ///
    /// The on-disk WAV write happens here, once, as 16-bit PCM: the whole
    /// recording's Float32 samples (already fully accumulated in memory —
    /// this was true even before this fix, since `MonoPCMBuffer` always
    /// needed the complete buffer) are converted via `PCM16Conversion` and
    /// encoded via `WAVEncoder.encode(pcm16Samples:sampleRate:)` — the same
    /// WAV-header code already used and tested for the "Test Groq
    /// connection" synthetic audio. This replaces the old per-buffer
    /// `AVAudioFile` streaming write (which wrote Float32 straight through);
    /// batching to one write at `stop()` is not a behavior change in what's
    /// captured, only in when/how the bytes hit disk.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        tearDownTap()
        if engine.isRunning {
            engine.stop()
        }

        let samples = samplesLock.withLock { accumulatedSamples }

        guard let url = lastRecordingURL else { return }
        let buffer = MonoPCMBuffer(samples: samples, sampleRate: TargetAudioFormat.sampleRate)
        os_log(.info, log: audioLog, "Recording stopped: %.2fs, %d samples", buffer.duration, samples.count)

        let pcm16Samples = PCM16Conversion.convert(samples)
        let wavData = WAVEncoder.encode(pcm16Samples: pcm16Samples, sampleRate: buffer.sampleRate)
        do {
            try wavData.write(to: url, options: .atomic)
        } catch {
            os_log(.error, log: audioLog, "Recording file write failed: %{public}@", error.localizedDescription)
        }

        let handler = onRecordingFinished
        MainActor.assumeIsolated {
            handler?(buffer, url)
        }
    }

    private func abortRecording(reason: String) {
        isRecording = false
        tearDownTap()
        if engine.isRunning {
            engine.stop()
        }
        samplesLock.withLock { accumulatedSamples.removeAll(keepingCapacity: false) }
        // No WAV file exists yet at this point (it's only written in
        // `stop()`, not incrementally) — nothing to remove from disk.
        let handler = onRecordingAborted
        MainActor.assumeIsolated {
            handler?(reason)
        }
    }

    private func tearDownTap() {
        guard isTapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    /// Runs on the audio engine's realtime I/O thread — must stay
    /// allocation-light and never touch AppKit/main-actor state directly.
    private func processInputBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return
        }

        var conversionError: NSError?
        var suppliedInput = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil else {
            os_log(.error, log: audioLog, "Audio conversion failed: %{public}@", conversionError?.localizedDescription ?? "unknown")
            return
        }
        guard outputBuffer.frameLength > 0, let channelData = outputBuffer.floatChannelData else {
            return
        }

        // Defensive guard, not a control-flow branch: this should always be
        // true since outputBuffer was allocated with targetFormat. This is
        // exactly the "never crash on format mismatch" check the blueprint
        // calls for — if it ever trips (exotic converter edge case), drop
        // the buffer instead of appending malformed samples.
        guard AudioBufferConversion.matchesTargetFormat(
            sampleRate: outputBuffer.format.sampleRate,
            channelCount: Int(outputBuffer.format.channelCount)
        ) else {
            os_log(.error, log: audioLog, "Converted buffer format mismatch — dropping")
            return
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        samplesLock.withLock { accumulatedSamples.append(contentsOf: samples) }
    }

    private static func newRecordingURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("voxflow-\(UUID().uuidString).wav")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
