import XCTest
@testable import AskFreeCore

final class DayNotesPromptTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func day(_ questions: [(String, String)]) -> HistoryDay {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9))!
        let threads = questions.enumerated().map { i, qa in
            AskHistoryThread(id: "th\(i)", turns: [AskHistoryTurn(id: "tu\(i)", thread: "th\(i)", at: base.addingTimeInterval(Double(i) * 3600),
                                                                  question: qa.0, answer: qa.1, hasScreenshot: true)])
        }
        return HistoryDay.group(threads, calendar: calendar)[0]
    }

    // MARK: 请求

    func testQuestionsAreNumberedFromOneWithTheirTime() {
        let qs = DayNotesPrompt.questions(for: day([("一", "答一"), ("二", "答二")]), calendar: calendar)
        XCTAssertEqual(qs.map(\.index), [1, 2])
        XCTAssertEqual(qs.map(\.time), ["09:00", "10:00"])
        XCTAssertEqual(qs.map(\.turnID), ["tu0", "tu1"])
    }

    func testLongAnswersAreClippedAtAParagraphAndWholeRequestStaysBounded() {
        let para = String(repeating: "字", count: 400)
        let long = (0..<30).map { _ in para }.joined(separator: "\n")
        let qs = DayNotesPrompt.questions(for: day(Array(repeating: ("问", long), count: 40)), calendar: calendar)
        let request = DayNotesPrompt.request(todo: qs, total: 40, dayLabel: "2026-10-29")
        XCTAssertLessThan(request.user.count, 75_000)
        XCTAssertTrue(request.user.contains("（后面省略）"))
        XCTAssertLessThanOrEqual(request.maxTokens, 8000, "会员后台最多放 8192")
    }

    func testRequestMentionsOnlyTheRemainingQuestionsWhenResuming() {
        let qs = DayNotesPrompt.questions(for: day([("甲", "答甲"), ("乙", "答乙"), ("丙", "答丙")]), calendar: calendar)
        let request = DayNotesPrompt.request(todo: [qs[2]], total: 3, dayLabel: "2026-10-29", finishedTitles: [(1, "甲题"), (2, "乙题")])
        XCTAssertTrue(request.user.contains("### 问题 3（11:00）"))
        XCTAssertFalse(request.user.contains("### 问题 1"))
        XCTAssertTrue(request.user.contains("1. 甲题；2. 乙题"))
    }

    func testEnglishQuestionsAskForEnglishNotesButChineseDoesNot() {
        let en = DayNotesPrompt.questions(for: day([("What does marginalize mean in this paper?", "a"), ("How do I rebase onto main without losing commits?", "b"), ("为什么", "c")]), calendar: calendar)
        XCTAssertEqual(DayNotesPrompt.languageName(of: en), "English")
        let zh = DayNotesPrompt.questions(for: day([("这是什么", "a"), ("怎么办", "b")]), calendar: calendar)
        XCTAssertNil(DayNotesPrompt.languageName(of: zh))
        let request = DayNotesPrompt.request(todo: en, total: 3, dayLabel: "d", language: "English")
        XCTAssertTrue(request.system.contains("Write the whole notes"))
    }

    func testFollowUpsAreIncludedWithTheirAnswers() {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9))!
        let t = AskHistoryThread(id: "a", turns: [
            AskHistoryTurn(id: "a0", thread: "a", at: base, question: "首问", answer: "首答"),
            AskHistoryTurn(id: "a1", thread: "a", at: base.addingTimeInterval(60), question: "再问", answer: "再答"),
        ])
        let qs = DayNotesPrompt.questions(for: HistoryDay.group([t], calendar: calendar)[0], calendar: calendar)
        let user = DayNotesPrompt.request(todo: qs, total: 1, dayLabel: "d").user
        XCTAssertTrue(user.contains("追问1：再问"))
        XCTAssertTrue(user.contains("追问1的回答：再答"))
    }

    // MARK: 读回来

    func testParsesItemsSummaryAndKeep() {
        let text = """
        ## 1
        标题：rebase 冲突里的记号
        - `<<<<<<< HEAD` 到 `=======` 是你这边的代码。
        - 改完 `git add` 再 `git rebase --continue`。

        ## 2
        标题：二
        - 要点 $x^2$

        ## 小结
        今天弄明白了两件事。
        第二行。

        ## 记住
        - 第一条
        * 第二条
        3. 第三条
        """
        let r = DayNotesParser.parse(text, final: true)
        XCTAssertEqual(r.items.map(\.index), [1, 2])
        XCTAssertEqual(r.items[0].title, "rebase 冲突里的记号")
        XCTAssertEqual(r.items[0].points, "- `<<<<<<< HEAD` 到 `=======` 是你这边的代码。\n- 改完 `git add` 再 `git rebase --continue`。")
        XCTAssertEqual(r.summary, "今天弄明白了两件事。\n第二行。")
        XCTAssertEqual(r.keep, ["第一条", "第二条", "第三条"])
    }

    func testWhileStreamingOnlyClosedSectionsCount() {
        let partial = "## 1\n标题：一\n- 甲\n\n## 2\n标题：二\n- 乙"
        XCTAssertEqual(DayNotesParser.parse(partial, final: false).items.map(\.index), [1], "最后一节还在长，不算")
        XCTAssertEqual(DayNotesParser.parse(partial, final: true).items.map(\.index), [1, 2])
    }

    func testHeadersInsideCodeFencesAreNotSections() {
        let text = "## 1\n标题：脚本\n- 要点\n```bash\n## 2 这是注释\necho hi\n```\n- 后面还有\n## 小结\n好"
        let r = DayNotesParser.parse(text, final: true)
        XCTAssertEqual(r.items.map(\.index), [1])
        XCTAssertTrue(r.items[0].points.contains("## 2 这是注释"))
        XCTAssertTrue(r.items[0].points.hasSuffix("- 后面还有"))
    }

    func testWholeAnswerWrappedInAFenceIsUnwrapped() {
        let r = DayNotesParser.parse("```markdown\n## 1\n标题：一\n- 甲\n## 小结\n好\n```", final: true)
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.summary, "好")
    }

    func testLenientHeadersAndTitles() {
        let r = DayNotesParser.parse("### 1. 随便\n**标题**：粗体题名\n- a\n## 问题 2\n- 没有标题行\n## 2026 年的事\n- 不是节", final: true)
        XCTAssertEqual(r.items.map(\.index), [1, 2])
        XCTAssertEqual(r.items[0].title, "粗体题名")
        XCTAssertEqual(r.items[1].title, "")
        XCTAssertEqual(r.items[1].points, "- 没有标题行")
    }

    func testSectionWithoutPointsIsDroppedAndGarbageHasNoSection() {
        XCTAssertEqual(DayNotesParser.parse("## 1\n标题：空", final: true).items, [])
        XCTAssertFalse(DayNotesParser.parse("好的，下面是笔记……", final: true).sawSection)
    }

    func testFallbackTitleCutsALongQuestion() {
        XCTAssertEqual(DayNotesGenerator.fallbackTitle("短问题"), "短问题")
        XCTAssertEqual(DayNotesGenerator.fallbackTitle(String(repeating: "长", count: 40)), String(repeating: "长", count: 16) + "…")
    }
}
