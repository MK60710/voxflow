import Testing
@testable import VoxFlowCore

@Suite("SilenceDetector")
struct SilenceDetectorTests {

    @Test("an empty buffer is silent")
    func emptyBufferIsSilent() {
        #expect(SilenceDetector.isSilent([]))
    }

    @Test("an all-zero buffer (digital silence) is silent — the exact case that hallucinated \"Thank you.\" against the real Groq API")
    func allZeroBufferIsSilent() {
        let samples = [Float](repeating: 0, count: 16_000 * 2) // 2s at 16kHz
        #expect(SilenceDetector.isSilent(samples))
    }

    @Test("a buffer with one loud sample is not silent, even if everything else is zero")
    func oneLoudSampleIsNotSilent() {
        var samples = [Float](repeating: 0, count: 1000)
        samples[500] = 0.5
        #expect(!SilenceDetector.isSilent(samples))
    }

    @Test("a buffer entirely below the threshold is silent")
    func belowThresholdIsSilent() {
        let samples = [Float](repeating: 0.0005, count: 1000)
        #expect(SilenceDetector.isSilent(samples, peakAmplitudeThreshold: 0.002))
    }

    @Test("a buffer at or above the threshold is not silent")
    func atOrAboveThresholdIsNotSilent() {
        let samples = [Float](repeating: 0.002, count: 1000)
        #expect(!SilenceDetector.isSilent(samples, peakAmplitudeThreshold: 0.002))
    }

    @Test("negative-amplitude samples are compared by absolute value")
    func negativeAmplitudeComparedByAbsoluteValue() {
        var samples = [Float](repeating: 0, count: 1000)
        samples[10] = -0.5
        #expect(!SilenceDetector.isSilent(samples))
    }

    @Test("a custom, looser threshold treats low-level noise as silent")
    func customThresholdCanBeLooser() {
        let samples = [Float](repeating: 0.05, count: 1000)
        #expect(SilenceDetector.isSilent(samples, peakAmplitudeThreshold: 0.1))
        #expect(!SilenceDetector.isSilent(samples, peakAmplitudeThreshold: 0.01))
    }
}
