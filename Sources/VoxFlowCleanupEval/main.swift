import Foundation
import Security
import VoxFlowCore

// Standalone, on-demand cleanup-quality eval for Step 6 (blueprint task 5:
// "15 messy-transcript → expected-clean pairs ... an ON-DEMAND eval script
// for manual verification — NOT part of the Scripts/test.sh build gate").
// Run manually:
//
//   swift run VoxFlowCleanupEval
//
// (or via `Scripts/eval-cleanup.sh`, which just wraps this). Makes 15 REAL
// calls to Groq's live chat-completions API using the real Keychain-stored
// key — the same category of blueprint-sanctioned live-API testing as
// Step 5a's VoxFlowSmokeTest. Never part of `swift test`/`Scripts/test.sh`,
// never prints the key itself.
//
// Uses the REAL `GroqCleanupEngine` + `CleanupPromptTemplate` from
// VoxFlowCore (not a reimplementation) so this eval can never silently
// drift from what the shipped app actually sends to Groq.
//
// **Real finding from this session, documented here because it changed how
// this file reads the key:** a brand-new, not-yet-approved SwiftPM debug
// binary calling `SecItemCopyMatching` directly triggers macOS's one-time
// "<binary> wants to use your confidential information" Keychain
// authorization dialog (routed through `SecurityAgent`) — confirmed live via
// `ps aux` showing a `SecurityAgent` process blocked waiting for input. In
// an unattended/headless agent session there is no way to click that
// dialog, so the call hangs indefinitely (same class of issue as Step 3's
// PROGRESS.md note about `codesign`'s interactive Keychain-access prompt).
// The CLI `security` tool itself, by contrast, is already trusted on this
// machine and returns instantly (verified directly: `security
// find-generic-password -a "groq-api-key" -s "com.mihirk.voxflow" -w`
// returns in well under a second, no prompt).
//
// So THIS eval tool reads the key from the `GROQ_API_KEY` environment
// variable — populated by `Scripts/eval-cleanup.sh` via that same trusted
// CLI call — rather than calling `SecItemCopyMatching` itself. It falls
// back to the direct Keychain read (same duplicated-from-
// KeychainCredentialStore pattern `VoxFlowSmokeTest` uses) for the case
// where Mihir runs `swift run VoxFlowCleanupEval` directly outside the
// wrapper script: HE has a real GUI session and hands, so the one-time
// approval dialog (if this binary hasn't been approved before) is just a
// normal click for him, not a hang. The key is never printed, logged, or
// written to any file either way.
func readGroqAPIKey() -> String? {
    if let fromEnvironment = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !fromEnvironment.isEmpty {
        return fromEnvironment
    }

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.mihirk.voxflow",
        kSecAttrAccount as String: "groq-api-key",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data,
          let key = String(data: data, encoding: .utf8),
          !key.isEmpty else {
        return nil
    }
    return key
}

/// One eval case: a messy transcript, a hand-written "acceptable clean
/// version" (for a human to compare against — the LLM's real wording won't
/// match this exactly even at temperature 0, since it isn't the one that
/// produced it), and `mustContainTokens` — the numbers/names/technical
/// terms from the ORIGINAL transcript that rule 4 of the cleanup prompt
/// requires survive verbatim (checked case-insensitively, since fixing
/// capitalization is allowed; the token itself must not change or vanish).
struct EvalCase {
    let label: String
    let messy: String
    let expectedClean: String
    let mustContainTokens: [String]
    /// Step 9: tokens that must NOT survive — specifically for correction
    /// cases, where the whole point is that the RETRACTED value (e.g. the
    /// original "9am" in "...9am scratch that 10am") must be gone from the
    /// final text, not just that the corrected value is present. Empty for
    /// every Step 6 case (nothing there needs a "must not contain" check).
    let mustNotContainTokens: [String]
    /// `true` only for the one case testing rule 5 (filler-only input →
    /// empty output) — scored differently (see `isAcceptable`).
    let expectEmpty: Bool

    init(_ label: String, messy: String, expectedClean: String, mustContainTokens: [String] = [], mustNotContainTokens: [String] = [], expectEmpty: Bool = false) {
        self.label = label
        self.messy = messy
        self.expectedClean = expectedClean
        self.mustContainTokens = mustContainTokens
        self.mustNotContainTokens = mustNotContainTokens
        self.expectEmpty = expectEmpty
    }
}

/// The 15 cases (blueprint task 5). Deliberately DIFFERENT wording from
/// `CleanupPromptTemplate.fewShotExamples` (which the model has already
/// seen in-context) so this is a real generalization check, not a re-test
/// of the exact few-shots. Covers: plain filler removal, proper names,
/// technical vocabulary, numbers, run-ons needing inserted punctuation,
/// "like" as a real verb (must NOT be stripped), a question that must stay
/// a question, and the filler-only/empty case.
let evalCases: [EvalCase] = [
    EvalCase(
        "basic filler + missing punctuation",
        messy: "um so basically i think we should uh push the launch to next tuesday",
        expectedClean: "So basically, I think we should push the launch to next Tuesday.",
        mustContainTokens: ["tuesday"]
    ),
    EvalCase(
        "number must survive verbatim",
        messy: "can you like send me the invoice for twelve thousand dollars by friday",
        expectedClean: "Can you send me the invoice for twelve thousand dollars by Friday?",
        mustContainTokens: ["twelve thousand dollars", "friday"]
    ),
    EvalCase(
        "technical vocabulary must survive",
        messy: "we need to deploy the uh kubernetes cluster before we uh migrate the rag pipeline",
        expectedClean: "We need to deploy the Kubernetes cluster before we migrate the RAG pipeline.",
        mustContainTokens: ["kubernetes", "rag"]
    ),
    EvalCase(
        "proper names must survive",
        messy: "so i talked to vivek and he said the cogniswitch demo went uh really well",
        expectedClean: "So I talked to Vivek and he said the CogniSwitch demo went really well.",
        mustContainTokens: ["vivek", "cogniswitch"]
    ),
    EvalCase(
        "run-on needs split + inserted punctuation, no content added",
        messy: "the meeting is at three the room changed to building two and dont forget your badge",
        expectedClean: "The meeting is at three. The room changed to building two, and don't forget your badge.",
        mustContainTokens: ["three", "building two", "badge"]
    ),
    EvalCase(
        "spelled-out numbers preserved, not converted to digits",
        messy: "we sold two hundred and fifty units last quarter which is up twelve percent",
        expectedClean: "We sold two hundred and fifty units last quarter, which is up twelve percent.",
        mustContainTokens: ["two hundred and fifty", "twelve percent"]
    ),
    EvalCase(
        "short filler-heavy utterance",
        messy: "um yeah uh i guess that works",
        expectedClean: "Yeah, I guess that works."
    ),
    EvalCase(
        "\"like\" as a real verb must NOT be stripped",
        messy: "i really like the new design uh a lot",
        expectedClean: "I really like the new design a lot."
    ),
    EvalCase(
        "a spoken question must stay a question, not get answered",
        messy: "uh what time does the flight leave tomorrow",
        expectedClean: "What time does the flight leave tomorrow?"
    ),
    EvalCase(
        "casual contractions preserved, not formalized away",
        messy: "yeah no i think thats fine lets just go with it",
        expectedClean: "Yeah, no, I think that's fine, let's just go with it."
    ),
    EvalCase(
        "multi-clause run-on with a name",
        messy: "so first we need to fix the login bug then uh update the docs and then like ping sarah about the release",
        expectedClean: "So first we need to fix the login bug, then update the docs, and then ping Sarah about the release.",
        mustContainTokens: ["sarah"]
    ),
    EvalCase(
        "proper noun + institution name must survive",
        messy: "my professor doctor patel said the umass hackathon is in november",
        expectedClean: "My professor, Doctor Patel, said the UMass hackathon is in November.",
        mustContainTokens: ["patel", "umass", "november"]
    ),
    EvalCase(
        "filler-only input should return empty (rule 5), different wording than the in-prompt few-shot",
        messy: "um uh yeah so um",
        expectedClean: "",
        expectEmpty: true
    ),
    EvalCase(
        "spelled-out numbers in a technical context preserved verbatim",
        messy: "the api rate limit is uh five hundred requests per minute and if we hit it we get a four twenty nine error",
        expectedClean: "The API rate limit is five hundred requests per minute, and if we hit it we get a four twenty nine error.",
        mustContainTokens: ["five hundred", "four twenty nine"]
    ),
    EvalCase(
        "informal question with filler, must stay a question",
        messy: "uh do you know if like the client already signed off on this",
        expectedClean: "Do you know if the client already signed off on this?"
    )
]

/// Step 9 (blueprint task 3): "Add 10 correction cases + 5 false-positive
/// cases to Scripts/eval-cleanup.sh (on-demand eval, not the build gate)."
/// Kept as a SEPARATE array (not appended into `evalCases`) so the run
/// output and pass count can report against Step 9's own "≥13/15 on the
/// NEW cases" bar, distinct from Step 6's original 15. Deliberately
/// DIFFERENT wording than `CleanupPromptTemplate.correctionFewShotExamples`
/// (which the model has already seen in-context) — a real generalization
/// check, not a re-test of the exact few-shots, same philosophy as
/// `evalCases` above.
let autoEditsEvalCases: [EvalCase] = [
    // MARK: Positive — 10 correction cases, one per blueprint trigger
    // phrase pattern, each checking BOTH that the corrected value survives
    // AND that the retracted value is gone.
    EvalCase(
        "scratch that — flight time",
        messy: "book the flight for 9am scratch that 10am",
        expectedClean: "Book the flight for 10am.",
        mustContainTokens: ["10am"],
        mustNotContainTokens: ["9am"]
    ),
    EvalCase(
        "scratch that — deadline day",
        messy: "the deadline is friday scratch that monday",
        expectedClean: "The deadline is Monday.",
        mustContainTokens: ["monday"],
        mustNotContainTokens: ["friday"]
    ),
    EvalCase(
        "no wait — pizza count",
        messy: "order 2 pizzas no wait order 3 pizzas",
        expectedClean: "Order 3 pizzas.",
        mustContainTokens: ["3 pizzas"],
        mustNotContainTokens: ["2 pizzas"]
    ),
    EvalCase(
        "no wait — budget number",
        messy: "set the budget to 5000 no wait 5500",
        expectedClean: "Set the budget to 5500.",
        mustContainTokens: ["5500"],
        mustNotContainTokens: ["5000"]
    ),
    EvalCase(
        "I mean — meeting time",
        messy: "tell the team the demo is at noon i mean 1pm",
        expectedClean: "Tell the team the demo is at 1pm.",
        mustContainTokens: ["1pm"],
        mustNotContainTokens: ["noon"]
    ),
    EvalCase(
        "I mean — office city",
        messy: "ship it to the chicago office i mean the denver office",
        expectedClean: "Ship it to the Denver office.",
        mustContainTokens: ["denver"],
        mustNotContainTokens: ["chicago"]
    ),
    EvalCase(
        "actually make that — price",
        messy: "the total comes to 200 dollars actually make that 180 dollars",
        expectedClean: "The total comes to 180 dollars.",
        mustContainTokens: ["180"],
        mustNotContainTokens: ["200 dollars"]
    ),
    EvalCase(
        "actually make that — service call",
        messy: "call the plumber tomorrow actually make that call the electrician tomorrow",
        expectedClean: "Call the electrician tomorrow.",
        mustContainTokens: ["electrician"],
        mustNotContainTokens: ["plumber"]
    ),
    EvalCase(
        "chained correction — person name",
        messy: "reschedule with alex no wait actually reschedule with jordan",
        expectedClean: "Reschedule with Jordan.",
        mustContainTokens: ["jordan"],
        mustNotContainTokens: ["alex"]
    ),
    EvalCase(
        "scratch that — shared secret phrase",
        messy: "the password is blue sky scratch that red sky",
        expectedClean: "The password is red sky.",
        mustContainTokens: ["red sky"],
        mustNotContainTokens: ["blue sky"]
    ),

    // MARK: Negative — 5 false-positive guards. Each phrase LOOKS like a
    // trigger but isn't a real self-correction, so the original content
    // must survive intact, nothing dropped.
    EvalCase(
        "false positive: \"scratch that\" used literally",
        messy: "please dont scratch that mosquito bite it will get infected",
        expectedClean: "Please don't scratch that mosquito bite, it will get infected.",
        mustContainTokens: ["mosquito bite"]
    ),
    EvalCase(
        "false positive: \"scratch that\" used literally, different object",
        messy: "can you scratch that part off the car door",
        expectedClean: "Can you scratch that part off the car door?",
        mustContainTokens: ["car door"]
    ),
    EvalCase(
        "false positive: \"I mean\" as a genuine phrase, not a correction",
        messy: "i really do mean what i said about the raise",
        expectedClean: "I really do mean what I said about the raise.",
        mustContainTokens: ["raise"]
    ),
    EvalCase(
        "false positive: \"actually\" alone, no substitution follows",
        messy: "actually this idea might work better than the last one",
        expectedClean: "Actually, this idea might work better than the last one.",
        mustContainTokens: ["better"]
    ),
    EvalCase(
        "false positive: \"make that\" with no earlier value to replace",
        messy: "make that reservation for two people please",
        expectedClean: "Make that reservation for two people, please.",
        mustContainTokens: ["two people"]
    )
]

let fillerWordPattern = try! NSRegularExpression(pattern: "\\b(um+|uh+|erm+)\\b", options: .caseInsensitive)

func containsFillerWord(_ text: String) -> Bool {
    let range = NSRange(text.startIndex..., in: text)
    return fillerWordPattern.firstMatch(in: text, range: range) != nil
}

func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}

/// Heuristic acceptance check — a starting point for automated triage, not
/// a substitute for actually reading the printed messy/expected/actual
/// triple below. Checks: (1) no leftover filler words, (2) every token that
/// must survive verbatim is present (case-insensitively), (3) word count
/// isn't wildly different from the hand-written expected version (guards
/// against both hallucinated additions and dropped content).
func isAcceptable(_ testCase: EvalCase, actual: String) -> Bool {
    let trimmed = actual.trimmingCharacters(in: .whitespacesAndNewlines)

    if testCase.expectEmpty {
        return trimmed.isEmpty || wordCount(trimmed) <= 2
    }

    guard !containsFillerWord(trimmed) else { return false }

    let lowerActual = trimmed.lowercased()
    for token in testCase.mustContainTokens {
        guard lowerActual.contains(token.lowercased()) else { return false }
    }
    for token in testCase.mustNotContainTokens {
        guard !lowerActual.contains(token.lowercased()) else { return false }
    }

    let expectedWords = max(1, wordCount(testCase.expectedClean))
    let actualWords = wordCount(trimmed)
    let ratio = Double(actualWords) / Double(expectedWords)
    guard ratio >= 0.5 && ratio <= 1.8 else { return false }

    return true
}

/// Runs one set of eval cases against the real Groq API and returns the
/// acceptable count. Factored out of `main()` so Step 6's original 15 cases
/// and Step 9's 15 new cases can each run as their own labeled pass with
/// their own reported total, per the blueprint's separate "≥13/15" bars for
/// each (task 5 for Step 6, task 3 for Step 9) — pooling them into one
/// combined number would hide a regression in either half behind the
/// other's strength.
func runEvalPass(label: String, cases: [EvalCase], engine: GroqCleanupEngine) async -> Int {
    print("=== \(label): \(cases.count) real Groq calls ===\n")
    var acceptableCount = 0
    for (index, testCase) in cases.enumerated() {
        print("--- Case \(index + 1)/\(cases.count): \(testCase.label) ---")
        print("messy:    \(testCase.messy)")
        print("expected: \(testCase.expectedClean.isEmpty ? "<empty>" : testCase.expectedClean)")

        let start = Date()
        do {
            // Hard per-case ceiling (well above the 10s HTTP timeout
            // already set on the request) so a single stuck call can
            // never block the whole eval run indefinitely — reuses the
            // same real async race `CleanupLatencyGuard` provides in
            // production, just with a much more generous budget.
            let result = try await CleanupLatencyGuard.run(budgetMilliseconds: 15_000) {
                try await engine.clean(transcript: testCase.messy)
            }
            let elapsedMs = LatencyInstrumentation.milliseconds(from: start, to: Date())
            let accepted = isAcceptable(testCase, actual: result.text)
            if accepted { acceptableCount += 1 }
            print("actual:   \(result.text.isEmpty ? "<empty>" : result.text)  (\(elapsedMs)ms, \(accepted ? "ACCEPTABLE" : "NOT ACCEPTABLE"))")
        } catch let error as CleanupEngineError {
            let elapsedMs = LatencyInstrumentation.milliseconds(from: start, to: Date())
            print("FAILED in \(elapsedMs)ms — classified error: \(error) — message: \(error.pillMessage)")
        } catch {
            print("FAILED with unclassified error: \(error.localizedDescription)")
        }
        print("")

        // Fixed pacing delay between cases — NOT a retry of any failing
        // case — 1.5s originally (Step 6's first run), widened to 5s here
        // after a Step 9 session's 30-case run (2 eval sets back-to-back,
        // on top of a day of other real Groq calls) burst-rate-limited
        // badly at 1.5s: only 9/30 cases got real responses, the rest all
        // HTTP 429. Keeps this a single clean pass through exactly the
        // designed cases per the blueprint's "don't loop/retry burning
        // quota" instruction — widening the delay is pacing, not retrying.
        if index < cases.count - 1 {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    print("=== \(label) result: \(acceptableCount)/\(cases.count) acceptable (blueprint bar: ≥13/15) ===\n")
    return acceptableCount
}

@main
struct VoxFlowCleanupEval {
    static func main() async {
        // Force unbuffered stdout: when this process's stdout is a pipe
        // (not a TTY — e.g. redirected to a log file), Swift/Foundation
        // fully-buffers it by default, so `print` calls don't actually
        // reach the file until the buffer fills or the process exits.
        // Unbuffering makes each case's progress visible in real time,
        // which matters for diagnosing exactly where a run stalls.
        setvbuf(stdout, nil, _IONBF, 0)

        let totalCases = evalCases.count + autoEditsEvalCases.count
        print("VoxFlow cleanup eval (Step 6 + Step 9) — \(totalCases) real Groq calls total, no key values printed.\n")

        guard readGroqAPIKey() != nil else {
            print("No Groq key found in Keychain (service com.mihirk.voxflow, account groq-api-key). Nothing to test.")
            return
        }

        let engine = GroqCleanupEngine(apiKeyProvider: { readGroqAPIKey() })

        let step6Count = await runEvalPass(label: "Step 6 cleanup quality", cases: evalCases, engine: engine)
        let step9Count = await runEvalPass(label: "Step 9 auto-edits (corrections + false positives)", cases: autoEditsEvalCases, engine: engine)

        print("=== FINAL: Step 6 \(step6Count)/\(evalCases.count), Step 9 \(step9Count)/\(autoEditsEvalCases.count) ===")
    }
}
