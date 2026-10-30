import XCTest
@testable import AskFreeCore

/// 假的模型：按预设的文字分几段「流」出来
private final class FakeAI: NotesCompleting {
    var chunks: [String] = []
    var failure: Error?
    private(set) var requests: [(system: String, user: String, maxTokens: Int, member: String?)] = []

    func complete(system: String, user: String, maxTokens: Int, member: AskMember?,
                  onPartial: ((String) -> Void)?, completion: @escaping (Result<String, Error>) -> Void) -> AskRequestHandle {
        requests.append((system, user, maxTokens, member?.useId))
        var text = ""
        for chunk in chunks {
            text += chunk
            onPartial?(text)
        }
        if let failure { completion(.failure(failure)) } else { completion(.success(text)) }
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
}
