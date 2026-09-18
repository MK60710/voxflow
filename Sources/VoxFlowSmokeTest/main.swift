import Foundation
import Security
import VoxFlowCore

// Standalone integration smoke test for Step 5a (blueprint: "you MAY make a
// small number of REAL calls to Groq's actual API ... as an integration
// smoke test outside the swift test gate"). Run manually:
//
//   swift run VoxFlowSmokeTest
//
// Never part of `Scripts/test.sh` — this hits the live network with the
// real Keychain-stored key. It never prints the key itself.
//
// Keychain read is duplicated (not imported) from
// Sources/VoxFlow/KeychainCredentialStore.swift deliberately: this target
// doesn't depend on the AppKit-facing VoxFlow app target, and the read
// logic is ~10 lines — not worth a shared module just for that, per the
// same "system side effects live at the call site" convention the app
// target already follows for AudioRecorder/HotkeyManager.
func readGroqAPIKeyFromKeychain() -> String? {
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

func runCase(label: String, wavData: Data, engine: GroqTranscriptionEngine) async {
    print("--- \(label) ---")
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("voxflow-smoketest-\(UUID().uuidString).wav")
    do {
        try wavData.write(to: tempURL)
    } catch {
        print("FAILED to write local test WAV: \(error.localizedDescription)")
        return
    }
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let start = Date()
    do {
        let result = try await engine.transcribe(audioFileURL: tempURL, biasPrompt: nil)
        let elapsedMs = LatencyInstrumentation.milliseconds(from: start, to: Date())
        print("SUCCESS in \(elapsedMs)ms — transcript field present, value: \"\(result.text)\" (empty is expected/correct for silence)")
    } catch let error as TranscriptionEngineError {
        let elapsedMs = LatencyInstrumentation.milliseconds(from: start, to: Date())
        print("FAILED in \(elapsedMs)ms — classified error: \(error) — message: \(error.pillMessage)")
    } catch {
        print("FAILED with unclassified error: \(error.localizedDescription)")
    }
}

@main
struct VoxFlowSmokeTest {
    static func main() async {
        print("VoxFlow Groq integration smoke test (Step 5a) — real network calls, no key values printed.")

        guard readGroqAPIKeyFromKeychain() != nil else {
            print("No Groq key found in Keychain (service com.mihirk.voxflow, account groq-api-key). Nothing to test.")
            return
        }
        print("Key found in Keychain (length not printed as content, only presence confirmed).")

        let engine = GroqTranscriptionEngine(apiKeyProvider: { readGroqAPIKeyFromKeychain() })

        await runCase(
            label: "1.5s digital silence (whisper-large-v3-turbo, verbose_json)",
            wavData: WAVEncoder.makeSilentWAV(durationSeconds: 1.5),
            engine: engine
        )
        await runCase(
            label: "1.5s 440Hz tone (non-speech, still exercises the full round-trip)",
            wavData: WAVEncoder.makeToneWAV(durationSeconds: 1.5),
            engine: engine
        )

        print("Done — 2 real Groq API calls made.")
    }
}
