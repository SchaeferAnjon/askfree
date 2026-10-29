import XCTest
@testable import AskFreeCore

final class AnswerBlocksTests: XCTestCase {
    private func parse(_ md: String, streaming: Bool = false) -> [AnswerBlock] { AnswerBlocks.parse(md, streaming: streaming) }

    // MARK: - 和原来的 AnswerText 拆法一致

    /// 原来 AnswerPanel.AnswerText 的拆块，原样抄过来当期望
    private func legacyBlocks(_ text: String) -> [AnswerBlock] {
        var out: [AnswerBlock] = []
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para.removeAll() } }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { out.append(.heading(title)) }
                continue
            }
            if let r = line.range(of: #"^(?:[-•·*]|\d+[.、)）])\s+"#, options: .regularExpression) {
                flush()
                let marker = String(line[r.lowerBound..<r.upperBound]).trimmingCharacters(in: .whitespaces)
                let body = String(line[r.upperBound...])
                if marker.first?.isNumber == true {
                    out.append(.numbered(marker.trimmingCharacters(in: CharacterSet(charactersIn: ".、)）")) + ".", body))
                } else {
                    out.append(.bullet(body))
                }
            } else {
                para.append(line)
            }
        }
        flush()
        return out
    }

    func testPlainMarkdownSplitsLikeBefore() {
        let samples = [
            "先说结论。\n\n### 原因\n\n- **少装了** sharp\n* 版本不对\n• 圆点\n\n\n1、 先装\n2) 再跑\n3） 第三\n10. 第十",
            "第一行\n第二行接着\n\n  缩进的段落  \n# \n#没有空格的标题\n- \n-不是条目",
            "",
            "\n\n\n",
            "**加粗开头**的段落\n`行内代码` 开头\n[链接](https://example.com)",
        ]
        for md in samples {
            XCTAssertEqual(parse(md), legacyBlocks(md), md)
            XCTAssertEqual(parse(md, streaming: true).filter { $0 != .pending }, legacyBlocks(md), md)
        }
    }

    // MARK: - 代码块

    func testCodeBlockWithLanguage() {
        XCTAssertEqual(parse("看：\n\n```python\nprint(1)\n```\n\n完。"),
                       [.paragraph("看："), .code(language: "python", code: "print(1)", attachedTo: nil), .paragraph("完。")])
    }

    func testCodeKeepsIndentBlankLinesAndMarkdownLookalikes() {
        let md = "```bash\n# 注释\n- x\n1. x\n\n  缩进\n**不加粗**\n```"
        XCTAssertEqual(parse(md), [.code(language: "bash", code: "# 注释\n- x\n1. x\n\n  缩进\n**不加粗**", attachedTo: nil)])
    }

    func testFourBacktickFenceKeepsThreeBacktickLines() {
        let md = "````markdown\n```js\nx\n```\n````\n后面"
        XCTAssertEqual(parse(md), [.code(language: "markdown", code: "```js\nx\n```", attachedTo: nil), .paragraph("后面")])
    }

    func testIndentedFenceUnderListItemDropsIndentAndAttaches() {
        let md = "1. 装依赖：\n   ```bash\n   npm install\n     --save\n   ```\n- 圆点\n\n  ```\n  ls\n  ```"
        XCTAssertEqual(parse(md), [
            .numbered("1.", "装依赖："),
            .code(language: "bash", code: "npm install\n  --save", attachedTo: .numbered),
            .bullet("圆点"),
            .code(language: "", code: "ls", attachedTo: .bullet),
        ])
    }

    func testLanguageNameSanitized() {
        XCTAssertEqual(parse("```c++\nx\n```"), [.code(language: "c++", code: "x", attachedTo: nil)])
        XCTAssertEqual(parse("```py title=\"a.py\"\nx\n```"), [.code(language: "py", code: "x", attachedTo: nil)])
        XCTAssertEqual(parse("```<script>\nx\n```"), [.code(language: "", code: "x", attachedTo: nil)])
        XCTAssertEqual(parse("```abcdefghijklmnopqrstuvwxyz\nx\n```"), [.code(language: "", code: "x", attachedTo: nil)])
    }

    func testUnclosedCodeBlockStaysCodeBlock() {
        let md = "```swift\nlet a = 1\nlet b = 2"
        XCTAssertEqual(parse(md), [.code(language: "swift", code: "let a = 1\nlet b = 2", attachedTo: nil)])
        XCTAssertEqual(parse(md, streaming: true), [.code(language: "swift", code: "let a = 1\nlet b = 2", attachedTo: nil)])
    }

    func testFenceLineNotFinishedIsPendingWhileStreaming() {
        XCTAssertEqual(parse("看：\n```pyt", streaming: true), [.paragraph("看："), .pending])
        // 换行到了：代码块和语言名一起出来，先按一行留位置
        XCTAssertEqual(parse("看：\n```python\n", streaming: true), [.paragraph("看："), .code(language: "python", code: "", attachedTo: nil)])
    }

    func testPossibleClosingFenceHiddenWhileStreaming() {
        XCTAssertEqual(parse("```\nls\n`", streaming: true), [.code(language: "", code: "ls", attachedTo: nil)])
        XCTAssertEqual(parse("```\nls\n``", streaming: true), [.code(language: "", code: "ls", attachedTo: nil)])
        XCTAssertEqual(parse("```\nls\n```", streaming: true), [.code(language: "", code: "ls", attachedTo: nil)])
        // 末尾的空行先不显示：收尾前后高度一样
        XCTAssertEqual(parse("```\nls\n", streaming: true), [.code(language: "", code: "ls", attachedTo: nil)])
    }

    func testEmptyUnclosedFenceDroppedWhenDone() {
        XCTAssertEqual(parse("看：\n```python"), [.paragraph("看：")])
        XCTAssertEqual(parse("看：\n```python\n\n"), [.paragraph("看：")])
        XCTAssertEqual(parse("```\n```"), [])
    }

    func testOneOrTwoBackticksAtEndHiddenWhileStreaming() {
        XCTAssertEqual(parse("看：\n``", streaming: true), [.paragraph("看：")])
        XCTAssertEqual(parse("看：\n``", streaming: false), [.paragraph("看：\n``")])
    }

    // MARK: - 独立公式

    func testDisplayMathOnOneLine() {
        XCTAssertEqual(parse("推出：\n\n$$x=\\frac{-b}{2a}$$\n\n完。"),
                       [.paragraph("推出："), .math(tex: "x=\\frac{-b}{2a}", attachedTo: nil), .paragraph("完。")])
    }

    func testDisplayMathAcrossLines() {
        XCTAssertEqual(parse("$$\na + b\n\n= c\n$$"), [.math(tex: "a + b\n\n= c", attachedTo: nil)])
        XCTAssertEqual(parse("\\[\nE = mc^2\n\\]"), [.math(tex: "E = mc^2", attachedTo: nil)])
    }

    func testTextAfterClosingDelimiterIsNewLine() {
        XCTAssertEqual(parse("$$x^2$$ 是面积\n- 条目"), [.math(tex: "x^2", attachedTo: nil), .paragraph("是面积"), .bullet("条目")])
    }

    func testUnclosedDisplayMath() {
        XCTAssertEqual(parse("前面\n$$\\frac{a", streaming: true), [.paragraph("前面"), .pending])
        XCTAssertEqual(parse("前面\n$$\\frac{a", streaming: false), [.paragraph("前面"), .paragraph("$$\\frac{a")])
    }

    func testTooLongUnclosedDisplayMathShownAsText() {
        let long = "$$" + String(repeating: "x", count: 501)
        XCTAssertEqual(parse(long, streaming: true), [.paragraph(long)])
        let manyLines = "$$\n" + Array(repeating: "x", count: 15).joined(separator: "\n")
        XCTAssertEqual(parse(manyLines, streaming: true), [.paragraph(manyLines)])
        XCTAssertEqual(parse(manyLines, streaming: false), [.paragraph(manyLines)])
        let fewLines = "$$\n" + Array(repeating: "x", count: 13).joined(separator: "\n")
        XCTAssertEqual(parse(fewLines, streaming: true), [.pending])
    }

    func testDisplayMathAttachesToListUntilParagraph() {
        let md = "1. 两边除以 $a$：\n\n$$x^2=0$$\n\n```\nx\n```\n\n$$y$$\n\n普通段落\n\n$$z$$\n\n- 圆点\n$$w$$"
        XCTAssertEqual(parse(md), [
            .numbered("1.", "两边除以 $a$："),
            .math(tex: "x^2=0", attachedTo: .numbered),
            .code(language: "", code: "x", attachedTo: .numbered),
            .math(tex: "y", attachedTo: .numbered),
            .paragraph("普通段落"),
            .math(tex: "z", attachedTo: nil),
            .bullet("圆点"),
            .math(tex: "w", attachedTo: .bullet),
        ])
        XCTAssertEqual(parse("### 小标题\n$$a$$"), [.heading("小标题"), .math(tex: "a", attachedTo: nil)])
    }

    func testDollarsInsideParagraphAreInline() {
        XCTAssertEqual(parse("面积是 $$x^2$$ 平方米"), [.paragraph("面积是 $$x^2$$ 平方米")])
    }

    // MARK: - 行内

    func testInlineMathDelimiters() {
        XCTAssertEqual(AnswerBlocks.inline("设 $x$ 为"), [.text("设 "), .math("x"), .text(" 为")])
        XCTAssertEqual(AnswerBlocks.inline("设 \\(x^2\\) 为"), [.text("设 "), .math("x^2"), .text(" 为")])
        XCTAssertEqual(AnswerBlocks.inline("得 $$\\pi$$ 了"), [.text("得 "), .math("\\pi"), .text(" 了")])
        XCTAssertEqual(AnswerBlocks.inline("$a$$b$"), [.math("a"), .math("b")])
    }

    func testDollarsThatAreNotMath() {
        for s in ["$5 and $10", "costs $5.", "$ x$", "$x $", "$x$5", "单独一个 $"] {
            XCTAssertEqual(AnswerBlocks.inline(s), [.text(s)], s)
        }
        XCTAssertEqual(AnswerBlocks.inline("价格 \\$5，$y$"), [.text("价格 $5，"), .math("y")])
        XCTAssertEqual(AnswerBlocks.inline("$5 and $x$"), [.text("$5 and "), .math("x")])
    }

    func testBackticksProtectDollars() {
        XCTAssertEqual(AnswerBlocks.inline("运行 `echo $HOME` 和 ``a`$b$`c``"), [.text("运行 `echo $HOME` 和 ``a`$b$`c``")])
        // 没闭合的反引号是普通字，后面照样找公式
        XCTAssertEqual(AnswerBlocks.inline("` 然后 $x$"), [.text("` 然后 "), .math("x")])
    }

    func testFormulaSourceKeptVerbatim() {
        let tex = "50\\% + a\\\\b + \\, + \\{x\\} + a*b*c + x_1 + y_2"
        XCTAssertEqual(AnswerBlocks.inline("看 $\(tex)$ 吧"), [.text("看 "), .math(tex), .text(" 吧")])
        XCTAssertEqual(AnswerBlocks.inline("\\(a \\\\ b\\)"), [.math("a \\\\ b")])
    }

    func testPrivateUseCharactersRemoved() {
        XCTAssertEqual(AnswerBlocks.inline("a\u{E000}b$x$\u{F8FF}"), [.text("ab"), .math("x")])
    }

    // MARK: - 流式时先不显示

    func testStreamingHidesUnclosedInlineMath() {
        let cases: [(String, String)] = [
            ("面积 \\", "面积 "),
            ("面积 $", "面积 "),
            ("面积 \\(x^2\\", "面积 "),
            ("面积 $\\frac{a", "面积 "),
            ("面积 $$\\int", "面积 "),
            ("有 $x$ 和 $y", "有 $x$ 和 "),
        ]
        for (md, shown) in cases {
            XCTAssertEqual(parse("前面一段\n\n" + md, streaming: true), [.paragraph("前面一段"), .paragraph(shown)], md)
        }
    }

    func testStreamingKeepsPricesAndClosedFormulas() {
        XCTAssertEqual(parse("花了 $5 美元", streaming: true), [.paragraph("花了 $5 美元")])
        XCTAssertEqual(parse("$x$ 和 $y$", streaming: true), [.paragraph("$x$ 和 $y$")])
        XCTAssertEqual(parse("`$HOME 没闭合", streaming: true), [.paragraph("`$HOME 没闭合")])
        // 已经换行的那一行不算最后一行：照常显示
        XCTAssertEqual(parse("开了 $x\n下一行", streaming: true), [.paragraph("开了 $x\n下一行")])
    }

    func testStreamingGivesUpAfter200HiddenCharacters() {
        let tail = "$" + String(repeating: "a", count: 201)
        XCTAssertEqual(parse("看 " + tail, streaming: true), [.paragraph("看 " + tail)])
        let short = "$" + String(repeating: "a", count: 150)
        XCTAssertEqual(parse("看 " + short, streaming: true), [.paragraph("看 ")])
    }

    func testStreamingHiddenTailInsideListItem() {
        XCTAssertEqual(parse("- 条目 $\\alpha", streaming: true), [.bullet("条目 ")])
        XCTAssertEqual(parse("### 小标题 \\(", streaming: true), [.heading("小标题")])
    }

    /// 每个前缀：前面的块和下一个前缀里一模一样，只有最后一块会长、会换类型
    func testEarlierBlocksNeverChangeWhileStreaming() {
        let md = "一元二次方程 $ax^2+bx+c=0$ 的解：\n\n1. 配方：\n\n$$x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}$$\n\n2. 代码：\n```python\nimport math\n\ndef f(a):\n    return a ** 2\n```\n\n- 结束 \\(x\\) 和 `$HOME`\n\n\\[\ny = 1\n\\]\n完"
        var previous: [AnswerBlock] = []
        for n in 0...md.count {
            let blocks = parse(String(md.prefix(n)), streaming: true)
            if previous.count > 1 {
                XCTAssertGreaterThanOrEqual(blocks.count, previous.count - 1, "prefix \(n)")
                for k in 0..<(previous.count - 1) where k < blocks.count {
                    XCTAssertEqual(blocks[k], previous[k], "prefix \(n) block \(k)")
                }
            }
            previous = blocks
        }
    }
}
