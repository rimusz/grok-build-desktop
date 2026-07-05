import XCTest
@testable import GrokBuild

final class QuickStartPromptTests: XCTestCase {
    func testDefaultsAreProvided() {
        XCTAssertFalse(QuickStartPrompt.defaults.isEmpty)
    }

    func testDefaultsHaveUniqueTitles() {
        let titles = QuickStartPrompt.defaults.map(\.title)
        XCTAssertEqual(titles.count, Set(titles).count, "Quick-start titles must be unique")
    }

    func testEachDefaultIsFullyPopulated() {
        for item in QuickStartPrompt.defaults {
            XCTAssertFalse(item.icon.trimmingCharacters(in: .whitespaces).isEmpty, "\(item.title) is missing an icon")
            XCTAssertFalse(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(item.prompt.trimmingCharacters(in: .whitespaces).isEmpty, "\(item.title) is missing a prompt")
        }
    }

    func testPromptsAreNotSlashCommands() {
        // Quick-start prompts seed a normal message; a leading "/" would trigger slash autocomplete.
        for item in QuickStartPrompt.defaults {
            XCTAssertFalse(item.prompt.hasPrefix("/"), "\(item.title) should not start with a slash command")
        }
    }
}
