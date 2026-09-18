import Foundation
import Testing
@testable import VoxFlowCore

@Suite("WAVEncoder")
struct WAVEncoderTests {

    @Test("encoded WAV has the correct RIFF/WAVE/fmt/data chunk headers")
    func headersAreCorrect() {
        let data = WAVEncoder.encode(pcm16Samples: [1, 2, 3], sampleRate: 16_000)
        #expect(data.count == 44 + 3 * 2) // 44-byte header + 3 Int16 samples

        #expect(String(data: data.subdata(in: 0..<4), encoding: .ascii) == "RIFF")
        #expect(String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE")
        #expect(String(data: data.subdata(in: 12..<16), encoding: .ascii) == "fmt ")
        #expect(String(data: data.subdata(in: 36..<40), encoding: .ascii) == "data")
    }

    @Test("fmt chunk encodes sample rate, mono channel count, and 16-bit depth")
    func fmtChunkFieldsAreCorrect() {
        let sampleRate: Double = 16_000
        let data = WAVEncoder.encode(pcm16Samples: [0, 0], sampleRate: sampleRate)

        let channelCount = data.subdata(in: 22..<24).withUnsafeBytes { $0.load(as: UInt16.self) }
        let encodedSampleRate = data.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
        let bitsPerSample = data.subdata(in: 34..<36).withUnsafeBytes { $0.load(as: UInt16.self) }

        #expect(channelCount == 1)
        #expect(encodedSampleRate == UInt32(sampleRate))
        #expect(bitsPerSample == 16)
    }

    @Test("data chunk size matches sample count times 2 bytes")
    func dataChunkSizeMatchesSampleCount() {
        let samples: [Int16] = Array(repeating: 0, count: 100)
        let data = WAVEncoder.encode(pcm16Samples: samples, sampleRate: 16_000)
        let dataSize = data.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: UInt32.self) }
        #expect(dataSize == UInt32(samples.count * 2))
    }

    @Test("silent WAV samples are all zero")
    func silentWAVIsAllZero() {
        let data = WAVEncoder.makeSilentWAV(durationSeconds: 0.1, sampleRate: 16_000)
        let sampleBytes = data.subdata(in: 44..<data.count)
        #expect(sampleBytes.allSatisfy { $0 == 0 })
    }

    @Test("silent WAV duration matches the requested sample count")
    func silentWAVDurationMatchesRequestedSampleCount() {
        let sampleRate: Double = 16_000
        let duration = 0.5
        let data = WAVEncoder.makeSilentWAV(durationSeconds: duration, sampleRate: sampleRate)
        let dataSize = data.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: UInt32.self) }
        let expectedSamples = Int((duration * sampleRate).rounded())
        #expect(Int(dataSize) == expectedSamples * 2)
    }

    @Test("tone WAV is not all zero (has actual signal)")
    func toneWAVHasSignal() {
        let data = WAVEncoder.makeToneWAV(durationSeconds: 0.5, frequencyHz: 440, sampleRate: 16_000)
        let sampleBytes = data.subdata(in: 44..<data.count)
        #expect(!sampleBytes.allSatisfy { $0 == 0 })
    }

    @Test("degenerate zero-or-negative duration still produces a valid, non-empty WAV")
    func degenerateDurationStillValid() {
        let data = WAVEncoder.makeSilentWAV(durationSeconds: 0, sampleRate: 16_000)
        #expect(data.count >= 44 + 2) // header + at least one sample (max(1, ...) guard)
    }

    // MARK: - durationSeconds(ofWAVData:) — the inverse of encode, used by
    // GroqTranscriptionEngine to scale its request timeout to the real
    // recording length.

    @Test("durationSeconds round-trips against a WAV this encoder just made")
    func durationRoundTripsThroughEncode() {
        let data = WAVEncoder.makeSilentWAV(durationSeconds: 2.5, sampleRate: 16_000)
        let duration = WAVEncoder.durationSeconds(ofWAVData: data)
        #expect(duration != nil)
        #expect(abs((duration ?? -1) - 2.5) < 0.001)
    }

    @Test("durationSeconds is correct at a non-default sample rate")
    func durationCorrectAtDifferentSampleRate() {
        let data = WAVEncoder.makeSilentWAV(durationSeconds: 1.0, sampleRate: 44_100)
        let duration = WAVEncoder.durationSeconds(ofWAVData: data)
        #expect(duration != nil)
        #expect(abs((duration ?? -1) - 1.0) < 0.001)
    }

    @Test("durationSeconds returns nil for data that isn't a WAV file at all")
    func durationNilForGarbageData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        #expect(WAVEncoder.durationSeconds(ofWAVData: garbage) == nil)
    }

    @Test("durationSeconds returns nil for an empty file")
    func durationNilForEmptyData() {
        #expect(WAVEncoder.durationSeconds(ofWAVData: Data()) == nil)
    }

    @Test("durationSeconds still finds fmt/data chunks when preceded by an unrelated chunk")
    func durationSurvivesAnExtraLeadingChunk() {
        var data = WAVEncoder.makeSilentWAV(durationSeconds: 1.0, sampleRate: 16_000)
        // Splice a fake 6-byte "JUNK" chunk (even-sized, no padding needed)
        // right after the 12-byte RIFF/WAVE preamble, ahead of `fmt `.
        var junkChunk = Data("JUNK".utf8)
        withUnsafeBytes(of: UInt32(2).littleEndian) { junkChunk.append(contentsOf: $0) }
        junkChunk.append(contentsOf: [0xAB, 0xCD])
        data.insert(contentsOf: junkChunk, at: 12)

        let duration = WAVEncoder.durationSeconds(ofWAVData: data)
        #expect(duration != nil)
        #expect(abs((duration ?? -1) - 1.0) < 0.001)
    }
}
