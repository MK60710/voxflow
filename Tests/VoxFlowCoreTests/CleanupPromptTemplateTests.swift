import Foundation
import Testing
@testable import VoxFlowCore

@Suite("CleanupPromptTemplate")
struct CleanupPromptTemplateTests {

    @Test("temperature is 0, per the blueprint's determinism requirement")
    func temperatureIsZero() {
        #expect(CleanupPromptTemplate.temperature == 0)
    }

    @Test("system prompt states the do-not-paraphrase / do-not-add rules explicitly")
    func systemPromptStatesCoreRules() {
        let prompt = CleanupPromptTemplate.systemPrompt.lowercased()
        #expect(prompt.contains("do not paraphrase"))
        #expect(prompt.contains("do not add"))
        #expect(prompt.contains("filler"))
    }

    @Test("at least one few-shot example, and none are empty")
    func fewShotExamplesArePopulated() {
        #expect(!CleanupPromptTemplate.fewShotExamples.isEmpty)
        for example in CleanupPromptTemplate.fewShotExamples {
            #expect(!example.messy.isEmpty)
        }
    }

    @Test("messages(forTranscript:) starts with exactly one system message")
    func messagesStartsWithSystemPrompt() {
        let messages = CleanupPromptTemplate.messages(forTranscript: "hello")
        #expect(messages.first?.role == "system")
        #expect(messages.first?.content == CleanupPromptTemplate.systemPrompt)
        #expect(messages.filter { $0.role == "system" }.count == 1)
    }

    @Test("each few-shot example becomes one user/assistant turn pair, in order")
    func fewShotExamplesBecomeAlternatingTurns() {
        let messages = CleanupPromptTemplate.messages(forTranscript: "the real transcript")
        let examples = CleanupPromptTemplate.fewShotExamples

        // messages[0] is system; then 2 messages per example; then the
        // final real transcript as the last user turn.
        #expect(messages.count == 1 + examples.count * 2 + 1)

        for (index, example) in examples.enumerated() {
            let userMessage = messages[1 + index * 2]
            let assistantMessage = messages[2 + index * 2]
            #expect(userMessage.role == "user")
            #expect(userMessage.content == example.messy)
            #expect(assistantMessage.role == "assistant")
            #expect(assistantMessage.content == example.clean)
        }
    }

    @Test("the real transcript is the final message and is a user turn")
    func realTranscriptIsFinalUserTurn() {
        let messages = CleanupPromptTemplate.messages(forTranscript: "um so anyway the meeting moved")
        #expect(messages.last?.role == "user")
        #expect(messages.last?.content == "um so anyway the meeting moved")
    }

    @Test("an empty transcript still produces a valid message list ending in an empty user turn")
    func emptyTranscriptStillAssembles() {
        let messages = CleanupPromptTemplate.messages(forTranscript: "")
        #expect(messages.last?.role == "user")
        #expect(messages.last?.content == "")
    }
}
