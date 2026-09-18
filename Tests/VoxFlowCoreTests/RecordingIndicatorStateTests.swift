import Testing
@testable import VoxFlowCore

@Suite("RecordingIndicatorState")
struct RecordingIndicatorStateTests {

    @Test("idle shows a persistent, non-error Ready pill")
    func idleShowsReadyPill() {
        #expect(RecordingIndicatorState.idle.pillMessage == "Ready")
        #expect(RecordingIndicatorState.idle.isPillVisible == true)
        #expect(RecordingIndicatorState.idle.isIdle == true)
        #expect(RecordingIndicatorState.idle.isErrorState == false)
    }

    @Test("recording shows a pill and is not an error state")
    func recordingShowsPill() {
        let state = RecordingIndicatorState.recording
        #expect(state.pillMessage != nil)
        #expect(state.isPillVisible)
        #expect(state.isErrorState == false)
    }

    @Test("toggleRecording shows a distinct pill (not just recording's) and is not an error state")
    func toggleRecordingShowsDistinctPill() {
        let state = RecordingIndicatorState.toggleRecording
        #expect(state.pillMessage != nil)
        #expect(state.pillMessage != RecordingIndicatorState.recording.pillMessage)
        #expect(state.isErrorState == false)
        #expect(state.menuBarSymbolName == RecordingIndicatorState.recording.menuBarSymbolName)
    }

    @Test("transcribing shows a distinct, non-error pill and shares recording's menu bar symbol")
    func transcribingShowsDistinctPill() {
        let state = RecordingIndicatorState.transcribing
        #expect(state.pillMessage == "Transcribing…")
        #expect(state.isErrorState == false)
        #expect(state.isIdle == false)
        #expect(state.menuBarSymbolName == RecordingIndicatorState.recording.menuBarSymbolName)
    }

    @Test("secureInputBlocked is a visible error state with the expected message")
    func secureInputBlockedIsErrorState() {
        let state = RecordingIndicatorState.secureInputBlocked
        #expect(state.pillMessage == "Blocked by secure input")
        #expect(state.isErrorState)
    }

    @Test("permissionNeeded is a visible error state")
    func permissionNeededIsErrorState() {
        let state = RecordingIndicatorState.permissionNeeded
        #expect(state.isPillVisible)
        #expect(state.isErrorState)
    }

    @Test("aborted surfaces its custom reason verbatim as the pill message")
    func abortedSurfacesReason() {
        let state = RecordingIndicatorState.aborted(reason: "Audio device changed — recording stopped, try again")
        #expect(state.pillMessage == "Audio device changed — recording stopped, try again")
        #expect(state.isErrorState)
    }

    @Test("menu bar symbol differs between idle and recording")
    func menuBarSymbolDiffersByState() {
        #expect(RecordingIndicatorState.idle.menuBarSymbolName != RecordingIndicatorState.recording.menuBarSymbolName)
    }

    @Test("error-family states all share the warning symbol")
    func errorStatesShareWarningSymbol() {
        let symbol = RecordingIndicatorState.secureInputBlocked.menuBarSymbolName
        #expect(RecordingIndicatorState.permissionNeeded.menuBarSymbolName == symbol)
        #expect(RecordingIndicatorState.aborted(reason: "x").menuBarSymbolName == symbol)
    }

    @Test("Equatable distinguishes aborted reasons")
    func abortedEquatableComparesReason() {
        #expect(RecordingIndicatorState.aborted(reason: "a") != RecordingIndicatorState.aborted(reason: "b"))
        #expect(RecordingIndicatorState.aborted(reason: "a") == RecordingIndicatorState.aborted(reason: "a"))
    }
}
