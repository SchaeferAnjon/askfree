import XCTest
@testable import AskFreeCore

final class DayNotesTests: XCTestCase {
    private var dir: URL!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vpdn-\(UUID().uuidString)")
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar = c
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// 2026-10-29 08:00（上海）加几个小时
    private func at(_ day: Int, _ hour: Double) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!.addingTimeInterval(hour * 3600)
    }

    private func thread(_ id: String, day: Int, hour: Double, q: String = "问题", a: String = "回答", turns: Int = 1) -> AskHistoryThread {
        AskHistoryThread(id: id, turns: (0..<turns).map { i in
            AskHistoryTurn(id: "\(id)-t\(i)", thread: id, at: at(day, hour + Double(i) * 0.1), question: i == 0 ? q : "追问\(i)", answer: a, hasScreenshot: i == 0)
        })
    }

    // MARK: 分天

    func testGroupsByDayNewestFirstAndEarliestQuestionFirstWithinADay() {
        let days = HistoryDay.group([thread("c", day: 29, hour: 22), thread("a", day: 28, hour: 9),
                                     thread("b", day: 29, hour: 10)], calendar: calendar)
        XCTAssertEqual(days.map(\.key), ["2026-10-29", "2026-10-28"])
        XCTAssertEqual(days[0].threads.map(\.id), ["b", "c"])
    }

    func testThreadStartedYesterdayFollowedUpTodayBelongsToTodayWithTodaysTime() {
        let t = AskHistoryThread(id: "x", turns: [
            AskHistoryTurn(id: "x0", thread: "x", at: at(28, 23.5), question: "昨天的", answer: "答"),
            AskHistoryTurn(id: "x1", thread: "x", at: at(29, 9.25), question: "今天追问", answer: "答"),
        ])
        let days = HistoryDay.group([t], calendar: calendar)
        XCTAssertEqual(days.map(\.key), ["2026-10-29"])
        XCTAssertEqual(HistoryDay.moment(of: t, on: days[0].date, calendar: calendar), at(29, 9.25))
    }

    func testDayKeyRoundTrip() {
        let date = HistoryDay.date(forKey: "2026-10-29", calendar: calendar)!
        XCTAssertEqual(HistoryDay.key(for: date, calendar: calendar), "2026-10-29")
        XCTAssertNil(HistoryDay.date(forKey: "2026-10", calendar: calendar))
        XCTAssertNil(HistoryDay.date(forKey: "bad", calendar: calendar))
    }

    // MARK: 状态

    func testStatusCountsDoneNewAndFollowedUp() {
        let day = HistoryDay.group([thread("a", day: 29, hour: 9), thread("b", day: 29, hour: 10, turns: 2)], calendar: calendar)[0]
        var notes = DayNotes.begin(day)
        XCTAssertEqual(notes.status(against: day), DayNotesStatus(done: 0, total: 2, hasSummary: false, newQuestions: 0, followedUp: 0))
        notes.put(DayNoteItem(id: "a", turnID: "a-t0", title: "A", points: "- 一"))
        notes.put(DayNoteItem(id: "b", turnID: "b-t0", title: "B", points: "- 二"))
        notes.summary = "小结"
        XCTAssertTrue(notes.status(against: day).isComplete)
        XCTAssertFalse(notes.status(against: day).isOutdated)

        // 之后又问了一个新的，b 又追问了一轮
        let later = HistoryDay.group([thread("a", day: 29, hour: 9), thread("b", day: 29, hour: 10, turns: 3),
                                      thread("c", day: 29, hour: 12)], calendar: calendar)[0]
        let status = notes.status(against: later)
        XCTAssertEqual(status.newQuestions, 1)
        XCTAssertEqual(status.followedUp, 1)
        XCTAssertTrue(status.isOutdated)
    }

    func testQuestionDeletedFromHistoryNoLongerCounts() {
        let day = HistoryDay.group([thread("a", day: 29, hour: 9), thread("b", day: 29, hour: 10)], calendar: calendar)[0]
        var notes = DayNotes.begin(day)
        notes.put(DayNoteItem(id: "a", turnID: "a-t0", title: "A", points: "- 一"))
        notes.put(DayNoteItem(id: "b", turnID: "b-t0", title: "B", points: "- 二"))
        notes.summary = "小结"
        let after = HistoryDay.group([thread("a", day: 29, hour: 9)], calendar: calendar)[0]
        let status = notes.status(against: after)
        XCTAssertEqual(status.done, 1)
        XCTAssertEqual(status.total, 1)
        XCTAssertTrue(status.isComplete)
    }

    func testPutReplacesTheSameThread() {
        var notes = DayNotes(day: "2026-10-29", covered: [DayNoteCoverage(thread: "a", turns: 1)])
        notes.put(DayNoteItem(id: "a", turnID: "t", title: "旧", points: "- 旧"))
        notes.put(DayNoteItem(id: "a", turnID: "t", title: "新", points: "- 新"))
        XCTAssertEqual(notes.items.map(\.title), ["新"])
    }

    // MARK: 存取

    func testStoreRoundTripPermissionsAndUnreadableFile() throws {
        let store = DayNotesStore(directory: dir.appendingPathComponent("day-notes"))
        XCTAssertNil(store.load(day: "2026-10-29"))
        var notes = DayNotes(day: "2026-10-29", summary: "今天", keep: ["一", "二"],
                             items: [DayNoteItem(id: "a", turnID: "t", title: "题", points: "- 要点 $x^2$")],
                             covered: [DayNoteCoverage(thread: "a", turns: 2)], generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(notes)
        XCTAssertEqual(store.load(day: "2026-10-29"), notes)
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("day-notes/2026-10-29.json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(store.days(), ["2026-10-29"])

        try "not json".write(to: dir.appendingPathComponent("day-notes/2026-10-30.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(store.load(day: "2026-10-30"))

        notes.version = 99
        try store.save(notes)
        XCTAssertNil(store.load(day: "2026-10-29"), "比这个 App 新的版本当没有，不乱读")
    }

    func testLedgerAndForget() throws {
        let store = DayNotesStore(directory: dir.appendingPathComponent("day-notes"))
        try store.save(DayNotes(day: "2026-10-29", summary: "s",
                                items: [DayNoteItem(id: "a", turnID: "t", title: "A", points: "- x"), DayNoteItem(id: "b", turnID: "u", title: "B", points: "- y")],
                                covered: [DayNoteCoverage(thread: "a", turns: 1), DayNoteCoverage(thread: "b", turns: 1)]))
        try store.markInAnki(["a", "b"], at: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(Set(store.ankiLedger().keys), ["a", "b"])
        store.forget(thread: "a")
        XCTAssertEqual(store.load(day: "2026-10-29")?.items.map(\.id), ["b"])
        XCTAssertEqual(store.load(day: "2026-10-29")?.covered.map(\.thread), ["b"])
        XCTAssertEqual(Set(store.ankiLedger().keys), ["b"])
        store.forget(thread: "b")
        XCTAssertNil(store.load(day: "2026-10-29"), "一天的问题都删光，这天的笔记文件也删掉")
    }

    func testDeletingHistoryDeletesNotesAndExports() throws {
        let history = AskHistoryStore(fileURL: dir.appendingPathComponent("history.jsonl"))
        try history.append(AskHistoryTurn(id: "t1", thread: "a", question: "问", answer: "答"))
        try history.append(AskHistoryTurn(id: "t2", thread: "b", question: "问2", answer: "答2"))
        let notes = DayNotesStore(directory: history.notesDirectory)
        try notes.save(DayNotes(day: "2026-10-29", summary: "s",
                                items: [DayNoteItem(id: "a", turnID: "t1", title: "A", points: "- x")], covered: [DayNoteCoverage(thread: "a", turns: 1), DayNoteCoverage(thread: "b", turns: 1)]))
        try FileManager.default.createDirectory(at: history.exportedNotesDirectory, withIntermediateDirectories: true)
        try "<html>".write(to: history.exportedNotesDirectory.appendingPathComponent("x.html"), atomically: true, encoding: .utf8)

        try history.deleteThread("a")
        XCTAssertEqual(notes.load(day: "2026-10-29")?.items, [])
        try history.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.notesDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.exportedNotesDirectory.path))
    }

    // MARK: 删历史（代码审查 1、2）

    private func historyWithTwoThreads() throws -> (history: AskHistoryStore, store: DayNotesStore, day: HistoryDay) {
        let history = AskHistoryStore(fileURL: dir.appendingPathComponent("history.jsonl"))
        let base = Date().addingTimeInterval(-3600)
        try history.append(AskHistoryTurn(id: "tuA", thread: "thA", at: base, question: "我的银行卡 6222 0000 怎么绑", answer: "答 A"))
        try history.append(AskHistoryTurn(id: "tuB", thread: "thB", at: base.addingTimeInterval(60), question: "B", answer: "答 B"))
        return (history, DayNotesStore(directory: history.notesDirectory), HistoryDay.group(history.threads())[0])
    }

    func testDeletingAThreadClearsSummaryAndKeepThatMayQuoteIt() throws {
        let (history, store, day) = try historyWithTwoThreads()
        var notes = DayNotes.begin(day)
        notes.put(DayNoteItem(id: "thA", turnID: "tuA", title: "绑卡", points: "- 卡号 6222 0000"))
        notes.put(DayNoteItem(id: "thB", turnID: "tuB", title: "B", points: "- b"))
        notes.summary = "今天弄清了银行卡 6222 0000 怎么绑。"
        notes.keep = ["卡号 6222 0000 绑在设置里"]
        try store.save(notes)
        try history.deleteThread("thA")
        let after = try XCTUnwrap(store.load(day: day.key))
        XCTAssertEqual(after.items.map(\.id), ["thB"])
        XCTAssertEqual(after.summary, "")
        XCTAssertEqual(after.keep, [])
        let afterDay = HistoryDay.group(history.threads())[0]
        XCTAssertFalse(after.status(against: afterDay).isComplete, "小结没了：页面显示「接着整理」，只补小结")
        XCTAssertEqual(after.status(against: afterDay).done, 1)
    }

    func testDeletingAThreadWithoutAnItemKeepsTheSummary() throws {
        let (history, store, day) = try historyWithTwoThreads()
        var notes = DayNotes.begin(day)
        notes.put(DayNoteItem(id: "thB", turnID: "tuB", title: "B", points: "- b"))
        notes.summary = "小结"
        try store.save(notes)
        try history.deleteThread("thA")
        XCTAssertEqual(store.load(day: day.key)?.summary, "小结")
    }

    func testKeepingDropsThreadsThatAreNoLongerInHistory() {
        var notes = DayNotes(day: "2026-10-29", covered: [DayNoteCoverage(thread: "a", turns: 1), DayNoteCoverage(thread: "b", turns: 1)])
        notes.put(DayNoteItem(id: "a", turnID: "ta", title: "A", points: "- 机密要点 A"))
        notes.put(DayNoteItem(id: "b", turnID: "tb", title: "B", points: "- b"))
        notes.summary = "s"
        let kept = notes.keeping(existing: ["b"])
        XCTAssertEqual(kept.items.map(\.id), ["b"])
        XCTAssertEqual(kept.covered.map(\.thread), ["b"])
        XCTAssertEqual(kept.summary, "")
        XCTAssertEqual(notes.keeping(existing: ["a", "b"]), notes, "都还在就原样")
        XCTAssertTrue(notes.keeping(existing: []).items.isEmpty)
    }

    /// 整理途中用户清空历史 / 删一条：存盘前按现在的历史过一遍，已删的不写回
    func testSavingAfterDeletionDuringGenerationDoesNotWriteItBack() throws {
        let (history, store, day) = try historyWithTwoThreads()
        var working = DayNotes.begin(day)
        working.put(DayNoteItem(id: "thA", turnID: "tuA", title: "甲", points: "- 机密要点 A"))
        func persist(_ notes: DayNotes) {
            let kept = notes.keeping(existing: Set(history.threads().map(\.id)))
            if !kept.items.isEmpty { try? store.save(kept) }
        }
        persist(working)
        XCTAssertNotNil(store.load(day: day.key))
        try history.deleteThread("thA")
        persist(working)   // 整理还在写：下一次存盘
        XCTAssertNil(store.load(day: day.key)?.item(for: "thA"))
        try history.deleteAll()
        persist(working)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: history.notesDirectory.path)) ?? [], [], "清空历史后 day-notes/ 里不再出现文件")
    }
}
