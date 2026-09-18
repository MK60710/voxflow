import Testing
@testable import VoxFlowCore

@Suite("TranscriptionQueueGate")
struct TranscriptionQueueGateTests {

    @Test("idle (depth 0) enqueues")
    func idleEnqueues() {
        #expect(TranscriptionQueueGate.decide(currentDepth: 0) == .enqueue)
    }

    @Test("one in flight (depth 1) still enqueues — this is the normal single-flight case")
    func oneInFlightEnqueues() {
        #expect(TranscriptionQueueGate.decide(currentDepth: 1) == .enqueue)
    }

    @Test("one in flight plus one already queued (depth 2) rejects — this is the cap")
    func twoDeepRejects() {
        #expect(TranscriptionQueueGate.decide(currentDepth: 2) == .rejectQueueFull)
    }

    @Test("depth beyond 2 also rejects, not just exactly 2")
    func beyondCapAlsoRejects() {
        #expect(TranscriptionQueueGate.decide(currentDepth: 3) == .rejectQueueFull)
    }
}
