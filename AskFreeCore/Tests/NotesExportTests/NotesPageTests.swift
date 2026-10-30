import XCTest
@testable import NotesExport
@testable import AskFreeCore

final class NotesPageTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func fixture(items: Int = 3, summary: String = "今天三件事。") -> (HistoryDay, DayNotes) {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 10, minute: 12))!
        var threads: [AskHistoryThread] = []
        for i in 0..<3 {
            let at = base.addingTimeInterval(Double(i) * 3600)
            let question = i == 1 ? "这个 <script> 怎么用？" : "问题 \(i + 1)"
            let turn = AskHistoryTurn(id: "tu\(i)", thread: "th\(i)", at: at, question: question, answer: "答",
                                      hasScreenshot: i != 2, via: i == 2 ? "type" : "screen")
            threads.append(AskHistoryThread(id: "th\(i)", turns: [turn]))
        }
        let day = HistoryDay.group(threads, calendar: calendar)[0]
        var notes = DayNotes.begin(day)
        let points = [
            "- 先算 $\\frac{a}{b}$ 再看：\n\n$$\\sum_{i=1}^{n} x_i = \\int_0^1 f(x)\\,dx$$\n- 第二条 **重点**",
            "- 看这段：\n\n```swift\nstruct A { let x = 1 // 注释\n  var s = \"串\" }\n```\n- 坏公式 $\\badcommand{$ 还在",
            "- 只有文字 `code`",
        ]
        for i in 0..<items {
            notes.put(DayNoteItem(id: "th\(i)", turnID: "tu\(i)", title: "题名\(i + 1)", points: points[i]))
        }
        notes.summary = summary
        notes.keep = ["记 $x^2$", "再记一条"]
        return (day, notes)
    }

    private func page(_ day: HistoryDay, _ notes: DayNotes) -> String {
        NotesPage.html(notes: notes, day: day, screenshot: { $0.turns[0].hasScreenshot ? Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]) : nil },
                       exportedAt: calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12, minute: 40))!, calendar: calendar)
    }

    func testKaTeXTypesetsInsideJavaScriptCore() {
        let html = KaTeXRenderer.shared.render("\\frac{a}{b}", display: false)
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("class=\"katex\""))
        XCTAssertTrue(html!.contains("mfrac"))
        XCTAssertTrue(KaTeXRenderer.shared.render("x^2", display: true)!.contains("katex-display"))
        XCTAssertNil(KaTeXRenderer.shared.render("\\badcommand{", display: false), "TeX 写错不抛、返回 nil，由调用方显示源码")
        XCTAssertNil(KaTeXRenderer.shared.render("\\href{javascript:alert(1)}{x}", display: false) .flatMap { $0.contains("javascript") ? $0 : nil }, "不信任的命令不出链接")
    }

    func testKaTeXFontsAreInlinedAsDataURLs() throws {
        let css = try XCTUnwrap(KaTeXRenderer.inlineCSS())
        XCTAssertTrue(css.contains("data:font/woff2;base64,"))
        XCTAssertFalse(css.contains("url(fonts/"), "不再引用相对路径的字体")
        XCTAssertFalse(css.contains("http://") || css.contains("https://"))
    }

    func testPageIsSelfContainedWithEverythingInlined() {
        let (day, notes) = fixture()
        let html = page(day, notes)
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<title>2026-10-29 Ask Free 笔记</title>"))
        XCTAssertTrue(html.contains("<h1>10 月 29 日 周四的问答笔记</h1>"))
        XCTAssertTrue(html.contains("2026 年 · 3 个问题 · 10:12 到 12:12"))
        XCTAssertTrue(html.contains("<img src=\"data:image/jpeg;base64,"))
        XCTAssertTrue(html.contains("data:font/woff2;base64,"))
        // 离线：不引用任何网上的东西、也没有外部脚本和样式
        XCTAssertFalse(html.contains("<script src"))
        XCTAssertFalse(html.contains("<link "))
        XCTAssertNil(html.range(of: #"(src|href)="https?://"#, options: .regularExpression))
        XCTAssertNil(html.range(of: #"url\((?!data:)"#, options: .regularExpression), "CSS 里没有指向外面的 url()")
    }

    func testSectionsSummaryAndTableOfContents() {
        let (day, notes) = fixture()
        let html = page(day, notes)
        for n in 1...3 { XCTAssertTrue(html.contains("<section class=\"sec\" id=\"t\(n)\">")); XCTAssertTrue(html.contains("href=\"#t\(n)\"")) }
        XCTAssertTrue(html.contains("今天三件事。"))
        XCTAssertTrue(html.contains("记住这几条"))
        XCTAssertTrue(html.contains("10:12 · 看屏幕问"))
        XCTAssertTrue(html.contains("12:12 · 打字问"))
        XCTAssertTrue(html.contains("这个 &lt;script&gt; 怎么用？"), "问题里的 HTML 不能当真")
        XCTAssertFalse(html.contains("<script>怎么"))
        XCTAssertEqual(html.components(separatedBy: "<figure class=\"shot\">").count - 1, 2, "打字问的没有截图，不留空框")
        XCTAssertTrue(html.contains("class=\"qb solo\""))
        XCTAssertTrue(html.contains("Ask Free 整理 · 2026-10-30 12:40 导出 · 截图里的红框是提问时指着的地方"))
    }

    func testNoUiOnlyThingsAreExported() {
        let html = page(fixture().0, fixture().1)
        for word in ["已在 Anki", "在历史里看", "导入 Anki", "type=\"checkbox\""] { XCTAssertFalse(html.contains(word), word) }
    }

    func testFormulasAreTypesetAndCodeIsHighlightedAndBadMathShowsSource() {
        let (day, notes) = fixture()
        let html = page(day, notes)
        XCTAssertTrue(html.contains("class=\"katex\""))
        XCTAssertTrue(html.contains("katex-display"))
        XCTAssertTrue(html.contains("<span class=\"k\">struct</span>"))
        XCTAssertTrue(html.contains("<span class=\"c\">// 注释</span>"))
        XCTAssertTrue(html.contains("<span class=\"s\">\"串\"</span>") || html.contains("<span class=\"s\">&quot;串&quot;</span>"))
        XCTAssertTrue(html.contains("<code class=\"texsrc\">\\badcommand{</code>"))
        XCTAssertTrue(html.contains("<span>Swift</span>"))
    }

    func testPartialNotesExportOnlyFinishedQuestionsAndSaySo() {
        let (day, notes) = fixture(items: 2, summary: "")
        let html = page(day, notes)
        XCTAssertTrue(html.contains("2 个问题（这一天问了 3 个，其余没整理）"))
        XCTAssertFalse(html.contains("id=\"t3\""))
        XCTAssertFalse(html.contains("记住这几条"))
    }

    func testPageWithoutFormulasCarriesNoKaTeXFonts() {
        let (day, _) = fixture()
        var notes = DayNotes.begin(day)
        notes.put(DayNoteItem(id: "th0", turnID: "tu0", title: "一", points: "- 只有字"))
        notes.summary = "小结"
        let html = page(day, notes)
        XCTAssertFalse(html.contains("data:font/woff2"))
        XCTAssertLessThan(html.utf8.count, 60_000)
    }

    func testFileName() {
        XCTAssertEqual(NotesPage.fileName(day: "2026-10-29", ext: "pdf"), "2026-10-29 Ask Free 笔记.pdf")
    }
}
