import Foundation

/// File storage for the Cursor API key used by the managed local bridge.
///
/// The key lives in a 0600 file under Application Support. It is injected into the
/// sidecar process environment only — never written to `~/.grok/config.toml`
/// (imported models keep `api_key = "local"`).
enum CursorBridgeAPIKey {
    enum StorageError: LocalizedError {
        case fileWriteFailed

        var errorDescription: String? {
            "Could not write Cursor API key to Application Support."
        }
    }

    /// Saves or replaces the Cursor API key (Application Support, mode 0600).
    static func save(_ apiKey: String, fileURL: URL = secretFileURL) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete(fileURL: fileURL)
            return
        }
        try writeSecretFile(trimmed, fileURL: fileURL)
    }

    /// Returns the stored API key, or nil when absent.
    static func load(fileURL: URL = secretFileURL) -> String? {
        readSecretFile(fileURL: fileURL)
    }

    /// True when a non-empty key is stored.
    static func hasAPIKey(fileURL: URL = secretFileURL) -> Bool {
        load(fileURL: fileURL) != nil
    }

    /// Removes the stored API key file.
    static func delete(fileURL: URL = secretFileURL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
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

    private static func writeSecretFile(_ value: String, fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = value.data(using: .utf8) else { throw StorageError.fileWriteFailed }
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func readSecretFile(fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
