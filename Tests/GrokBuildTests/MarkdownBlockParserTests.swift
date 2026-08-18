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

    func testSmashedInlineTableBecomesATableBlock() {
        let smashed = "Results: shell and browser control do not. | Capability | Result | What I ran ||---|---|---|| Shell / terminal | Fail | `echo` never started. || Browser | Fail | No browser_* tools. |"
        let expanded = MarkdownBlockParser.expandSmashedTables(smashed)
        XCTAssertTrue(expanded.contains("\n|---|---|---|\n"), expanded)
        XCTAssertTrue(expanded.contains("Results: shell and browser control do not."), expanded)

        let blocks = MarkdownBlockParser.parse(smashed)
        XCTAssertGreaterThanOrEqual(blocks.count, 2)
        guard let table = blocks.first(where: {
            if case .table = $0 { return true }
            return false
        }) else {
            return XCTFail("Expected a table block from smashed GFM")
        }
        if case .table(let headers, let rows) = table {
            XCTAssertEqual(headers, ["Capability", "Result", "What I ran"])
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows[0][0], "Shell / terminal")
            XCTAssertEqual(rows[1][0], "Browser")
        }
    }

    func testSmashedTableInsideFenceIsLeftAlone() {
        let fenced = "```\n| A | B ||---|---|| x | y |\n```"
        XCTAssertEqual(MarkdownBlockParser.expandSmashedTables(fenced), fenced)
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

    func testCRLFTableAndFenceStillParse() {
        let table = "| Host | Role |\r\n|------|------|\r\n| Mini | backend |\r\n"
        let tableBlocks = MarkdownBlockParser.parse(table)
        XCTAssertEqual(tableBlocks.count, 1)
        if case .table(let headers, let rows) = tableBlocks[0] {
            XCTAssertEqual(headers, ["Host", "Role"])
            XCTAssertEqual(rows, [["Mini", "backend"]])
        } else {
            XCTFail("Expected CRLF table")
        }

        let fence = "```\r\nMacBook —Tailscale—> Mini\r\n```"
        let fenceBlocks = MarkdownBlockParser.parse(fence)
        XCTAssertEqual(fenceBlocks.count, 1)
        if case .code(_, let source) = fenceBlocks[0] {
            XCTAssertTrue(source.contains("Tailscale"))
        } else {
            XCTFail("Expected CRLF fence")
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

    func testLongListLineWithManyInlineCodeSpansKeepsTail() {
        let line = "- **Bootstrap:** `setup-mini.sh`, `setup-macbook.sh`, `setup-poly.sh`, `setup-spark.sh`, plus focused helpers (`setup-buzz.sh`, `setup-boost.sh`, `setup-agnt-spark.sh`, `setup-macbook-agnt.sh`)"
        let rendered = String(GrokMarkdownStyle.attributedLine(line).characters)
        XCTAssertTrue(rendered.contains("setup-macbook-agnt.sh"), rendered)
        XCTAssertTrue(rendered.contains("setup-boost.sh"), rendered)
        XCTAssertFalse(rendered.contains("`"), rendered)
    }

    func testContractParagraphKeepsTail() {
        let line = "The contract is `AGENTS.md`. The topology map is `docs/architecture/stack-map.md`. Day-to-day “which agent do I ask?” is `USAGE.md`. Runbooks and skill cards under `docs/` (copied into Cursor/Claude/Grok/Codex skill dirs) tell agents how to upgrade, wire Buzz, switch Spark models, and keep trading gated."
        let rendered = String(GrokMarkdownStyle.attributedLine(line).characters)
        XCTAssertTrue(rendered.contains("wire Buzz"), rendered)
        XCTAssertTrue(rendered.contains("keep trading gated"), rendered)
    }

    func testLinesPreserveBlankParagraphBreaks() {
        XCTAssertEqual(GrokMarkdownStyle.lines(in: "a\n\nb"), ["a", "", "b"])
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

    func testInlineCodePreservesAngleBracketPlaceholder() {
        let line = "must use `wss://<BUZZ_DOMAIN>`, not raw `ws://ai-stack:3000`."
        let attr = GrokMarkdownStyle.inline(line)
        let rendered = String(attr.characters)
        XCTAssertTrue(rendered.contains("<BUZZ_DOMAIN>"), rendered)
        XCTAssertTrue(rendered.contains("ws://ai-stack:3000"), rendered)
        XCTAssertTrue(rendered.contains("must use"), rendered)
        XCTAssertTrue(rendered.contains("not raw"), rendered)

        var codePieces: [String] = []
        var plainPieces: [String] = []
        for run in attr.runs {
            let piece = String(attr[run.range].characters)
            if run.inlinePresentationIntent?.contains(.code) == true {
                codePieces.append(piece)
            } else {
                plainPieces.append(piece)
            }
        }
        XCTAssertEqual(codePieces, ["wss://<BUZZ_DOMAIN>", "ws://ai-stack:3000"])
        XCTAssertTrue(plainPieces.joined().contains("not raw"), plainPieces.joined())
    }

    func testAttributedKeepsTailAfterAngleBracketsAndHeadings() {
        let markdown = """
        Buzz is the consumer chat front door. The desktop app must use `wss://<BUZZ_DOMAIN>`, not raw `ws://ai-stack:3000`.

        ## What lives in the repo

        Runbooks and skill cards under `docs/` (copied into Cursor/Claude/Grok/Codex skill dirs) tell agents how to upgrade, wire Buzz, switch Spark models, and keep trading gated.

        **In one line:** AGNT takes the request and everyone else has one job.
        """
        let rendered = String(GrokMarkdownStyle.attributed(markdown).characters)
        XCTAssertTrue(rendered.contains("<BUZZ_DOMAIN>"), rendered)
        XCTAssertTrue(rendered.contains("wire Buzz"), rendered)
        XCTAssertTrue(rendered.contains("In one line"), rendered)
        XCTAssertTrue(rendered.contains("everyone else has one job"), rendered)
        XCTAssertFalse(rendered.contains("##"), rendered)
    }

    func testWrappedAttributedHeightExceedsSingleLine() {
        let line = String(repeating: "upgrade, wire Buzz, switch Spark models, and keep trading gated. ", count: 8)
        let attributed = GrokMarkdownStyle.attributed(line)
        let wrapped = AttributedTextSizing.height(attributed, width: 240)
        let wide = AttributedTextSizing.height(attributed, width: 4000)
        XCTAssertGreaterThan(wrapped, wide)
        XCTAssertGreaterThan(wrapped, 40)
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
