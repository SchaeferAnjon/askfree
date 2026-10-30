import XCTest
@testable import AskFreeCore

/// 假的模型：按预设的文字分几段「流」出来
private final class FakeAI: NotesCompleting {
    var chunks: [String] = []
    var failure: Error?
    /// 流是怎么结束的：stop；"length" = 输出到 max_tokens 被截断
    var finishReason: String? = "stop"
    private(set) var requests: [(system: String, user: String, maxTokens: Int, member: String?)] = []

    func complete(system: String, user: String, maxTokens: Int, member: AskMember?,
                  onPartial: ((String) -> Void)?, onFinishReason: ((String?) -> Void)?, completion: @escaping (Result<String, Error>) -> Void) -> AskRequestHandle {
        requests.append((system, user, maxTokens, member?.useId))
        var text = ""
        for chunk in chunks {
            text += chunk
            onPartial?(text)
        }
        if let failure { completion(.failure(failure)) } else { onFinishReason?(finishReason); completion(.success(text)) }
        return AskRequestHandle()
    }
}

final class DayNotesGeneratorTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func day(_ n: Int) -> HistoryDay {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9))!
        let threads = (0..<n).map { i in
            AskHistoryThread(id: "th\(i)", turns: [AskHistoryTurn(id: "tu\(i)", thread: "th\(i)", at: base.addingTimeInterval(Double(i) * 3600),
                                                                  question: "问题\(i + 1)", answer: "回答\(i + 1)", hasScreenshot: true)])
        }
        return HistoryDay.group(threads, calendar: calendar)[0]
    }

    private func run(_ ai: FakeAI, day: HistoryDay, resume: DayNotes? = nil, member: AskMember? = nil) -> (updates: [DayNotes], result: Result<DayNotes, Error>) {
        let done = expectation(description: "done")
        var updates: [DayNotes] = []
        var result: Result<DayNotes, Error>!
        DayNotesGenerator(ai: ai).run(day: day, resume: resume, member: member, calendar: calendar,
                                      onUpdate: { updates.append($0) }, completion: { result = $0; done.fulfill() })
        wait(for: [done], timeout: 5)
        // onUpdate 的最后一次排在 completion 前面，已经都到了
        return (updates, result)
    }

    private let full = """
    ## 1
    标题：一题
    - 甲

    ## 2
    标题：二题
    - 乙

    ## 3
    标题：三题
    - 丙

    ## 小结
    今天三件事。

    ## 记住
    - 记一
    - 记二
    """

    func testOneRequestForTheWholeDayAndProgressTicksPerQuestion() throws {
        let ai = FakeAI()
        ai.chunks = ["## 1\n标题：一题\n- 甲\n\n## 2\n标", "题：二题\n- 乙\n\n## 3\n标题：三题\n- 丙\n\n", "## 小结\n今天三件事。\n\n## 记住\n- 记一\n- 记二"]
        let (updates, result) = run(ai, day: day(3))
        XCTAssertEqual(ai.requests.count, 1, "一天一个请求")
        XCTAssertEqual(updates.map { $0.items.count }, [1, 2, 3], "每收尾一节回调一次：第 2 节在第二段里收尾，第 3 节在第三段（遇到「## 小结」）收尾")
        let notes = try result.get()
        XCTAssertEqual(notes.items.map(\.title), ["一题", "二题", "三题"])
        XCTAssertEqual(notes.items.map(\.turnID), ["tu0", "tu1", "tu2"])
        XCTAssertEqual(notes.summary, "今天三件事。")
        XCTAssertEqual(notes.keep, ["记一", "记二"])
        XCTAssertTrue(notes.status(against: day(3)).isComplete)
    }

    func testMemberUseIdIsPassedThrough() {
        let ai = FakeAI()
        ai.chunks = [full]
        let member = AskMember(credentials: MemberCredentials(base: URL(string: "http://x")!, token: "t"), useId: "use-123")
        _ = run(ai, day: day(3), member: member)
        XCTAssertEqual(ai.requests.first?.member, "use-123")
    }

    func testModelStoppedShortLeavesAPartialNotesWithoutSummary() throws {
        let ai = FakeAI()
        ai.chunks = ["## 1\n标题：一题\n- 甲\n\n## 2\n标题：二题\n- 乙"]
        let notes = try run(ai, day: day(3)).result.get()
        XCTAssertEqual(notes.items.count, 2)
        XCTAssertEqual(notes.summary, "", "没整理完就不写小结")
        XCTAssertEqual(notes.status(against: day(3)).done, 2)
        XCTAssertFalse(notes.status(against: day(3)).isComplete)
    }

    func testResumeOnlyAsksForTheMissingQuestionsAndKeepsTheFinishedOnes() throws {
        let ai = FakeAI()
        ai.chunks = ["## 1\n标题：一题\n- 甲\n\n## 2\n标题：二题\n- 乙"]
        let partial = try run(ai, day: day(3)).result.get()

        let ai2 = FakeAI()
        ai2.chunks = ["## 3\n标题：三题\n- 丙\n\n## 小结\n都弄完了。\n\n## 记住\n- 记"]
        let notes = try run(ai2, day: day(3), resume: partial).result.get()
        XCTAssertTrue(ai2.requests[0].user.contains("### 问题 3"))
        XCTAssertFalse(ai2.requests[0].user.contains("### 问题 1"))
        XCTAssertTrue(ai2.requests[0].user.contains("1. 一题；2. 二题"))
        XCTAssertEqual(notes.items.map(\.title), ["一题", "二题", "三题"])
        XCTAssertEqual(notes.summary, "都弄完了。")
    }

    func testResumeKeepsNewQuestionsAskedInTheMeantime() throws {
        let ai = FakeAI()
        ai.chunks = ["## 1\n标题：一题\n- 甲\n\n## 2\n标题：二题\n- 乙\n\n## 小结\n好"]
        let first = try run(ai, day: day(2)).result.get()
        let ai2 = FakeAI()
        ai2.chunks = ["## 3\n标题：三题\n- 丙\n\n## 小结\n三个。\n\n## 记住\n- 记"]
        let notes = try run(ai2, day: day(3), resume: first).result.get()
        XCTAssertEqual(notes.covered.count, 3)
        XCTAssertEqual(notes.items.count, 3)
        XCTAssertEqual(notes.summary, "三个。")
    }

    func testMissingTitleFallsBackToTheQuestion() throws {
        let ai = FakeAI()
        ai.chunks = ["## 1\n- 只有要点\n\n## 小结\n好"]
        let notes = try run(ai, day: day(1)).result.get()
        XCTAssertEqual(notes.items[0].title, "问题1")
    }

    func testUnreadableAnswerAndNetworkFailureAreErrors() {
        let ai = FakeAI()
        ai.chunks = ["抱歉，我没法整理。"]
        if case .failure(let e) = run(ai, day: day(2)).result { XCTAssertEqual(e as? DayNotesError, .unreadable) } else { XCTFail("应当失败") }

        let ai2 = FakeAI()
        ai2.chunks = ["## 1\n标题：一题\n- 甲\n\n## 2\n标题：二"]
        ai2.failure = URLError(.networkConnectionLost)
        let (updates, result) = run(ai2, day: day(2))
        if case .failure(let e) = result { XCTAssertEqual((e as? URLError)?.code, .networkConnectionLost) } else { XCTFail("应当失败") }
        XCTAssertEqual(updates.last?.items.count, 1, "断网前已经收尾的那一节留着")
    }

    // MARK: 输出被截断

    func testTruncatedLastSectionIsNotAcceptedAsFinished() throws {
        let ai = FakeAI()
        ai.finishReason = "length"
        ai.chunks = ["## 1\n标题：一题\n- 甲\n\n## 2\n标题：二题\n- 乙要用这段\n```swift\nlet a = compute("]
        let notes = try run(ai, day: day(3)).result.get()
        XCTAssertEqual(notes.items.map(\.id), ["th0"], "被截断的第 2 节不算整理好")
        XCTAssertEqual(notes.summary, "")
        // 接着整理从第 2 个补起
        let ai2 = FakeAI()
        ai2.chunks = ["## 2\n标题：二题\n- 乙\n\n## 3\n标题：三题\n- 丙\n\n## 小结\n好\n\n## 记住\n- 记"]
        let done = try run(ai2, day: day(3), resume: notes).result.get()
        XCTAssertFalse(ai2.requests[0].user.contains("### 问题 1"))
        XCTAssertTrue(ai2.requests[0].user.contains("### 问题 2"))
        XCTAssertEqual(done.items.map(\.title), ["一题", "二题", "三题"])
        XCTAssertEqual(done.items[1].points, "- 乙")
    }

    func testTruncatedAfterAllQuestionsKeepsTheSummaryForNextTime() throws {
        let ai = FakeAI()
        ai.finishReason = "length"
        ai.chunks = ["## 1\n标题：一题\n- 甲\n\n## 小结\n好。\n\n## 记住\n- 记一\n- 记"]
        let notes = try run(ai, day: day(1)).result.get()
        XCTAssertEqual(notes.items.count, 1)
        XCTAssertEqual(notes.summary, "", "「记住」被截断了：小结也留到接着整理时一起写")
        XCTAssertEqual(notes.keep, [])
    }

    func testFinishedWithStopStillAcceptsTheLastSection() throws {
        let ai = FakeAI()
        ai.chunks = ["## 1\n标题：一题\n- 甲\n- 乙"]
        XCTAssertEqual(try run(ai, day: day(1)).result.get().items[0].points, "- 甲\n- 乙")
    }

    // MARK: 请求大小

    func testRequestStaysWithinTheBudgetAndTheRestWaitsForResume() throws {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9))!
        let long = String(repeating: "这是一段很长的回答内容。", count: 500)   // 6000 字
        let threads = (0..<60).map { i -> AskHistoryThread in
            var turns = [AskHistoryTurn(id: "tu\(i)", thread: "th\(i)", at: base.addingTimeInterval(Double(i) * 60),
                                        question: String(repeating: "问", count: 500), answer: long)]
            for f in 0..<4 {
                turns.append(AskHistoryTurn(id: "tu\(i)-\(f)", thread: "th\(i)", at: base.addingTimeInterval(Double(i) * 60 + Double(f + 1)),
                                            question: String(repeating: "追", count: 500), answer: long))
            }
            return AskHistoryThread(id: "th\(i)", turns: turns)
        }
        let big = HistoryDay.group(threads, calendar: calendar)[0]
        let ai = FakeAI()
        ai.chunks = ["## 1\n标题：一\n- 甲\n\n## 2\n标题：二\n- 乙\n\n## 小结\n不该收\n\n## 记住\n- 不该收"]
        let first = try run(ai, day: big).result.get()
        let user = ai.requests[0].user
        XCTAssertLessThanOrEqual(user.count, DayNotesPrompt.totalBudget + 5_000, "整个请求（问题、回答、追问）不超过预算：\(user.count) 字")
        XCTAssertTrue(user.contains("留到下一次"))
        XCTAssertTrue(user.contains("### 问题 1（") && !user.contains("### 问题 60（"))
        XCTAssertEqual(first.summary, "", "还有问题没整理，小结不收")
        XCTAssertEqual(first.items.count, 2)
        // 接着整理：从没整理的第一个往下，同样不超预算
        let ai2 = FakeAI()
        ai2.chunks = ["## 3\n标题：三\n- 丙"]
        _ = try run(ai2, day: big, resume: first).result.get()
        XCTAssertFalse(ai2.requests[0].user.contains("### 问题 2（"))
        XCTAssertTrue(ai2.requests[0].user.contains("### 问题 3（"))
        XCTAssertLessThanOrEqual(ai2.requests[0].user.count, DayNotesPrompt.totalBudget + 5_000)
    }

    func testFitAlwaysTakesAtLeastOneQuestion() {
        let q = NotesQuestion(index: 1, threadID: "a", turnID: "b", time: "10:00", question: "问", answer: String(repeating: "答", count: 100), followUps: [])
        XCTAssertEqual(DayNotesPrompt.fit([q, q], budget: 10).count, 1)
        XCTAssertEqual(DayNotesPrompt.fit([q, q], budget: 10_000).count, 2)
    }
}
