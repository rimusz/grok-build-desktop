import Foundation

enum ComputerUseSkillInstaller {
    static let skillName = "grokbuild-computer-use"

    static var userSkillsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok")
            .appendingPathComponent("skills")
    }

    static func installIfNeeded(
        settings: ComputerUseSettings = ComputerUseSettingsStore.load(),
        skillsRoot: URL = userSkillsRoot
    ) throws {
        guard settings.enabled else { return }
        try install(to: skillsRoot)
    }

    @discardableResult
    static func install(to skillsRoot: URL = userSkillsRoot) throws -> URL {
        let source = try bundledSkillURL()
        let destination = skillURL(inSkillsRoot: skillsRoot)
        let fileManager = FileManager.default

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destination.path) {
            let existing = try Data(contentsOf: destination)
            let bundled = try Data(contentsOf: source)
            if existing == bundled {
                return destination
            }
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    static func skillURL(inSkillsRoot skillsRoot: URL = userSkillsRoot) -> URL {
        skillsRoot
            .appendingPathComponent(skillName)
            .appendingPathComponent("SKILL.md")
    }

    static func bundledSkillURL() throws -> URL {
        if let url = Bundle.main.url(
            forResource: "SKILL",
            withExtension: "md",
            subdirectory: "Skills/\(skillName)"
        ) {
            return url
        }

        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(
            forResource: "SKILL",
            withExtension: "md",
            subdirectory: "Skills/\(skillName)"
        ) {
            return url
        }
        #endif

        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            let candidate = directory
                .appendingPathComponent("Resources")
                .appendingPathComponent("Skills")
                .appendingPathComponent(skillName)
                .appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "ComputerUseSkillInstaller",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Bundled Computer Use skill was not found."]
        )
    }
}
