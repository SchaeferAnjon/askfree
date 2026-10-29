import AppKit
import SwiftUI
import XCTest
@testable import AnswerRender
@testable import AskFreeCore

/// 两份评审（task-lue8s）要改的地方：每一条一个回归测试
@MainActor
final class InlineMathLayoutTests: XCTestCase {
    private func height(_ md: String, width: CGFloat = 368) -> CGFloat {
        Offscreen.fit(Offscreen.host(AnswerBody(markdown: md, streaming: false, style: TestTheme.panel).frame(width: width), dark: false)).height
    }

    /// 设计评审 2：带行内分数、∫、∑ 的一行最多比普通一行高 6 点，只带上下标的最多高 2 点（原来分数 +24、∫ +47、∑ +26）
    func testInlineFormulasBarelyStretchTheLine() {
        MathGlyphs.warmUp()
        let plain = height("一些字和后面的字")
        for (tex, limit) in [("b^2-4ac", 2.0), ("\\frac{b}{2a}", 6), ("\\left(\\frac{b}{2a}\\right)^2", 6), ("x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}", 6),
                             ("\\int_0^1 f(x)\\,dx", 6), ("\\sum_{i=1}^{n}x_i", 6), ("\\sqrt{b^2-4ac}", 2)] {
            let extra = height("一些字 $\(tex)$ 后面的字") - plain
            XCTAssertLessThanOrEqual(extra, CGFloat(limit), tex)
        }
    }

    /// 行内的矩阵、cases 单独一行，不把一行字撑高
    func testInlineMatrixGetsItsOwnLine() {
        let rendered = InlineText.render("矩阵 $\\begin{pmatrix}1&0\\\\0&1\\end{pmatrix}$ 也放在行内", style: TestTheme.panel)
        XCTAssertTrue(rendered.parts.contains { if case .wideMath = $0 { return true } else { return false } })
    }

    /// 设计评审 6：这段话在 348–374 宽时 SwiftUI 量出两行、只画一行加「…」，下面空一大块。每个宽度画出来看最后一行字到底边空了多少
    func testParagraphIsNotTruncatedNextToFormulas() {
        MathGlyphs.warmUp()
        let md = "A：分数 $\\frac{\\scriptstyle b}{\\scriptstyle 2a}$ 放在行内，积分 ${\\scriptstyle\\int}_0^1 f(x)\\,dx$ 和求和 ${\\scriptstyle\\sum}_{i=1}^{n}x_i$ 也是。"
        for width in stride(from: 330, through: 380, by: 2) {
            let rep = Offscreen.bitmap(Offscreen.host(AnswerBody(markdown: md, streaming: false, style: TestTheme.panel)
                .frame(width: CGFloat(width)).background(Color.white), dark: false))
            var lowestInk = -1
            for y in stride(from: rep.pixelsHigh - 1, through: 0, by: -1) {
                if (0..<rep.pixelsWide).contains(where: { (rep.colorAt(x: $0, y: y)?.brightnessComponent ?? 1) < 0.5 }) { lowestInk = y; break }
            }
            let gap = CGFloat(rep.pixelsHigh - 1 - lowestInk) / 2
            XCTAssertLessThan(gap, 8, "宽 \(width)：最后一行字下面空了 \(gap) 点")
        }
    }

    /// 设计评审 4：det、sin 后面紧跟字母时有细空（和手写 \, 一样宽）
    func testOperatorNameFollowedByThinSpace() {
        for (auto, manual) in [("\\det A", "\\det\\,A"), ("\\sin x", "\\sin\\,x"), ("\\log_2 n", "\\log_2\\,n"), ("\\sin\\frac{x}{2}", "\\sin\\,\\frac{x}{2}")] {
            let a = MathGlyphs.glyph(auto, display: true, size: 15.5)!, m = MathGlyphs.glyph(manual, display: true, size: 15.5)!
            XCTAssertEqual(a.size.width, m.size.width, accuracy: 0.6, auto)
        }
        // 括号前面不补
        XCTAssertEqual(TeXTweaks.thinSpaceAfterOperators("\\sin(x)+\\det\\left(A\\right)"), "\\sin(x)+\\det\\left(A\\right)")
    }

    /// 设计评审 3：矩阵格子开头的负号和公式开头的一样紧
    func testLeadingMinusInMatrixCellsIsUnary() {
        XCTAssertEqual(TeXTweaks.unaryAtCellStart("\\begin{pmatrix}6&-7\\\\-2&4\\end{pmatrix}"), "\\begin{pmatrix}6&\\text{−}7\\\\\\text{−}2&4\\end{pmatrix}")
        XCTAssertEqual(TeXTweaks.unaryAtCellStart("\\begin{cases}-x & x<0\\\\ x & x\\ge 0\\end{cases}"), "\\begin{cases}\\text{−}x & x<0\\\\ x & x\\ge 0\\end{cases}")
        // 格子中间的负号、括号里的不动
        XCTAssertEqual(TeXTweaks.unaryAtCellStart("\\begin{matrix}a-b&{-c}\\end{matrix}"), "\\begin{matrix}a-b&{-c}\\end{matrix}")
        let tight = MathGlyphs.glyph("\\begin{matrix}-2\\end{matrix}", display: true, size: 15.5)!
        let alone = MathGlyphs.glyph("-2", display: true, size: 15.5)!
        XCTAssertEqual(tight.size.width, alone.size.width, accuracy: 0.6)
    }

    /// 行内分数拆开排：段和分数之间的空照 TeX（Rel 粗空、Bin 中空、Ord 细空），开头的负号是一元的
    func testFractionSplitting() {
        let parts = TeXTweaks.splitAtFractions("x=\\frac{-b\\pm\\sqrt{\\Delta}}{2a}+1")!
        XCTAssertEqual(parts.map(\.tex), ["x=", "\\frac{-b\\pm\\sqrt{\\Delta}}{2a}", "+1"])
        XCTAssertEqual(parts.map(\.gapBefore), [0, 5, 0])
        XCTAssertEqual(parts[2].kind, .text(padLeft: true, padRight: false))
        XCTAssertEqual(TeXTweaks.splitAtFractions("-\\frac12")!.map(\.gapBefore), [0, 3])
        XCTAssertEqual(TeXTweaks.splitAtFractions("\\left(\\frac{b}{2a}\\right)^2")!.map(\.tex), ["\\bigl(", "\\frac{b}{2a}", "\\bigr)^2"])
        // 带上下标的、上下标里的、根号里的、\dfrac 不拆
        XCTAssertNil(TeXTweaks.splitAtFractions("\\frac{a}{b}^2"))
        XCTAssertNil(TeXTweaks.splitAtFractions("e^\\frac12"))
        XCTAssertNil(TeXTweaks.splitAtFractions("\\sqrt\\frac12"))
        XCTAssertNil(TeXTweaks.splitAtFractions("\\dfrac{a}{b}"))
        // 拆开排出来的基线和整条排的一样（字母 x 落在同一高度）
        let split = MathGlyphs.glyph("x+\\frac{1}{2}", display: false, size: 15.5)!
        let whole = MathGlyphs.glyph("x+1", display: false, size: 15.5)!
        XCTAssertEqual(split.size.height - split.descent - (whole.size.height - whole.descent), 1.3, accuracy: 3.5)
    }

    /// 行内 ∑、∫ 用基本字形；明写 \limits 的照它
    func testInlineBigOperatorsUseBaseGlyph() {
        XCTAssertEqual(TeXTweaks.baseGlyphOperators("\\sum_{i=1}^n x_i"), "\\text{∑}_{i=1}^n x_i")
        XCTAssertEqual(TeXTweaks.baseGlyphOperators("\\int\\nolimits_0^1"), "\\text{∫}_0^1")
        XCTAssertEqual(TeXTweaks.baseGlyphOperators("\\sum\\limits_{i}"), "\\sum\\limits_{i}")
        XCTAssertEqual(TeXTweaks.baseGlyphOperators("\\summation"), "\\summation")
        let inline = MathGlyphs.glyph("\\int_0^1 f(x)\\,dx", display: false, size: 15.5)!
        XCTAssertLessThan(inline.size.height, 24)
    }

    /// 代码评审 5：几百层根号一条公式不卡主线程（原来 InlineText.render 用了 1 秒）、不出上百 MB 的图
    func testDeeplyNestedFormulaIsCheap() {
        let src = "看 $" + String(repeating: "\\sqrt", count: 300) + " x$ 这个"
        InlineText.resetCache()
        let start = DispatchTime.now().uptimeNanoseconds
        _ = InlineText.render(src, style: TestTheme.panel)
        XCTAssertLessThan(ms(since: start), 100)
        XCTAssertNil(MathGlyphs.glyph(String(repeating: "\\sqrt", count: 100) + " x", display: false, size: 15.5), "套得太深显示源码")
        XCTAssertNotNil(MathGlyphs.glyph(String(repeating: "\\sqrt", count: 20) + " x", display: false, size: 15.5))
    }
}

/// 代码评审 6：历史页里的 Markdown 链接照原来那样是链接，不是源码
@MainActor
final class InlineLinkTests: XCTestCase {
    func testMarkdownLinksAreParsed() {
        let parsed = InlineText.markdown("详见[官网](https://www.python.org)。")
        XCTAssertEqual(parsed.map { String($0.characters) }, "详见官网。")
        XCTAssertEqual(parsed?.runs.compactMap(\.link).map(\.absoluteString), ["https://www.python.org"])
        XCTAssertEqual(InlineText.markdown("<https://example.com>").map { String($0.characters) }, "https://example.com")
        // 不是 https 的链接只留字
        XCTAssertEqual(InlineText.markdown("[点](javascript:alert(1))")?.runs.compactMap(\.link), [])
        // 没有记号的字不解析（和原来的面板逐像素一样）
        XCTAssertNil(InlineText.markdown("普通的一句话。"))
    }
}

/// 代码评审 1：代码按行着色、按行缓存；跨行的块注释、三引号、模板字符串照样着对
@MainActor
final class CodeLineHighlightTests: XCTestCase {
    private func tokens(_ line: AttributedString) -> [String] {
        line.runs.map { run in
            let text = String(line[run.range].characters)
            return run.foregroundColor == nil ? text : "<\(text)>"
        }
    }

    func testMultiLineStatesCarryOver() {
        CodeHighlighter.resetCache()
        let c = CodeHighlighter.highlightLines("a = 1 /* x\nstill comment\nend */ b", language: "js")
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(tokens(c[1]), ["<still comment>"])
        XCTAssertEqual(tokens(c[2]).first, "<end */>")
        let py = CodeHighlighter.highlightLines("s = \"\"\"doc\nmore\n\"\"\"\nx = 2", language: "python")
        XCTAssertEqual(tokens(py[1]), ["<more>"])
        XCTAssertEqual(tokens(py[2]), ["<\"\"\">"])
        XCTAssertEqual(tokens(py[3]), ["x = ", "<2>"])
        let js = CodeHighlighter.highlightLines("const t = `a\nb ${x}`;\nlet y", language: "js")
        XCTAssertEqual(tokens(js[1]), ["<b ${x}`>", ";"])
        XCTAssertEqual(tokens(js[2]).first, "<let>")
    }

    /// 流式出字：前面的行着出来的颜色不因为后面来了字而变
    func testEarlierLinesStableWhileStreaming() {
        let code = PerfReplayTests.pythonCode(lines: 40)
        let final = CodeHighlighter.highlightLines(code, language: "python")
        var acc = ""
        for ch in code {
            acc.append(ch)
            let lines = CodeHighlighter.highlightLines(acc, language: "python")
            for k in 0..<(lines.count - 1) { XCTAssertEqual(lines[k], final[k], "第 \(k) 行在第 \(acc.count) 个字时变了") }
        }
    }
}

/// 设计评审 1：放不下的代码、公式右端渐隐，滚到最右去掉；滚到头右边留 12
@MainActor
final class OverflowFadeTests: XCTestCase {
    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { ($0 as? NSScrollView).map { [$0] } ?? [] } + view.subviews.flatMap { scrollViews(in: $0) }
    }

    /// 代码那一行最右边 4 点的字比往左 40 点处淡得多；滚到最右以后一样浓
    func testCodeFadesAtTheRightEdgeUntilScrolledToTheEnd() throws {
        let line = String(repeating: "M", count: 80)
        let host = Offscreen.host(CodeBlockView(language: "text", code: line, style: TestTheme.panel).frame(width: 300).background(Color.white), dark: false)
        Offscreen.fit(host)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        func inkNear(_ rep: NSBitmapImageRep, x: CGFloat, width: CGFloat = 4) -> Double {
            // 代码那一行：标题 28 + 发丝线 1 + 上边 12，再往下 5 点
            let y = Int((28 + 1 + 12 + 5) * 2)
            var sum = 0.0
            for px in Int(x * 2)..<Int((x + width) * 2) { sum += 1 - (rep.colorAt(x: px, y: y)?.brightnessComponent ?? 1) }
            return sum
        }
        // 代码块的底色（hover，4% 黑）本身每 4 点有 0.3 左右
        let background = 0.35
        let before = Offscreen.bitmap(host)
        let edge = inkNear(before, x: 300 - 6) - background, inner = inkNear(before, x: 300 - 60) - background
        XCTAssertGreaterThan(inner, 1, "那一行有字")
        XCTAssertLessThan(edge, inner * 0.5, "右端渐隐")
        let sv = try XCTUnwrap(Self.scrollViews(in: host).first { ($0.documentView?.frame.width ?? 0) > $0.contentView.bounds.width + 1 })
        sv.contentView.scroll(to: NSPoint(x: sv.documentView!.frame.width - sv.contentView.bounds.width, y: 0))
        sv.reflectScrolledClipView(sv.contentView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        let after = Offscreen.bitmap(host)
        // 滚到头：最后一个字右边是 12 点的空，再往左一点就是字，不淡
        XCTAssertLessThan(inkNear(after, x: 300 - 10), background, "右边留空")
        XCTAssertGreaterThan(inkNear(after, x: 300 - 22) - background, inner * 0.7, "滚到头不再渐隐")
    }

    func testFadeOnlyWhenWiderAndNotAtEnd() {
        XCTAssertFalse(ScrollGeometry(viewport: 300, content: 280, offset: 0).showsFade)
        XCTAssertTrue(ScrollGeometry(viewport: 300, content: 600, offset: 0).showsFade)
        XCTAssertTrue(ScrollGeometry(viewport: 300, content: 600, offset: 200).showsFade)
        XCTAssertFalse(ScrollGeometry(viewport: 300, content: 600, offset: 300).showsFade)
    }
}
