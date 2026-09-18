import Foundation
import Security

/// Reads VoxFlow's Groq API key from the login Keychain (blueprint Step 5a:
/// "Your Swift code must read it at runtime via the Security framework —
/// never hardcode, never print/log, never write it to any file"). Mihir
/// added the key himself outside this app via:
///   security add-generic-password -a "groq-api-key" -s "com.mihirk.voxflow" -w "<key>" -U
/// so there is no write path here — only read, on demand, every call.
///
/// Lives in `Sources/VoxFlow` (not `VoxFlowCore`) for the same reason
/// `AudioRecorder`/`HotkeyManager` do: it's a live system-integration side
/// effect (Keychain I/O), not pure logic, even though it happens not to
/// need AppKit. `GroqTranscriptionEngine` in VoxFlowCore never imports
/// Security — it just takes an `apiKeyProvider` closure, and this is the
/// only place that closure is backed by a real Keychain read.
enum KeychainCredentialStore {
    static let service = "com.mihirk.voxflow"
    static let groqAccount = "groq-api-key"

    /// `nil` if no key is stored, the stored value is empty, or the read
    /// fails for any reason (wrong ACL, item deleted, etc) — callers treat
    /// `nil` identically to "not configured".
    static func readGroqAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: groqAccount,
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
}
