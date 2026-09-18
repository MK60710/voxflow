import Testing
@testable import VoxFlowCore

@Suite("AudioBufferConversion")
struct AudioBufferConversionTests {

    // MARK: - Planar downmix

    @Test("planar downmix averages two channels sample-by-sample")
    func planarDownmixAveragesChannels() throws {
        let left: [Float] = [1.0, 0.0, -1.0]
        let right: [Float] = [0.0, 1.0, -1.0]
        let mono = try AudioBufferConversion.downmix(planarChannels: [left, right])
        #expect(mono == [0.5, 0.5, -1.0])
    }

    @Test("planar downmix with a single channel returns it unchanged")
    func planarDownmixSingleChannelPassthrough() throws {
        let mono: [Float] = [0.1, 0.2, 0.3]
        let result = try AudioBufferConversion.downmix(planarChannels: [mono])
        #expect(result == mono)
    }

    @Test("planar downmix throws on empty channel list")
    func planarDownmixThrowsOnEmpty() {
        #expect(throws: AudioBufferConversionError.emptyChannels) {
            _ = try AudioBufferConversion.downmix(planarChannels: [])
        }
    }

    @Test("planar downmix throws when channels have mismatched lengths")
    func planarDownmixThrowsOnMismatchedLengths() {
        #expect(throws: AudioBufferConversionError.mismatchedChannelLengths) {
            _ = try AudioBufferConversion.downmix(planarChannels: [[1, 2, 3], [1, 2]])
        }
    }

    // MARK: - Interleaved downmix

    @Test("interleaved downmix averages a stereo frame-major buffer")
    func interleavedDownmixAveragesStereo() throws {
        // Frames: (L=1,R=0), (L=0,R=1), (L=-1,R=-1)
        let interleaved: [Float] = [1, 0, 0, 1, -1, -1]
        let mono = try AudioBufferConversion.downmix(interleaved: interleaved, channelCount: 2)
        #expect(mono == [0.5, 0.5, -1.0])
    }

    @Test("interleaved downmix with channelCount 1 returns input unchanged")
    func interleavedDownmixMonoPassthrough() throws {
        let samples: [Float] = [0.1, -0.2, 0.3]
        let result = try AudioBufferConversion.downmix(interleaved: samples, channelCount: 1)
        #expect(result == samples)
    }

    @Test("interleaved downmix throws when sample count isn't a multiple of channel count")
    func interleavedDownmixThrowsOnMisalignedLength() {
        #expect(throws: AudioBufferConversionError.mismatchedChannelLengths) {
            _ = try AudioBufferConversion.downmix(interleaved: [1, 2, 3], channelCount: 2)
        }
    }

    @Test("interleaved downmix throws on zero channel count")
    func interleavedDownmixThrowsOnZeroChannels() {
        #expect(throws: AudioBufferConversionError.emptyChannels) {
            _ = try AudioBufferConversion.downmix(interleaved: [1, 2, 3], channelCount: 0)
        }
    }

    // MARK: - Duration

    @Test("duration converts frame count and sample rate to seconds")
    func durationComputesSeconds() {
        #expect(AudioBufferConversion.duration(frameCount: 16_000, sampleRate: 16_000) == 1.0)
        #expect(AudioBufferConversion.duration(frameCount: 8_000, sampleRate: 16_000) == 0.5)
    }

    @Test("duration is zero for a non-positive sample rate, never divides by zero")
    func durationGuardsZeroSampleRate() {
        #expect(AudioBufferConversion.duration(frameCount: 100, sampleRate: 0) == 0)
    }

    @Test("MonoPCMBuffer.duration matches the free function")
    func monoPCMBufferDurationMatchesFreeFunction() {
        let buffer = MonoPCMBuffer(samples: Array(repeating: 0, count: 32_000), sampleRate: 16_000)
        #expect(buffer.duration == 2.0)
    }

    // MARK: - Format validation

    @Test("matchesTargetFormat accepts exact 16kHz mono")
    func matchesTargetFormatAcceptsExact() {
        #expect(AudioBufferConversion.matchesTargetFormat(sampleRate: 16_000, channelCount: 1))
    }

    @Test("matchesTargetFormat tolerates sub-Hz float rounding")
    func matchesTargetFormatTolerance() {
        #expect(AudioBufferConversion.matchesTargetFormat(sampleRate: 16_000.4, channelCount: 1))
    }

    @Test("matchesTargetFormat rejects wrong sample rate")
    func matchesTargetFormatRejectsWrongRate() {
        #expect(!AudioBufferConversion.matchesTargetFormat(sampleRate: 44_100, channelCount: 1))
    }

    @Test("matchesTargetFormat rejects wrong channel count — the format-mismatch guard AudioRecorder relies on")
    func matchesTargetFormatRejectsWrongChannelCount() {
        #expect(!AudioBufferConversion.matchesTargetFormat(sampleRate: 16_000, channelCount: 2))
    }

    // MARK: - Linear resample

    @Test("linearResample with equal rates returns the input unchanged")
    func linearResampleNoOpWhenRatesMatch() {
        let samples: [Float] = [0.1, 0.2, 0.3]
        #expect(AudioBufferConversion.linearResample(samples, fromRate: 16_000, toRate: 16_000) == samples)
    }

    @Test("linearResample downsampling halves the sample count for a 2:1 ratio")
    func linearResampleDownsamplesToExpectedLength() {
        let samples = [Float](repeating: 1.0, count: 32_000) // 2s @ 16kHz-equivalent count
        let resampled = AudioBufferConversion.linearResample(samples, fromRate: 32_000, toRate: 16_000)
        #expect(resampled.count == 16_000)
    }

    @Test("linearResample upsampling doubles the sample count for a 1:2 ratio")
    func linearResampleUpsamplesToExpectedLength() {
        let samples = [Float](repeating: 1.0, count: 8_000)
        let resampled = AudioBufferConversion.linearResample(samples, fromRate: 8_000, toRate: 16_000)
        #expect(resampled.count == 16_000)
    }

    @Test("linearResample preserves a constant signal's value")
    func linearResamplePreservesConstantSignal() {
        let samples = [Float](repeating: 0.42, count: 1_000)
        let resampled = AudioBufferConversion.linearResample(samples, fromRate: 48_000, toRate: 16_000)
        #expect(resampled.allSatisfy { abs($0 - 0.42) < 0.0001 })
    }

    @Test("linearResample returns empty for empty input")
    func linearResampleHandlesEmptyInput() {
        #expect(AudioBufferConversion.linearResample([], fromRate: 48_000, toRate: 16_000).isEmpty)
    }
}
