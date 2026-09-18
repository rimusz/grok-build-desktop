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

    func testSmashedHeadingsAndListsBecomeReadableLines() {
        let smashed = "best first.# 1. Migration Assistant over the network (best full clone)Apple's built-in tool copies accounts.How- Put both Macs on the same Wi-Fi.- On the new Mac: later.Speed (rough)- Wi-Fi: hours- Ethernet: faster"
        let expanded = MarkdownBlockParser.expandSmashedMarkdown(smashed)
        XCTAssertTrue(expanded.contains("\n# 1. Migration Assistant over the network (best full clone)\n"), expanded)
        XCTAssertTrue(expanded.contains("\n- Put both Macs"), expanded)
        XCTAssertTrue(expanded.contains("\n- On the new Mac"), expanded)
        XCTAssertTrue(expanded.contains("\n- Wi-Fi: hours"), expanded)
        XCTAssertTrue(expanded.contains("\nHow\n- Put"), expanded)
        XCTAssertFalse(expanded.contains("first.# 1."), expanded)
        XCTAssertFalse(expanded.contains("clone)Apple"), expanded)

        let headingLine = GrokMarkdownStyle.lines(in: expanded).first { $0.hasPrefix("#") } ?? ""
        let heading = GrokMarkdownStyle.heading(from: headingLine)
        XCTAssertEqual(heading?.text, "1. Migration Assistant over the network (best full clone)")
        XCTAssertNil(headingLine.range(of: "Apple's"))
    }

    func testWellFormedMarkdownIsUnchangedBySmashedExpander() {
        let markdown = """
        Intro

        # Title

        Paragraph with a hyphenated Mac-to-Mac cable.

        - item one
        - item two
        """
        XCTAssertEqual(MarkdownBlockParser.expandSmashedMarkdown(markdown), markdown)
    }

    func testSmashedHeadingInsideFenceIsLeftAlone() {
        let fenced = "```\nbest first.# 1. Title- item\n```"
        XCTAssertEqual(MarkdownBlockParser.expandSmashedMarkdown(fenced), fenced)
    }

    func testSmashedHorizontalRuleDoesNotBreakTables() {
        let smashed = "done.---Next steps"
        let expanded = MarkdownBlockParser.expandSmashedMarkdown(smashed)
        XCTAssertTrue(expanded.contains("done.\n---\nNext steps"), expanded)

        let table = "| Keep | Skip |\n|------|------|\n| Docs | Caches |"
        XCTAssertEqual(MarkdownBlockParser.expandSmashedMarkdown(table), table)
    }

    func testProseGluedToTableRowIsKeptAsParagraph() {
        let extraPipe = """
        | Keep | Usually skip |
        |------|------|
        | IDE settings (sync via Git/cloud) | Huge VMs |A clean replacement plus cloud/git is often more reliable than cloning a years-old managed Mac.
        Practical recommendation
        """
        let extraBlocks = MarkdownBlockParser.parse(extraPipe)
        XCTAssertTrue(
            extraBlocks.contains { if case .table = $0 { return true } else { return false } }
        )
        let extraText = extraBlocks.compactMap { block -> String? in
            if case .text(let value) = block { return value } else { return nil }
        }.joined(separator: "\n")
        XCTAssertTrue(extraText.contains("A clean replacement plus cloud/git"), extraText)
        XCTAssertTrue(extraText.contains("Practical recommendation"), extraText)
        if let table = extraBlocks.first(where: { if case .table = $0 { return true } else { return false } }),
           case .table(_, let rows) = table {
            XCTAssertEqual(rows.last?.last, "Huge VMs")
        } else {
            XCTFail("expected table")
        }

        let gluedCell = """
        | Keep | Usually skip |
        |------|------|
        | IDE settings (sync via Git/cloud) | Huge VMs A clean replacement plus cloud/git is often more reliable than cloning a years-old managed Mac.
        """
        let gluedBlocks = MarkdownBlockParser.parse(gluedCell)
        let gluedText = gluedBlocks.compactMap { block -> String? in
            if case .text(let value) = block { return value } else { return nil }
        }.joined()
        XCTAssertTrue(gluedText.contains("A clean replacement plus cloud/git"), gluedText)
        if let table = gluedBlocks.first(where: { if case .table = $0 { return true } else { return false } }),
           case .table(_, let rows) = table {
            XCTAssertEqual(rows.last?.last, "Huge VMs")
        } else {
            XCTFail("expected table from glued cell")
        }
    }

    func testLiveSmashedTranscriptSplitsLabelsAndInnerLists() {
        let how = "Official steps: Transfer to a new Mac with Migration Assistant.How\n- Put both Macs on the same Wi-Fi."
        let howExpanded = MarkdownBlockParser.expandSmashedMarkdown(how)
        XCTAssertTrue(howExpanded.contains("Assistant.\nHow\n- Put"), howExpanded)

        let speed = "- Match the security code, then pick what to copy (apps, user data, settings).Speed (rough)\n- Wi-Fi: hours to overnight  - Ethernet: faster  - Thunderbolt cable: typically the fastest (often ~1 hour for a large home folder)Work-Mac caveats\n- MDM/firewall/VPN can block discovery."
        let speedExpanded = MarkdownBlockParser.expandSmashedMarkdown(speed)
        XCTAssertTrue(speedExpanded.contains("settings).\nSpeed (rough)\n"), speedExpanded)
        XCTAssertTrue(speedExpanded.contains("\n- Ethernet: faster\n"), speedExpanded)
        XCTAssertTrue(speedExpanded.contains("folder)\nWork-Mac caveats\n- MDM"), speedExpanded)

        let disk = "# 5. Network share, not a diskIf USB is blocked but SMB/AFP is not:"
        let diskExpanded = MarkdownBlockParser.expandSmashedMarkdown(disk)
        XCTAssertTrue(diskExpanded.contains("disk\nIf USB"), diskExpanded)

        let rec = "1. Ask IT whether USB block applies.  2. If they say yes to peer transfer: Migration Assistant.  3. In parallel, push work files."
        let recExpanded = MarkdownBlockParser.expandSmashedMarkdown(rec)
        XCTAssertTrue(recExpanded.contains("\n2. If they say"), recExpanded)
        XCTAssertTrue(recExpanded.contains("\n3. In parallel"), recExpanded)

        let practical = "Practical recommendation1. Ask IT whether USB block also applies."
        XCTAssertTrue(
            MarkdownBlockParser.expandSmashedMarkdown(practical).contains("recommendation\n1. Ask"),
            MarkdownBlockParser.expandSmashedMarkdown(practical)
        )
        let closing = "can log as a security event.If you say whether both Macs are Apple silicon."
        XCTAssertTrue(
            MarkdownBlockParser.expandSmashedMarkdown(closing).contains("event.\nIf you say"),
            MarkdownBlockParser.expandSmashedMarkdown(closing)
        )
        let fileVault = "This is the option that won’t fight FileVault, SIP, USB blocking, or license/MDM rules."
        XCTAssertEqual(MarkdownBlockParser.expandSmashedMarkdown(fileVault), fileVault)
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

    func testNumberedSectionTitleIsAHeadingButSentenceListIsNot() {
        let title = "1. Migration Assistant over the network (best full clone)"
        let heading = GrokMarkdownStyle.heading(from: title)
        XCTAssertEqual(heading?.level, 2)
        XCTAssertEqual(heading?.text, title)
        XCTAssertEqual(GrokMarkdownStyle.heading(from: "# \(title)")?.text, title)

        let sentence = "1. Ask IT whether USB block also applies to Mac-to-Mac Thunderbolt."
        XCTAssertNil(GrokMarkdownStyle.heading(from: sentence))
        XCTAssertEqual(GrokMarkdownStyle.listItem(from: sentence)?.text.contains("Ask IT"), true)

        XCTAssertEqual(GrokMarkdownStyle.heading(from: "How")?.text, "How")
        XCTAssertEqual(GrokMarkdownStyle.heading(from: "Speed (rough)")?.text, "Speed (rough)")
        XCTAssertNil(GrokMarkdownStyle.heading(from: "You do not need Time Machine or an external disk."))
    }

    func testHeadingNSAttributesUseCLIBlue() {
        let line = "# 1. Migration Assistant over the network (best full clone)"
        let ns = AttributedTextSizing.nsAttributed(GrokMarkdownStyle.attributedLine(line))
        XCTAssertGreaterThan(ns.length, 0)
        var color: NSColor?
        var font: NSFont?
        ns.enumerateAttributes(in: NSRange(location: 0, length: ns.length), options: []) { attrs, _, _ in
            if let next = attrs[.foregroundColor] as? NSColor { color = next }
            if let next = attrs[.font] as? NSFont { font = next }
        }
        let rgb = color?.usingColorSpace(.genericRGB)
        XCTAssertNotNil(rgb, "heading must carry an NSColor for NSTextView")
        XCTAssertEqual(rgb!.redComponent, 88 / 255, accuracy: 0.08)
        XCTAssertEqual(rgb!.blueComponent, 1.0, accuracy: 0.08)
        XCTAssertGreaterThan(rgb!.blueComponent, rgb!.greenComponent)
        XCTAssertNotNil(font)
        XCTAssertTrue(
            font!.fontDescriptor.symbolicTraits.contains(.bold),
            "heading should be bold like grok TUI"
        )
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

    func testHeadingWrapKeepsFullTitleAtNarrowWidth() {
        let line = "# 1. Migration Assistant over the network (best full clone)"
        let attributed = GrokMarkdownStyle.attributedLine(line)
        let rendered = String(attributed.characters)
        XCTAssertTrue(rendered.contains("best full clone"), rendered)
        let narrow = AttributedTextSizing.height(attributed, width: 220)
        let wide = AttributedTextSizing.height(attributed, width: 2000)
        XCTAssertGreaterThan(narrow, wide)
        XCTAssertGreaterThan(narrow, 36)
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
