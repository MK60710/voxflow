import Testing
@testable import VoxFlowCore

@Suite("ResponseDivergenceGuard")
struct ResponseDivergenceGuardTests {

    // MARK: - The real bug, as a regression test

    @Test("the real bug's exact raw/cleaned strings are flagged as likely fabricated")
    func realBugRegressionCase() {
        let raw = "select all of the budget items"
        let cleaned = "I couldn't find any budget items mentioned in the conversation"

        let verdict = ResponseDivergenceGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)

        #expect(verdict.isLikelyFabricated)
        // Real numbers from the confirmed live failure: only "budget",
        // "items" and "the" of the cleaned reply's 10 words appear anywhere
        // in the 6-word raw transcript — a ratio of 0.3.
        #expect(verdict.cleanedWordCount == 10)
        #expect(verdict.overlapRatio < 0.5)
    }

    // Illustrative, not a transcript of the exact second live case (whose
    // literal wording wasn't confirmed) — a second, clearly-fabricated
    // answer to a dictated question, same failure shape as the regression
    // above.
    @Test("a second, illustrative fabrication case (a question answered instead of transcribed) is flagged")
    func secondIllustrativeFabricationCase() {
        let raw = "can you tell me all the words that have h in them in this conversation"
        let cleaned = "Sorry, I don't have access to earlier messages in this session to search for that."

        let verdict = ResponseDivergenceGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)

        #expect(verdict.isLikelyFabricated)
    }

    // MARK: - Legitimate cases that must NOT trigger the guard — same
    // battery ContentPreservationGuardTests uses, to prove the two guards
    // don't fight each other on ordinary, correct cleanups.

    @Test("ordinary light cleanup does NOT trigger the guard")
    func ordinaryLightCleanupDoesNotTrigger() {
        let raw = "um so I think we should uh go with the plan for the launch next month and get everyone on board honestly"
        let cleaned = "So I think we should go with the plan for the launch next month and get everyone on board."

        let verdict = ResponseDivergenceGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)

        #expect(!verdict.isLikelyFabricated)
    }

    @Test("the blueprint's own worked example (deadline/Friday) does NOT trigger the guard")
    func blueprintWorkedExampleDoesNotTrigger() {
        let verdict = ResponseDivergenceGuard.evaluate(
            rawTranscript: "um so basically the uh the deadline moved to friday",
            cleanedText: "So basically, the deadline moved to Friday."
        )
        #expect(!verdict.isLikelyFabricated)
    }

    @Test("a code/terminal minimal-touch cleanup does NOT trigger the guard")
    func codeTerminalMinimalTouchDoesNotTrigger() {
        let verdict = ResponseDivergenceGuard.evaluate(
            rawTranscript: "um git commit dash m uh fix the login bug and push it to origin main",
            cleanedText: "git commit dash m fix the login bug and push it to origin main"
        )
        #expect(!verdict.isLikelyFabricated)
    }

    @Test("a contraction merge (do not -> don't) does NOT trigger the guard")
    func contractionMergeDoesNotTrigger() {
        let verdict = ResponseDivergenceGuard.evaluate(
            rawTranscript: "so the thing is we do not have the budget approved yet for the new laptops this quarter",
            cleanedText: "So the thing is we don't have the budget approved yet for the new laptops this quarter."
        )
        #expect(!verdict.isLikelyFabricated)
    }

    @Test("filler phrases like \"you know\" being dropped does NOT trigger the guard")
    func fillerPhraseDropDoesNotTrigger() {
        let raw = "you know I think we should just go with the option honestly"
        let cleaned = "I think we should go with the option"
        let verdict = ResponseDivergenceGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)
        #expect(!verdict.isLikelyFabricated)
    }

    @Test("word tokenization ignores punctuation and casing")
    func tokenizationIgnoresPunctuationAndCasing() {
        let verdict = ResponseDivergenceGuard.evaluate(
            rawTranscript: "Well, I don't think that's right — do you?",
            cleanedText: "I don't think that's right, do you?"
        )
        #expect(!verdict.isLikelyFabricated)
    }

    @Test("a drastic truncation (this guard's own sibling case) does NOT trigger THIS guard — division of labor with ContentPreservationGuard")
    func truncationAloneDoesNotTriggerDivergence() {
        // Every cleaned word here is a literal subset of the raw transcript
        // — no fabricated vocabulary — so ResponseDivergenceGuard correctly
        // stays quiet. ContentPreservationGuard is what catches this case
        // (see its own realBugRegressionCase test); the two guards target
        // different failure shapes on purpose.
        let raw = "so I wanted to walk through the quarterly roadmap and talk about the new hiring plan and the budget for the marketing campaign next quarter"
        let cleaned = "so I wanted to walk through the quarterly roadmap"

        let verdict = ResponseDivergenceGuard.evaluate(rawTranscript: raw, cleanedText: cleaned)

        #expect(!verdict.isLikelyFabricated)
    }

    // MARK: - The floor

    @Test("cleaned text below the minimum word floor does NOT trigger the guard")
    func belowFloorDoesNotTrigger() {
        let verdict = ResponseDivergenceGuard.evaluate(rawTranscript: "deploy it", cleanedText: "yes okay")
        #expect(!verdict.isLikelyFabricated)
    }

    @Test("empty cleaned text does NOT trigger the guard")
    func emptyCleanedTextDoesNotTrigger() {
        let verdict = ResponseDivergenceGuard.evaluate(rawTranscript: "um uh so yeah um", cleanedText: "")
        #expect(!verdict.isLikelyFabricated)
        #expect(verdict.cleanedWordCount == 0)
    }
}
