import Foundation
import Testing
@testable import VoxFlowCore

@Suite("ClipboardRestoreDecision")
struct ClipboardRestoreDecisionTests {

    private let minimumDwell: TimeInterval = 0.12
    private let maxWait: TimeInterval = 2.0

    @Test("keeps polling when nothing changed and the minimum dwell hasn't elapsed")
    func keepsPollingBeforeMinimumDwell() {
        let decision = ClipboardRestoreDecision.evaluate(
            postWriteChangeCount: 5,
            currentChangeCount: 5,
            elapsed: 0.02,
            minimumDwell: minimumDwell,
            maxWait: maxWait
        )
        #expect(decision == .keepPolling)
    }

    @Test("restores once the minimum dwell has elapsed and ownership is intact")
    func restoresAfterMinimumDwellWithOwnershipIntact() {
        let decision = ClipboardRestoreDecision.evaluate(
            postWriteChangeCount: 5,
            currentChangeCount: 5,
            elapsed: 0.15,
            minimumDwell: minimumDwell,
            maxWait: maxWait
        )
        #expect(decision == .restore)
    }

    @Test("the minimum dwell boundary itself (elapsed == minimumDwell) already restores")
    func minimumDwellBoundaryRestores() {
        let decision = ClipboardRestoreDecision.evaluate(
            postWriteChangeCount: 5,
            currentChangeCount: 5,
            elapsed: minimumDwell,
            minimumDwell: minimumDwell,
            maxWait: maxWait
        )
        #expect(decision == .restore)
    }

    @Test("aborts immediately if the pasteboard changed, even before the minimum dwell")
    func abortsOnOwnershipLossEvenEarly() {
        let decision = ClipboardRestoreDecision.evaluate(
            postWriteChangeCount: 5,
            currentChangeCount: 6,
            elapsed: 0.0,
            minimumDwell: minimumDwell,
            maxWait: maxWait
        )
        #expect(decision == .abort)
    }

    @Test("aborts on ownership loss even after the minimum dwell has elapsed")
    func abortsOnOwnershipLossAfterDwell() {
        let decision = ClipboardRestoreDecision.evaluate(
            postWriteChangeCount: 5,
            currentChangeCount: 99,
            elapsed: 1.5,
            minimumDwell: minimumDwell,
            maxWait: maxWait
        )
        #expect(decision == .abort)
    }

    @Test("times out and restores anyway once maxWait is exceeded with ownership still intact")
    func timesOutAndRestoresPastMaxWait() {
        let decision = ClipboardRestoreDecision.evaluate(
            postWriteChangeCount: 5,
            currentChangeCount: 5,
            elapsed: 2.5,
            minimumDwell: minimumDwell,
            maxWait: maxWait
        )
        #expect(decision == .restoreTimedOut)
    }

    @Test("the maxWait boundary itself (elapsed == maxWait) is a timeout, not a routine restore")
    func maxWaitBoundaryIsTimeout() {
        let decision = ClipboardRestoreDecision.evaluate(
            postWriteChangeCount: 5,
            currentChangeCount: 5,
            elapsed: maxWait,
            minimumDwell: minimumDwell,
            maxWait: maxWait
        )
        #expect(decision == .restoreTimedOut)
    }

    @Test("ownership loss takes priority over timeout — abort, not restoreTimedOut, past maxWait too")
    func ownershipLossOutranksTimeout() {
        let decision = ClipboardRestoreDecision.evaluate(
            postWriteChangeCount: 5,
            currentChangeCount: 6,
            elapsed: 5.0,
            minimumDwell: minimumDwell,
            maxWait: maxWait
        )
        #expect(decision == .abort)
    }
}

@Suite("PasteboardItemSnapshot")
struct PasteboardItemSnapshotTests {

    @Test("a snapshot's representations survive a save/restore round trip byte-for-byte")
    func snapshotRoundTripsRepresentationsExactly() {
        let originalRepresentations: [String: Data] = [
            "public.utf8-plain-text": Data("hello world".utf8),
            "public.rtf": Data([0x01, 0x02, 0x03, 0xFF, 0x00]),
        ]
        let saved = PasteboardItemSnapshot(representations: originalRepresentations)

        // "Restore": the AppKit-side glue (PasteboardCmdVInserter) rebuilds
        // an NSPasteboardItem from exactly these representations and writes
        // it back — modeled here as constructing a fresh snapshot from the
        // saved data, since VoxFlowCore has no NSPasteboard to round-trip
        // through directly (see PasteboardCmdVInserter.swift for the live
        // version against a real NSPasteboard).
        let restored = PasteboardItemSnapshot(representations: saved.representations)

        #expect(restored == saved)
        #expect(restored.representations["public.utf8-plain-text"] == Data("hello world".utf8))
        #expect(restored.representations["public.rtf"] == Data([0x01, 0x02, 0x03, 0xFF, 0x00]))
    }

    @Test("an empty-representations snapshot round-trips as empty, not nil or crashing")
    func emptySnapshotRoundTrips() {
        let saved = PasteboardItemSnapshot(representations: [:])
        let restored = PasteboardItemSnapshot(representations: saved.representations)
        #expect(restored == saved)
        #expect(restored.representations.isEmpty)
    }

    @Test("a multi-item save/restore round trip preserves item order and per-item content")
    func multiItemRoundTripPreservesOrderAndContent() {
        let original = [
            PasteboardItemSnapshot(representations: ["public.utf8-plain-text": Data("first".utf8)]),
            PasteboardItemSnapshot(representations: ["public.utf8-plain-text": Data("second".utf8)]),
            PasteboardItemSnapshot(representations: [:]),
        ]

        let restored = original.map { PasteboardItemSnapshot(representations: $0.representations) }

        #expect(restored == original)
        #expect(restored[0].representations["public.utf8-plain-text"] == Data("first".utf8))
        #expect(restored[1].representations["public.utf8-plain-text"] == Data("second".utf8))
        #expect(restored[2].representations.isEmpty)
    }
}
