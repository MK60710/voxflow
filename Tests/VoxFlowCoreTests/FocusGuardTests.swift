import Testing
@testable import VoxFlowCore

@Suite("FocusGuard")
struct FocusGuardTests {

    @Test("proceeds when the current app matches the expected app exactly")
    func proceedsWhenAppsMatch() {
        let app = AppIdentity(processIdentifier: 100, bundleIdentifier: "com.apple.TextEdit")
        #expect(FocusGuard.shouldProceed(expected: app, current: app))
    }

    @Test("holds when the frontmost app changed to a different bundle identifier")
    func holdsWhenBundleIdentifierDiffers() {
        let expected = AppIdentity(processIdentifier: 100, bundleIdentifier: "com.apple.TextEdit")
        let current = AppIdentity(processIdentifier: 200, bundleIdentifier: "com.tinyspeck.slackmacgap")
        #expect(FocusGuard.shouldProceed(expected: expected, current: current) == false)
    }

    @Test("holds when the process identifier differs even with the same bundle identifier (relaunch)")
    func holdsWhenProcessIdentifierDiffersEvenWithSameBundleID() {
        let expected = AppIdentity(processIdentifier: 100, bundleIdentifier: "com.apple.TextEdit")
        let current = AppIdentity(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit")
        #expect(FocusGuard.shouldProceed(expected: expected, current: current) == false)
    }

    @Test("holds when the current app is nil but an app was expected")
    func holdsWhenCurrentIsNil() {
        let expected = AppIdentity(processIdentifier: 100, bundleIdentifier: "com.apple.TextEdit")
        #expect(FocusGuard.shouldProceed(expected: expected, current: nil) == false)
    }

    @Test("fails open (proceeds) when no expected app was captured at all")
    func proceedsWhenExpectedIsNil() {
        let current = AppIdentity(processIdentifier: 100, bundleIdentifier: "com.apple.TextEdit")
        #expect(FocusGuard.shouldProceed(expected: nil, current: current))
    }

    @Test("proceeds when both expected and current are nil")
    func proceedsWhenBothNil() {
        #expect(FocusGuard.shouldProceed(expected: nil, current: nil))
    }
}
