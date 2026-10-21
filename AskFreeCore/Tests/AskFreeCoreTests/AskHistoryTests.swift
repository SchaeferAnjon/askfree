import XCTest
@testable import AskFreeCore

final class AskHistoryTests: XCTestCase {
    private var dir: URL!
    private var store: AskHistoryStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vpah-\(UUID().uuidString)")
        store = AskHistoryStore(fileURL: dir.appendingPathComponent("history.jsonl"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func turn(_ thread: String, _ seconds: TimeInterval, _ q: String, _ a: String = "答") -> AskHistoryTurn {
        AskHistoryTurn(thread: thread, at: Date(timeIntervalSince1970: 1_800_000_000 + seconds), question: q, answer: a)
    }

    func testEmptyWhenNoFile() {
        XCTAssertEqual(store.threads(), [])
    }

    func testFollowUpsGroupUnderOneThreadNewestThreadFirst() throws {
        try store.append(turn("a", 0, "这是什么"))
        try store.append(turn("b", 10, "另一个话题"))
        try store.append(turn("a", 20, "再说细一点"))
        let threads = store.threads()
        XCTAssertEqual(threads.map(\.id), ["a", "b"])
        XCTAssertEqual(threads[0].turns.map(\.question), ["这是什么", "再说细一点"])
        XCTAssertEqual(threads[0].startedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testRoundTripKeepsTextWithNewlinesAndQuotes() throws {
        let answer = "### 标题\n\n- 第一条 \"引号\"\n- https://example.com/a/b"
        try store.append(turn("a", 0, "问", answer))
        XCTAssertEqual(store.threads()[0].turns[0].answer, answer)
    }

    func testFileIsPrivate() throws {
        try store.append(turn("a", 0, "问"))
        try store.append(turn("a", 1, "再问"))
        let perms = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func testDeleteThreadKeepsOthers() throws {
        try store.append(turn("a", 0, "一"))
        try store.append(turn("b", 1, "二"))
        try store.append(turn("a", 2, "三"))
        try store.deleteThread("a")
        XCTAssertEqual(store.threads().map(\.id), ["b"])
        try store.append(turn("c", 3, "四"))
        XCTAssertEqual(store.threads().map(\.id), ["c", "b"])
    }

    func testDeleteAll() throws {
        try store.append(turn("a", 0, "一"))
        try store.deleteAll()
        XCTAssertEqual(store.threads(), [])
        try store.deleteAll()
    }

    func testBrokenLineIsSkipped() throws {
        try store.append(turn("a", 0, "一"))
        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"thread\":\"x\",\"que".utf8))
        try handle.close()
        XCTAssertEqual(store.threads().map(\.id), ["a"])
    }

    func testSearchMatchesQuestionOrAnswerIgnoringCase() {
        let thread = AskHistoryThread(id: "a", turns: [turn("a", 0, "Swift 是什么", "一门编程语言")])
        XCTAssertTrue(thread.matches("swift"))
        XCTAssertTrue(thread.matches("编程"))
        XCTAssertFalse(thread.matches("Python"))
    }
}
