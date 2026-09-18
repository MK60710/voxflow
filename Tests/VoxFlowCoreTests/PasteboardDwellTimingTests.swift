import Foundation
import Testing
@testable import VoxFlowCore

@Suite("PasteboardDwellTiming")
struct PasteboardDwellTimingTests {

    @Test("empty text gets the baseline dwell, not zero")
    func emptyTextGetsBaseline() {
        let timing = PasteboardDwellTiming.timing(forCharacterCount: 0)
        #expect(timing.minimumDwell == PasteboardDwellTiming.baselineDwell)
    }

    @Test("a short insertion (a few words) stays close to the original fast baseline")
    func shortInsertionStaysFast() {
        // "Hello, how are you?" — 20 characters.
        let timing = PasteboardDwellTiming.timing(forCharacterCount: 20)
        #expect(timing.minimumDwell < 0.3)
        #expect(timing.minimumDwell >= PasteboardDwellTiming.baselineDwell)
    }

    @Test("the real bug's ~90-word transcript length scales close to the maximum dwell")
    func longDictationApproachesMaximum() {
        // The real live bug's cleaned transcript was ~480 characters.
        let timing = PasteboardDwellTiming.timing(forCharacterCount: 480)
        #expect(timing.minimumDwell > 1.5)
        #expect(timing.minimumDwell <= PasteboardDwellTiming.maximumDwell)
    }

    @Test("dwell never exceeds the maximum ceiling regardless of how long the text is")
    func dwellNeverExceedsCeiling() {
        let timing = PasteboardDwellTiming.timing(forCharacterCount: 50_000)
        #expect(timing.minimumDwell == PasteboardDwellTiming.maximumDwell)
    }

    @Test("dwell is monotonically non-decreasing as text length grows")
    func dwellIsMonotonicallyNonDecreasing() {
        let lengths = [0, 10, 50, 100, 300, 500, 1_000, 5_000]
        let dwells = lengths.map { PasteboardDwellTiming.timing(forCharacterCount: $0).minimumDwell }
        for index in 1..<dwells.count {
            #expect(dwells[index] >= dwells[index - 1])
        }
    }

    @Test("maxWait always leaves genuine slack beyond minimumDwell")
    func maxWaitAlwaysExceedsMinimumDwellWithSlack() {
        for count in [0, 20, 200, 480, 2_000, 50_000] {
            let timing = PasteboardDwellTiming.timing(forCharacterCount: count)
            #expect(timing.maxWait > timing.minimumDwell)
        }
    }

    @Test("maxWait never exceeds its own absolute ceiling, even for arbitrarily long text")
    func maxWaitNeverExceedsItsCeiling() {
        // With dwell capped at `maximumDwell` (2.0) and a 1.0s buffer, the
        // actually-reachable maxWait under current constants is 3.0 —
        // `maximumMaxWait` (3.5) is a backstop that isn't hit today, but
        // must never be exceeded regardless of how `baselineDwell`/
        // `perCharacterDwell`/`maxWaitBuffer` are tuned later.
        let timing = PasteboardDwellTiming.timing(forCharacterCount: 50_000)
        #expect(timing.maxWait == PasteboardDwellTiming.maximumDwell + PasteboardDwellTiming.maxWaitBuffer)
        #expect(timing.maxWait <= PasteboardDwellTiming.maximumMaxWait)
    }

    @Test("negative-length input (defensive) still returns the baseline, not garbage")
    func negativeLengthDefensivelyReturnsBaseline() {
        let timing = PasteboardDwellTiming.timing(forCharacterCount: -5)
        #expect(timing.minimumDwell == PasteboardDwellTiming.baselineDwell)
    }
}
