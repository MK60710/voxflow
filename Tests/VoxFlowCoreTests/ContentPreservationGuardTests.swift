import Testing
@testable import VoxFlowCore

@Suite("ContentPreservationGuard")
struct ContentPreservationGuardTests {

    // MARK: - The real bug, as a regression test

    @Test("the real bug's exact raw/cleaned strings are flagged as dropped-too-much-content")
    func realBugRegressionCase() {
        let raw = " yeah so to do this is test number one and let me know how it works can you transcribe the text is it working let me know okay"
        let cleaned = "to do this is test number one and let me know how it works"

        let verdict = ContentPreservationGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)

        #expect(verdict.droppedTooMuchContent)
        // Real numbers this threshold is calibrated against: 28 raw words,
        // "yeah"/"so"/"okay" counted as this guard's own (loose) filler
        // estimate -> content estimate 25; cleaned reply was 14 words.
        #expect(verdict.rawContentWordEstimate == 25)
        #expect(verdict.cleanedWordCount == 14)
    }

    // MARK: - Legitimate cases that must NOT trigger the guard

    @Test("genuinely filler-only input correctly cleaning down to empty string does NOT trigger the guard")
    func allFillerToEmptyDoesNotTrigger() {
        let verdict = ContentPreservationGuard.evaluate(rawTranscript: "um uh so yeah um", cleanedText: "")
        #expect(!verdict.droppedTooMuchContent)
    }

    @Test("a short utterance below the content-word floor does NOT trigger the guard even if cleaned is much shorter")
    func shortUtteranceBelowFloorDoesNotTrigger() {
        // "deploy it" (2 content words) -> "" would be a real bug in
        // isolation, but this guard deliberately stays out of the way
        // below its minimum-content-word floor rather than guessing on too
        // little signal; CleanupOutcomeResolver's own empty-string check
        // (a separate, earlier guard) is what actually catches this case.
        let verdict = ContentPreservationGuard.evaluate(rawTranscript: "um so deploy it", cleanedText: "")
        #expect(!verdict.droppedTooMuchContent)
    }

    @Test("ordinary light cleanup — dropping a couple of real filler words on a longer sentence — does NOT trigger the guard")
    func ordinaryLightCleanupDoesNotTrigger() {
        let raw = "um so I think we should uh go with the plan for the launch next month and get everyone on board honestly"
        let cleaned = "So I think we should go with the plan for the launch next month and get everyone on board."

        let verdict = ContentPreservationGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)

        #expect(!verdict.droppedTooMuchContent)
    }

    @Test("the blueprint's own worked example (deadline/Friday) does NOT trigger the guard")
    func blueprintWorkedExampleDoesNotTrigger() {
        let verdict = ContentPreservationGuard.evaluate(
            rawTranscript: "um so basically the uh the deadline moved to friday",
            cleanedText: "So basically, the deadline moved to Friday."
        )
        #expect(!verdict.droppedTooMuchContent)
    }

    @Test("a code/terminal minimal-touch cleanup (filler removal only) does NOT trigger the guard")
    func codeTerminalMinimalTouchDoesNotTrigger() {
        let verdict = ContentPreservationGuard.evaluate(
            rawTranscript: "um git commit dash m uh fix the login bug and push it to origin main",
            cleanedText: "git commit dash m fix the login bug and push it to origin main"
        )
        #expect(!verdict.droppedTooMuchContent)
    }

    @Test("a contraction merge (do not -> don't) reducing word count by one does NOT trigger the guard")
    func contractionMergeDoesNotTrigger() {
        let verdict = ContentPreservationGuard.evaluate(
            rawTranscript: "so the thing is we do not have the budget approved yet for the new laptops this quarter",
            cleanedText: "So the thing is we don't have the budget approved yet for the new laptops this quarter."
        )
        #expect(!verdict.droppedTooMuchContent)
    }

    // MARK: - Synthetic drastic-truncation cases that MUST trigger the guard

    @Test("a long transcript truncated to a short unrelated fragment triggers the guard")
    func longTranscriptTruncatedToFragmentTriggers() {
        let raw = "so I wanted to walk through the quarterly roadmap and talk about the new hiring plan and the budget for the marketing campaign next quarter"
        let cleaned = "so I wanted to walk through the quarterly roadmap"

        let verdict = ContentPreservationGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)

        #expect(verdict.droppedTooMuchContent)
    }

    @Test("a long transcript cleaned down to a single short unrelated word triggers the guard")
    func longTranscriptToSingleWordTriggers() {
        let raw = "can you please transcribe this whole paragraph and make sure every sentence about the product launch survives intact"
        let cleaned = "sure"

        let verdict = ContentPreservationGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)

        #expect(verdict.droppedTooMuchContent)
    }

    @Test("dropping roughly half a substantial transcript's content triggers the guard")
    func droppingRoughlyHalfTriggers() {
        let raw = "the client wants the report finished by Monday and they also want a summary slide with the top three findings highlighted clearly"
        let cleaned = "the client wants the report finished by Monday"

        let verdict = ContentPreservationGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)

        #expect(verdict.droppedTooMuchContent)
    }

    // MARK: - Filler estimate internals (via the observable Verdict, not private access)

    @Test("filler phrases like \"you know\" and \"i mean\" count toward the content estimate discount")
    func fillerPhrasesCountTowardEstimate() {
        // 12 raw words, 2 consumed by "you know" -> content estimate 10.
        // Cleaned keeps all 10 real words -> ratio 1.0, no trigger.
        let raw = "you know I think we should just go with the option honestly"
        let cleaned = "I think we should go with the option"
        let verdict = ContentPreservationGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)
        #expect(!verdict.droppedTooMuchContent)
    }

    @Test("word tokenization ignores punctuation and casing")
    func tokenizationIgnoresPunctuationAndCasing() {
        let verdict = ContentPreservationGuard.evaluate(
            rawTranscript: "Well, I don't think that's right — do you?",
            cleanedText: "I don't think that's right, do you?"
        )
        #expect(!verdict.droppedTooMuchContent)
    }
}
