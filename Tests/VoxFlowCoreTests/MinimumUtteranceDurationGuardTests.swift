import Testing
@testable import VoxFlowCore

@Suite("MinimumUtteranceDurationGuard")
struct MinimumUtteranceDurationGuardTests {

    @Test("only the clearest degenerate case (near-instantaneous) from the real incident is still flagged")
    func onlyTheClearestDegenerateCaseIsStillFlagged() {
        // Real numbers from the 2026-08-13 log incident. Threshold was
        // revised DOWN from 1.0s to 0.3s after Mihir's direct correction
        // (a real single short word like "Okay" must not be blocked) — so
        // only the shortest of these, right at the old floor, is still
        // caught; the rest are an accepted tradeoff now, not a miss.
        #expect(MinimumUtteranceDurationGuard.isTooShortForRealSpeech(0.29))
    }

    @Test("the incident's less-extreme garbage clips now pass through — accepted tradeoff, not an oversight")
    func lessExtremeGarbageClipsNowPassThrough() {
        let noLongerFlagged: [Double] = [0.39, 0.49, 0.70, 0.80, 0.99]
        for duration in noLongerFlagged {
            #expect(!MinimumUtteranceDurationGuard.isTooShortForRealSpeech(duration), "\(duration)s should now pass through, per the revised threshold")
        }
    }

    @Test("a real, short voice-command-length utterance is NOT flagged")
    func realCommandLengthUtteranceIsNotFlagged() {
        // Real numbers from live Step 10 command testing this session
        // ("undo that", "select all") — genuine speech, must survive.
        #expect(!MinimumUtteranceDurationGuard.isTooShortForRealSpeech(1.19))
        #expect(!MinimumUtteranceDurationGuard.isTooShortForRealSpeech(1.39))
    }

    @Test("a fast single-word utterance like \"Okay\" is NOT flagged — the exact case Mihir corrected")
    func fastSingleWordUtteranceIsNotFlagged() {
        // A quick, real "Okay" plausibly runs 0.3s-0.5s for a fast talker —
        // must survive; this is the whole reason the threshold moved.
        #expect(!MinimumUtteranceDurationGuard.isTooShortForRealSpeech(0.35))
        #expect(!MinimumUtteranceDurationGuard.isTooShortForRealSpeech(0.45))
    }

    @Test("exactly at the threshold is NOT too short — the floor is exclusive")
    func exactlyAtThresholdIsNotTooShort() {
        #expect(!MinimumUtteranceDurationGuard.isTooShortForRealSpeech(MinimumUtteranceDurationGuard.minimumDurationSeconds))
    }

    @Test("zero duration is too short")
    func zeroDurationIsTooShort() {
        #expect(MinimumUtteranceDurationGuard.isTooShortForRealSpeech(0))
    }

    @Test("a long, genuine dictation is not flagged")
    func longDictationIsNotFlagged() {
        #expect(!MinimumUtteranceDurationGuard.isTooShortForRealSpeech(3.49))
        #expect(!MinimumUtteranceDurationGuard.isTooShortForRealSpeech(42.29))
    }
}
