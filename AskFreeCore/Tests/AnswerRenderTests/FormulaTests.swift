import AppKit
import SwiftUI
import XCTest
@testable import AnswerRender
@testable import AskFreeCore

/// DeepSeek 实际写出来的 249 条公式、刁钻输入（task-lue8s §12.2）
@MainActor
final class FormulaCorpusTests: XCTestCase {
    func testDeepSeekCorpusAllTypeset() {
        let formulas = Fixtures.formulas("formulas.json")
        XCTAssertEqual(formulas.count, 249)
        var failed: [String] = []
        for f in formulas where MathGlyphs.glyph(f.tex, display: f.display, size: 15.5) == nil {
            failed.append(f.tex)
        }
        XCTAssertEqual(failed, [], "排不出来的公式")
    }

    /// 不支持的命令显示源码（glyph 是 nil），都不崩
    func testUnsupportedShowSourceWithoutCrashing() {
        let unsupported = ["x \\xrightarrow{f} y", "\\underbrace{1+2+\\cdots+n}_{n\\text{ terms}}", "\\href{javascript:alert(1)}{click}",
                           "\\url{https://example.com}", "\\includegraphics{https://example.com/x.png}"]
        for tex in unsupported {
            XCTAssertNil(MathGlyphs.glyph(tex, display: true, size: 15.5), tex)
        }
        for f in Fixtures.formulas("extra.json") { _ = MathGlyphs.glyph(f.tex, display: f.display, size: 15.5) }
    }

    func testNormalizationRules() {
        XCTAssertEqual(MathGlyphs.normalize("a\\dots b \\dotsc"), "a\\ldots b \\dotsc")
        XCTAssertEqual(MathGlyphs.normalize("\\tfrac{1}{2}"), "\\frac{1}{2}")
        XCTAssertEqual(MathGlyphs.normalize("\\boxed{x = \\frac{a}{b}}"), "x = \\frac{a}{b}")
        XCTAssertEqual(MathGlyphs.normalize("E = mc^2 \\tag{1}"), "E = mc^2")
        XCTAssertEqual(MathGlyphs.normalize("E \\tag*{A}"), "E")
        XCTAssertEqual(MathGlyphs.normalize("\\begin{align*} a &= b \\\\ c &= d \\end{align*}"), "\\begin{aligned} a &= b \\\\ c &= d \\end{aligned}")
        XCTAssertEqual(MathGlyphs.normalize("\\begin{equation}x\\end{equation}"), "x")
        XCTAssertEqual(MathGlyphs.normalize("{\\color{red} x} + \\textcolor{blue}{y}"), "{ x} + y")
        // 单独的 \ 加换行换成空格；\\ 后面的换行不动
        XCTAssertEqual(MathGlyphs.normalize("a +\\\nb"), "a + b")
        XCTAssertEqual(MathGlyphs.normalize("a \\\\\nb"), "a \\\\\nb")
        XCTAssertNotNil(MathGlyphs.glyph("\\boxed{E=mc^2}", display: true, size: 15.5))
        XCTAssertNotNil(MathGlyphs.glyph("\\begin{align} a &= b \\\\ &= c \\end{align}", display: true, size: 15.5))
    }

    func testInlineLimitsGoToTheSide() {
        XCTAssertEqual(MathGlyphs.sideLimits("\\sum_{i=1}^{n} x_i + \\lim_{x\\to 0} + \\sum\\limits_a + \\summation"),
                       "\\sum\\nolimits_{i=1}^{n} x_i + \\lim\\nolimits_{x\\to 0} + \\sum\\limits_a + \\summation")
        let inline = MathGlyphs.glyph("\\sum_{i=1}^{n} x_i", display: false, size: 15.5)!
        let display = MathGlyphs.glyph("\\sum_{i=1}^{n} x_i", display: true, size: 15.5)!
        XCTAssertLessThan(inline.size.height, display.size.height - 8, "行内的上下限在右边，矮得多")
    }

    func testOddInputsDoNotCrash() {
        XCTAssertNil(MathGlyphs.glyph(String(repeating: "x+", count: 1001), display: true, size: 15.5), "超过 2000 字不排")
        XCTAssertNil(MathGlyphs.glyph(String(repeating: "{", count: 100) + "x" + String(repeating: "}", count: 100), display: true, size: 15.5))
        for tex in ["", " ", "\\", "{", "}", "^", "_", "\\frac", "\\frac{", "\\sqrt[", "\\begin{pmatrix}", "\\left(", "&&&", "\\\\\\\\", "$", "%",
                    String(repeating: "\\sqrt{", count: 30), "\\text{" + String(repeating: "中", count: 500) + "}"] {
            _ = MathGlyphs.glyph(tex, display: false, size: 15.5)
            _ = MathGlyphs.glyph(tex, display: true, size: 15.5)
        }
    }

    /// 流式时公式不会半截送去排，但答完时没收尾的会当字显示；每条公式的每个前缀都排一遍也不崩
    func testEveryPrefixOfCorpusDoesNotCrash() {
        var seen = Set<String>()
        var cases = 0
        for f in Fixtures.formulas("formulas.json") where seen.insert(f.tex).inserted {
            let chars = Array(f.tex)
            for n in stride(from: 1, through: chars.count, by: 3) {
                _ = MathGlyphs.glyph(String(chars[0..<n]), display: f.display, size: 15.5)
                cases += 1
            }
        }
        XCTAssertGreaterThan(cases, 500)
    }

    /// 同一条公式（同样的模式和字号）每次拿到同一张图
    func testSameFormulaSameImage() {
        let a = MathGlyphs.glyph("x^2+1", display: false, size: 15.5)
        let b = MathGlyphs.glyph("x^2+1", display: false, size: 15.5)
        XCTAssertTrue(a!.image === b!.image)
        XCTAssertFalse(a!.image === MathGlyphs.glyph("x^2+1", display: true, size: 15.5)!.image)
        XCTAssertTrue(a!.image.isTemplate)
    }

    func testCacheEvictsBeyond300() {
        AnswerRenderCaches.reset()
        for k in 0..<320 { _ = MathGlyphs.glyph("x_{\(k)}", display: false, size: 15.5) }
        XCTAssertEqual(MathGlyphs.cachedCount(), 300)
    }
}

/// 链接只留 https；<script>、<img> 原样当字；SwiftMath 只画字形（task-lue8s §9）
@MainActor
final class LinkSafetyTests: XCTestCase {
    private func links(_ s: String) -> [URL] {
        guard let a = InlineText.markdown(s) else { return [] }
        return a.runs.compactMap(\.link)
    }

    func testOnlyHttpsLinksSurvive() {
        let md = "**看** [click me](javascript:alert(1)) and [normal link](https://example.com/page) and [file](file:///etc/passwd) "
            + "[mail](mailto:a@b.com) [http](http://example.com) [data](data:text/html,<b>x</b>) <https://example.org/auto>"
        let urls = links(md).map(\.absoluteString)
        XCTAssertEqual(Set(urls), ["https://example.com/page", "https://example.org/auto"])
        // 去掉链接的那几个字还在
        let text = String(InlineText.markdown(md)!.characters)
        for word in ["click me", "file", "mail", "http", "data"] { XCTAssertTrue(text.contains(word), word) }
    }

    func testMaliciousAnswerRendersAsText() {
        let md = Fixtures.text("malicious.md")
        let blocks = AnswerBlocks.parse(md, streaming: false)
        var all = ""
        for block in blocks {
            if case .paragraph(let s) = block {
                for piece in AnswerBlocks.inline(s) {
                    if case .text(let t) = piece { all += t }
                    if case .math(let tex) = piece { XCTAssertNil(MathGlyphs.glyph(tex, display: false, size: 15.5), tex) }
                }
                _ = InlineText.render(s, style: TestTheme.panel)
                XCTAssertTrue(links(s + " **x**").allSatisfy { $0.scheme == "https" })
            }
        }
        XCTAssertTrue(all.contains("<script>window.pwned = 1</script>"))
        XCTAssertTrue(all.contains("<img src="))
        XCTAssertTrue(all.contains("<iframe"))
        // 整条画出来不崩
        _ = Offscreen.bitmap(Offscreen.host(PanelCard(markdown: md), dark: false))
    }

    func testCodeBlockContentIsNotMarkdown() {
        let blocks = AnswerBlocks.parse("```html\n<a href=\"javascript:x\">[x](https://a.b)</a> **b**\n```", streaming: false)
        XCTAssertEqual(blocks, [.code(language: "html", code: "<a href=\"javascript:x\">[x](https://a.b)</a> **b**", attachedTo: nil)])
        let attributed = CodeHighlighter.highlight("[x](https://a.b) **b**", language: "html")
        XCTAssertTrue(attributed.runs.allSatisfy { $0.link == nil })
        XCTAssertEqual(String(attributed.characters), "[x](https://a.b) **b**")
    }
}
