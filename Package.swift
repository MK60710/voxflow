// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoxFlow",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "VoxFlow",
            dependencies: ["VoxFlowCore"]
        ),
        .target(
            name: "VoxFlowCore"
        ),
        // Standalone integration smoke test for Step 5a's Groq wiring — NOT
        // part of `Scripts/test.sh`'s offline suite. Run manually via
        // `swift run VoxFlowSmokeTest` to make a handful of REAL calls to
        // Groq's live API using the real Keychain-stored key, proving the
        // HTTP round-trip/auth/multipart encoding/response parsing work
        // end-to-end without needing Mihir's mic. See PROGRESS.md for the
        // exact runs and results from Step 5a.
        .executableTarget(
            name: "VoxFlowSmokeTest",
            dependencies: ["VoxFlowCore"]
        ),
        // Step 6's on-demand cleanup-quality eval (blueprint task 5: "15
        // messy-transcript → expected-clean pairs ... an ON-DEMAND eval
        // script for manual verification — NOT part of the Scripts/test.sh
        // build gate"). `Scripts/eval-cleanup.sh` just runs
        // `swift run VoxFlowCleanupEval` — a real Swift target (not a
        // duplicated-prompt shell script) so it exercises the EXACT
        // production `CleanupPromptTemplate`/`GroqCleanupEngine` code, with
        // zero risk of the eval prompt drifting out of sync with what the
        // app actually sends.
        .executableTarget(
            name: "VoxFlowCleanupEval",
            dependencies: ["VoxFlowCore"]
        ),
        .testTarget(
            name: "VoxFlowCoreTests",
            dependencies: ["VoxFlowCore"]
        ),
    ]
)
