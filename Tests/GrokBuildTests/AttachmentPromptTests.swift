import XCTest
@testable import GrokBuild

final class AttachmentPromptTests: XCTestCase {
    func testSingleAttachmentUsesPlainPath() {
        let attachment = FileAttachment(path: "/tmp/project/README.md", workspaceRoot: URL(fileURLWithPath: "/tmp/project"))
        XCTAssertEqual(
            AttachmentPromptBuilder.build(from: [attachment]),
            "Attached file: README.md"
        )
    }

    func testMultipleAttachmentsUseBulletList() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let attachments = [
            FileAttachment(path: "/tmp/project/src/main.swift", workspaceRoot: root),
            FileAttachment(path: "/tmp/project/docs/guide.md", workspaceRoot: root),
        ]
        XCTAssertEqual(
            AttachmentPromptBuilder.build(from: attachments),
            "Attached files:\n- src/main.swift\n- docs/guide.md"
        )
    }

    func testHiddenAttachmentsAreSkipped() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let visible = FileAttachment(path: "/tmp/project/a.txt", workspaceRoot: root)
        var hidden = FileAttachment(path: "/tmp/project/secret.txt", workspaceRoot: root)
        hidden.isHidden = true

        XCTAssertEqual(
            AttachmentPromptBuilder.build(from: [visible, hidden]),
            "Attached file: a.txt"
        )
        XCTAssertNil(AttachmentPromptBuilder.build(from: [hidden]))
    }

    func testPromptDoesNotUseAtReferences() {
        let attachment = FileAttachment(path: "/tmp/image.png", workspaceRoot: nil)
        let prompt = AttachmentPromptBuilder.build(from: [attachment])!
        XCTAssertFalse(prompt.contains("@"))
    }
}
