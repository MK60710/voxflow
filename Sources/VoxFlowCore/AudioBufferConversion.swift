import Foundation

/// VoxFlow's canonical STT input format: Whisper-family models want 16 kHz
/// mono. Owned here so AudioRecorder and (later) TranscriptionEngine agree
/// on one definition — see docs/architecture.md.
public enum TargetAudioFormat {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1
}

/// A mono, 16 kHz, Float32 PCM audio buffer — the artifact `AudioRecorder`
/// hands to `TranscriptionEngine` (S5a) once a hold-to-talk utterance ends.
public struct MonoPCMBuffer: Equatable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double = TargetAudioFormat.sampleRate) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// Duration in seconds.
    public var duration: TimeInterval {
        AudioBufferConversion.duration(frameCount: samples.count, sampleRate: sampleRate)
    }
}

public enum AudioBufferConversionError: Error, Equatable {
    case emptyChannels
    case mismatchedChannelLengths
}

/// Pure, hardware-independent buffer-conversion logic. Deliberately has no
/// AVFoundation/CoreAudio import so it is testable without a live audio
/// device or CLT's absent XCTest — see AudioBufferConversionTests (Swift
/// Testing). `AudioRecorder` (Sources/VoxFlow) is the AVAudioEngine-based
/// caller that feeds this from real mic input; production resampling there
/// uses `AVAudioConverter` (hardware accelerated), not `linearResample`
/// below — that pure resampler exists as the tested, deterministic
/// reference implementation and a last-resort fallback so a malformed or
/// unsupported input format degrades gracefully instead of crashing.
public enum AudioBufferConversion {
    /// Downmix N *planar* (non-interleaved) channels of equal length to
    /// mono by averaging samples across channels.
    public static func downmix(planarChannels channels: [[Float]]) throws -> [Float] {
        guard let first = channels.first else {
            throw AudioBufferConversionError.emptyChannels
        }
        guard channels.allSatisfy({ $0.count == first.count }) else {
            throw AudioBufferConversionError.mismatchedChannelLengths
        }
        guard channels.count > 1 else { return first }

        var result = [Float](repeating: 0, count: first.count)
        let scale = Float(1.0 / Double(channels.count))
        for channel in channels {
            for index in 0..<channel.count {
                result[index] += channel[index] * scale
            }
        }
        return result
    }

    /// Downmix a single *interleaved* buffer (frame-major: ch0, ch1, ch0,
    /// ch1, … for stereo) to mono.
    public static func downmix(interleaved samples: [Float], channelCount: Int) throws -> [Float] {
        guard channelCount > 0 else { throw AudioBufferConversionError.emptyChannels }
        guard channelCount > 1 else { return samples }
        guard samples.count % channelCount == 0 else {
            throw AudioBufferConversionError.mismatchedChannelLengths
        }

        let frameCount = samples.count / channelCount
        var result = [Float](repeating: 0, count: frameCount)
        let scale = Float(1.0 / Double(channelCount))
        for frame in 0..<frameCount {
            var sum: Float = 0
            let base = frame * channelCount
            for channel in 0..<channelCount {
                sum += samples[base + channel]
            }
            result[frame] = sum * scale
        }
        return result
    }

    public static func duration(frameCount: Int, sampleRate: Double) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(frameCount) / sampleRate
    }

    /// True iff a buffer's format already matches VoxFlow's canonical STT
    /// target (16 kHz mono). `AudioRecorder` runs this after every
    /// `AVAudioConverter` pass as a defensive guard — the "never crash on
    /// format mismatch" requirement from the blueprint's Step 3 — dropping
    /// a buffer that fails this check rather than shipping a malformed one
    /// downstream to a paid STT call (S5a).
    public static func matchesTargetFormat(
        sampleRate: Double,
        channelCount: Int,
        toleranceHz: Double = 1.0
    ) -> Bool {
        abs(sampleRate - TargetAudioFormat.sampleRate) <= toleranceHz
            && channelCount == TargetAudioFormat.channelCount
    }

    /// Linear-interpolation resample of mono Float32 samples between
    /// arbitrary sample rates. Pure reference implementation — see the type
    /// doc comment above for why it exists alongside AVAudioConverter.
    public static func linearResample(_ samples: [Float], fromRate: Double, toRate: Double) -> [Float] {
        guard fromRate > 0, toRate > 0, !samples.isEmpty else { return [] }
        guard fromRate != toRate else { return samples }

        let ratio = fromRate / toRate
        let outputCount = max(1, Int((Double(samples.count) / ratio).rounded()))
        var output = [Float](repeating: 0, count: outputCount)

        for index in 0..<outputCount {
            let sourcePosition = Double(index) * ratio
            let index0 = min(Int(sourcePosition), samples.count - 1)
            let index1 = min(index0 + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(index0))
            output[index] = samples[index0] + (samples[index1] - samples[index0]) * fraction
        }
        return output
    }
}
