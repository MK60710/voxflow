import Testing
@testable import VoxFlowCore

@Suite("AppInfo")
struct AppInfoTests {
    @Test("latency budget sums to the 1.5 s bar from the plan")
    func latencyBudgetTotal() {
        #expect(LatencyBudget.totalMs == 1500)
    }

    @Test("bundle identifier is stable — TCC grants depend on it")
    func bundleIdentifierIsStable() {
        #expect(AppInfo.bundleIdentifier == "com.mihirk.voxflow")
    }
}
