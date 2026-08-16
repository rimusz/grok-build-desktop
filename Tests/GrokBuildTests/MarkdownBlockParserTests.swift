import XCTest
@testable import GrokBuild

final class MarkdownBlockParserTests: XCTestCase {
    func testCurrencyAndShellVariablesStayText() {
        let costBlocks = MarkdownBlockParser.parse("It costs $5 to $10")
        XCTAssertEqual(costBlocks.count, 1)
        if case .text(let s) = costBlocks[0] {
            XCTAssertEqual(s, "It costs $5 to $10")
        } else {
            XCTFail("Expected plain text block")
        }

        let pathBlocks = MarkdownBlockParser.parse("echo $PATH now")
        XCTAssertEqual(pathBlocks.count, 1)
        if case .text(let s) = pathBlocks[0] {
            XCTAssertEqual(s, "echo $PATH now")
        } else {
            XCTFail("Expected plain text block")
        }
    }

    func testInlineMathDetectedWithMathSignals() {
        assertInlineLatex(in: MarkdownBlockParser.parse("Euler: $e^{i\\pi}+1=0$"), expected: "e^{i\\pi}+1=0")
        assertInlineLatex(in: MarkdownBlockParser.parse("value $x_1$"), expected: "x_1")
        assertInlineLatex(in: MarkdownBlockParser.parse("$\\alpha$"), expected: "\\alpha")
    }

    func testDisplayMathStillParsed() {
        let blocks = MarkdownBlockParser.parse("Block $$a^2+b^2=c^2$$ end")
        XCTAssertEqual(blocks.count, 3)
        if case .latex(let expr, let display) = blocks[1] {
            XCTAssertEqual(expr, "a^2+b^2=c^2")
            XCTAssertTrue(display)
        } else {
            XCTFail("Expected display latex block")
        }
    }

    func testLooksLikeInlineMathPredicate() {
        XCTAssertFalse(MarkdownBlockParser.looksLikeInlineMath("5"))
        XCTAssertFalse(MarkdownBlockParser.looksLikeInlineMath("PATH"))
        XCTAssertTrue(MarkdownBlockParser.looksLikeInlineMath("x^2"))
        XCTAssertTrue(MarkdownBlockParser.looksLikeInlineMath("\\alpha"))
        XCTAssertTrue(MarkdownBlockParser.looksLikeInlineMath("a_1"))
        XCTAssertTrue(MarkdownBlockParser.looksLikeInlineMath("x=y"))
    }

    func testGFMTableIsATableBlock() {
        let markdown = """
        Intro

        | Host | Role |
        |------|------|
        | Mac Mini (`ai-stack`) | Always-on |
        | MacBook | Operator |

        Outro
        """
        let blocks = MarkdownBlockParser.parse(markdown)
        XCTAssertEqual(blocks.count, 3)
        if case .text(let intro) = blocks[0] {
            XCTAssertTrue(intro.contains("Intro"))
        } else {
            XCTFail("Expected intro text")
        }
        if case .table(let headers, let rows) = blocks[1] {
            XCTAssertEqual(headers, ["Host", "Role"])
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows[0][0], "Mac Mini (`ai-stack`)")
            XCTAssertEqual(rows[1][1], "Operator")
        } else {
            XCTFail("Expected table block")
        }
        if case .text(let outro) = blocks[2] {
            XCTAssertTrue(outro.contains("Outro"))
        } else {
            XCTFail("Expected outro text")
        }
    }

    func testFencedCodeIsNotMermaid() {
        let blocks = MarkdownBlockParser.parse("before\n```\nMacBook —Tailscale—> Mini\n```\nafter")
        XCTAssertEqual(blocks.count, 3)
        if case .code(let language, let source) = blocks[1] {
            XCTAssertEqual(language, "")
            XCTAssertTrue(source.contains("Tailscale"))
        } else {
            XCTFail("Expected code block")
        }
    }

    func testMermaidFenceStillSpecial() {
        let blocks = MarkdownBlockParser.parse("```mermaid\ngraph TD\nA-->B\n```")
        XCTAssertEqual(blocks.count, 1)
        if case .mermaid(let source) = blocks[0] {
            XCTAssertTrue(source.contains("graph TD"))
        } else {
            XCTFail("Expected mermaid block")
        }
    }

    func testHeadingLineDropsHashesAndKeepsTitle() {
        let heading = GrokMarkdownStyle.heading(from: "## Purpose")
        XCTAssertEqual(heading?.level, 2)
        XCTAssertEqual(heading?.text, "Purpose")
        let rendered = GrokMarkdownStyle.attributed("## Purpose\nbody")
        XCTAssertFalse(String(rendered.characters).contains("##"))
        XCTAssertTrue(String(rendered.characters).contains("Purpose"))
        XCTAssertTrue(String(rendered.characters).contains("body"))
    }

    func testListItemUsesBulletAndPreservesASCIINewlines() {
        let item = GrokMarkdownStyle.listItem(from: "- Research → AGNT")
        XCTAssertEqual(item?.prefix, "• ")
        XCTAssertEqual(item?.text, "Research → AGNT")
        let diagram = "MacBook —Tailscale—> Mini\n  |\n  +-> Spark"
        let rendered = String(GrokMarkdownStyle.attributed(diagram).characters)
        XCTAssertEqual(rendered, diagram)
    }

    func testInlineCodeRunIsPresent() {
        let attr = GrokMarkdownStyle.inline("host `ai-stack` port")
        let hasCode = attr.runs.contains { run in
            run.inlinePresentationIntent?.contains(.code) == true
        }
        XCTAssertTrue(hasCode)
    }

    private func assertInlineLatex(in blocks: [MarkdownBlock], expected: String) {
        let latexBlocks = blocks.compactMap { block -> (String, Bool)? in
            if case .latex(let expr, let display) = block { return (expr, display) }
            return nil
        }
        XCTAssertEqual(latexBlocks.count, 1)
        XCTAssertEqual(latexBlocks[0].0, expected)
        XCTAssertFalse(latexBlocks[0].1)
    }
}
