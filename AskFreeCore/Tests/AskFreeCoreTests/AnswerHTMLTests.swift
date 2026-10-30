import XCTest
@testable import AskFreeCore

final class AnswerHTMLTests: XCTestCase {
    private let renderer = AnswerHTML(math: { tex, display in let t = display ? "md" : "mi"; return "<\(t)>\(AnswerHTML.escape(tex))</\(t)>" },
                                      code: { lang, code in lang == "swift" ? "<k>\(AnswerHTML.escape(code))</k>" : nil })

    func testBulletsBecomeOneListAndInlineMarkupIsConverted() {
        let html = renderer.html("- 第一条 **重点** 和 `a<b`\n- 第二条 *斜* 与 [链接](https://example.com)")
        XCTAssertEqual(html.components(separatedBy: "<ul class=\"pts\">").count, 2)
        XCTAssertTrue(html.contains("<strong>重点</strong>"))
        XCTAssertTrue(html.contains("<code>a&lt;b</code>"), "行内代码里的 < 要转义，里面的字不再当 Markdown")
        XCTAssertTrue(html.contains("<em>斜</em>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\""))
    }

    func testStarsInsideCodeAndMathAreLeftAlone() {
        let html = renderer.html("- `a ** b ** c` 与 $x**2$")
        XCTAssertTrue(html.contains("<code>a ** b ** c</code>"))
        XCTAssertTrue(html.contains("<mi>x**2</mi>"))
        XCTAssertFalse(html.contains("<strong>"))
    }

    func testJavascriptLinksAndHTMLInTextAreNotLive() {
        let html = renderer.html("- [点我](javascript:alert(1)) <script>alert(1)</script>")
        XCTAssertFalse(html.contains("href=\"javascript"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testDisplayMathAndCodeFollowingAnItemStayInsideTheList() {
        let md = "1. 先算：\n\n$$\\frac{a}{b}$$\n\n2. 再写：\n\n```swift\nlet x = 1 < 2\n```\n"
        let html = renderer.html(md)
        XCTAssertTrue(html.contains("<li class=\"blk\"><div class=\"scrollx math\"><md>\\frac{a}{b}</md></div></li>"))
        XCTAssertTrue(html.contains("<li class=\"blk\"><div class=\"code\">"))
        XCTAssertTrue(html.contains("<span>Swift</span>"))
        XCTAssertTrue(html.contains("<code><k>let x = 1 &lt; 2</k></code>"), "着色器给的 HTML 原样放进去")
        XCTAssertEqual(html.components(separatedBy: "<ul class=\"pts\">").count, 2, "一个列表")
    }

    func testCodeWithoutLanguageIsLabelledAndEscaped() {
        let html = renderer.html("```\n<div>&</div>\n```")
        XCTAssertTrue(html.contains("<span>代码</span>"))
        XCTAssertTrue(html.contains("&lt;div&gt;&amp;&lt;/div&gt;"))
    }

    func testMathThatCannotBeTypesetShowsItsSource() {
        let none = AnswerHTML(math: { _, _ in nil })
        XCTAssertTrue(none.html("- 行内 $\\bad{$").contains("<code class=\"texsrc\">"))
        XCTAssertTrue(none.html("$$\n\\bad{\n$$").contains("<pre class=\"texsrc\">"))
    }

    func testParagraphsAndHeadings() {
        let html = renderer.html("### 小标题\n\n一段话，\n接着写。")
        XCTAssertTrue(html.contains("<p class=\"hd3\">小标题</p>"))
        XCTAssertTrue(html.contains("<p class=\"para\">一段话， 接着写。</p>"))
    }
}
