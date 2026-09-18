import Testing
@testable import VoxFlowCore

@Suite("PCM16Conversion")
struct PCM16ConversionTests {

    @Test("zero converts to zero")
    func zeroConvertsToZero() {
        #expect(PCM16Conversion.int16Sample(fromFloat32: 0.0) == 0)
    }

    @Test("full-scale positive (1.0) converts to Int16.max, not an overflow")
    func fullScalePositiveDoesNotOverflow() {
        #expect(PCM16Conversion.int16Sample(fromFloat32: 1.0) == Int16.max)
    }

    @Test("full-scale negative (-1.0) converts to -32767, one below Int16.min by design")
    func fullScaleNegativeStaysWithinRange() {
        #expect(PCM16Conversion.int16Sample(fromFloat32: -1.0) == -32767)
    }

    @Test("a sample beyond +1.0 (real mic overshoot, observed on real hardware) clamps to Int16.max, not garbage")
    func aboveRangeSampleClamps() {
        #expect(PCM16Conversion.int16Sample(fromFloat32: 2.0128) == Int16.max)
    }

    @Test("a sample beyond -1.0 clamps to -32767, not garbage or a wraparound")
    func belowRangeSampleClamps() {
        #expect(PCM16Conversion.int16Sample(fromFloat32: -2.5) == -32767)
    }

    @Test("mid-scale positive value scales and rounds correctly")
    func midScalePositiveValue() {
        // 0.5 * 32767 = 16383.5 -> rounds to 16384
        #expect(PCM16Conversion.int16Sample(fromFloat32: 0.5) == 16384)
    }

    @Test("mid-scale negative value scales and rounds correctly")
    func midScaleNegativeValue() {
        // -0.5 * 32767 = -16383.5 -> rounds to -16384
        #expect(PCM16Conversion.int16Sample(fromFloat32: -0.5) == -16384)
    }

    @Test("round-trip precision: converting back to Float32 stays within one quantization step of the original")
    func roundTripPrecisionIsReasonable() {
        let original: Float = 0.37
        let converted = PCM16Conversion.int16Sample(fromFloat32: original)
        let roundTripped = Float(converted) / 32767.0
        #expect(abs(roundTripped - original) < (1.0 / 32767.0))
    }

    @Test("a full buffer converts in order, one sample to one sample")
    func fullBufferConvertsInOrder() {
        let samples: [Float] = [0.0, 1.0, -1.0, 0.5, -0.5]
        let converted = PCM16Conversion.convert(samples)
        #expect(converted == [0, Int16.max, -32767, 16384, -16384])
    }

    @Test("an empty buffer converts to an empty buffer")
    func emptyBufferConvertsToEmpty() {
        #expect(PCM16Conversion.convert([]).isEmpty)
    }
}
