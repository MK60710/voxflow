import Foundation
import Testing
@testable import VoxFlowCore

@Suite("LatencyInstrumentation")
struct LatencyInstrumentationTests {

    @Test("computes whole milliseconds between two dates")
    func computesMillisecondsBetweenDates() {
        let start = Date()
        let end = start.addingTimeInterval(0.25)
        #expect(LatencyInstrumentation.milliseconds(from: start, to: end) == 250)
    }

    @Test("zero elapsed time is zero milliseconds")
    func zeroElapsedIsZero() {
        let now = Date()
        #expect(LatencyInstrumentation.milliseconds(from: now, to: now) == 0)
    }

    @Test("rounds to the nearest millisecond rather than truncating")
    func roundsToNearestMillisecond() {
        let start = Date()
        let end = start.addingTimeInterval(0.1004) // 100.4ms -> rounds to 100
        #expect(LatencyInstrumentation.milliseconds(from: start, to: end) == 100)
    }

    @Test("an end time before the start time yields a negative value rather than crashing")
    func negativeElapsedDoesNotCrash() {
        let start = Date()
        let end = start.addingTimeInterval(-0.5)
        #expect(LatencyInstrumentation.milliseconds(from: start, to: end) == -500)
    }
}
