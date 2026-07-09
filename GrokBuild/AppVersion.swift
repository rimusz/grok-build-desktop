import Foundation

enum AppVersion {
  /// Version baked into the app at build time (`Info.plist`). Do not read the repo
  /// `VERSION` file at runtime — that path is compile-time `#filePath` and would show
  /// whatever is currently in the dev tree, not what was actually released.
  static var short: String {
    bundleValue("CFBundleShortVersionString")
      ?? repositoryValue(named: "VERSION")
      ?? "0.0.0"
  }

    static var display: String {
        short
    }

    private static func bundleValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func repositoryValue(named fileName: String) -> String? {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        for _ in 0..<4 {
            let candidate = directory.appendingPathComponent(fileName)
            if let value = try? String(contentsOf: candidate, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            directory.deleteLastPathComponent()
        }

        return nil
    }
}
