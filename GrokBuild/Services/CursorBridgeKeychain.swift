import Foundation
import Security

/// Storage for the Cursor API key used by the managed local bridge.
///
/// Prefer a 0600 file under Application Support so ad-hoc `make run` rebuilds (new code
/// signature each time) do not trigger macOS Keychain password dialogs. Legacy Keychain
/// items are migrated once on read, then removed.
///
/// The key is injected into the sidecar process environment only — never written to
/// `~/.grok/config.toml` (imported models keep `api_key = "local"`).
enum CursorBridgeKeychain {
    static let service = "com.grokbuild.cursor-bridge"
    static let account = "CURSOR_API_KEY"

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case fileWriteFailed

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain error (\(status))"
            case .fileWriteFailed:
                return "Could not write Cursor API key to Application Support."
            }
        }
    }

    /// Saves or replaces the Cursor API key (Application Support, mode 0600).
    static func save(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete()
            return
        }
        try writeSecretFile(trimmed)
        // Drop any legacy Keychain copy so macOS stops prompting on ad-hoc rebuilds.
        try? deleteLegacyKeychainItem()
    }

    /// Returns the stored API key, or nil when absent.
    static func load() -> String? {
        if let fromFile = readSecretFile() {
            // Drop leftover Keychain items silently (avoids password sheets on ad-hoc rebuilds).
            try? deleteLegacyKeychainItem()
            return fromFile
        }
        // One-time migration from older Keychain storage (may no-op if UI would be required).
        if let legacy = loadLegacyKeychainItem() {
            try? writeSecretFile(legacy)
            try? deleteLegacyKeychainItem()
            return legacy
        }
        // Even if we cannot read the legacy item without a prompt, try deleting it so macOS stops asking.
        try? deleteLegacyKeychainItem()
        return nil
    }

    /// True when a non-empty key is stored.
    static func hasAPIKey() -> Bool {
        load() != nil
    }

    /// Removes the stored API key (file + legacy Keychain).
    static func delete() throws {
        try? FileManager.default.removeItem(at: secretFileURL)
        try deleteLegacyKeychainItem()
    }

    // MARK: - Application Support file

    /// `~/Library/Application Support/GrokBuild/Secrets/cursor-api-key`
    static var secretFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GrokBuild", isDirectory: true)
            .appendingPathComponent("Secrets", isDirectory: true)
        return support.appendingPathComponent("cursor-api-key", isDirectory: false)
    }

    /// Directory that must exist before writing the secret file (testable).
    static func secretsDirectoryURL() -> URL {
        secretFileURL.deletingLastPathComponent()
    }

    private static func writeSecretFile(_ value: String) throws {
        let directory = secretsDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = secretFileURL
        guard let data = value.data(using: .utf8) else { throw KeychainError.fileWriteFailed }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func readSecretFile() -> String? {
        guard let data = try? Data(contentsOf: secretFileURL),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    // MARK: - Legacy Keychain (migration only)

    private static func loadLegacyKeychainItem() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Prefer failing quietly over a password sheet when the app was re-signed.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private static func deleteLegacyKeychainItem() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
