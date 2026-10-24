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

    func testKeepsHowItWasAskedAndOldLinesStillLoad() throws {
        try store.append(AskHistoryTurn(thread: "a", question: "打字问的", answer: "答", via: "type", searched: true))
        // 加「问法」之前写下的一行：没有 via、searched
        let old = #"{"id":"x","thread":"b","at":"2026-10-20T08:00:00Z","question":"旧的","answer":"答","hasScreenshot":true,"images":[]}"#
        let handle = try FileHandle(forWritingTo: store.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((old + "\n").utf8))
        try handle.close()
        let turns = store.threads().flatMap(\.turns)
        XCTAssertEqual(turns.first { $0.question == "打字问的" }?.via, "type")
        XCTAssertEqual(turns.first { $0.question == "打字问的" }?.searched, true)
        let oldTurn = try XCTUnwrap(turns.first { $0.question == "旧的" })
        XCTAssertNil(oldTurn.via)
        XCTAssertTrue(oldTurn.hasScreenshot)
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

    func testScreenshotFilesSavedPrivatelyAndDeletedWithThread() throws {
        let kept = turn("b", 1, "留着")
        try store.append(turn("a", 0, "看屏幕"), screenshot: (Data("overview".utf8), Data("closeup".utf8)))
        try store.append(kept, screenshot: (Data("o".utf8), Data("c".utf8)))
        let saved = store.threads().first { $0.id == "a" }!.turns[0]
        XCTAssertTrue(saved.hasScreenshot)
        let urls = store.screenshotURLs(turnID: saved.id)
        XCTAssertEqual(try Data(contentsOf: urls.closeUp), Data("closeup".utf8))
        XCTAssertEqual(try Data(contentsOf: urls.overview), Data("overview".utf8))
        let perms = try FileManager.default.attributesOfItem(atPath: urls.closeUp.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)

        try store.deleteThread("a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.closeUp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls.overview.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.screenshotURLs(turnID: kept.id).closeUp.path))

        try store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imagesDirectory.path))
    }

    func testImagesArrivingAfterAnswerAreAttachedToThatTurn() throws {
        let first = turn("a", 0, "找个照片")
        try store.append(first)
        try store.append(turn("a", 1, "再来一张"))
        let image = AskImage(thumb: "https://t.example/1.jpg", full: "https://f.example/1.jpg",
                             pageURL: "https://p.example", title: "猫", width: 400, height: 600)
        try store.setImages([image], turnID: first.id)
        let turns = store.threads()[0].turns
        XCTAssertEqual(turns[0].images, [image])
        XCTAssertEqual(turns[1].images, [])
    }

    func testImageThumbsDownloadedSkippingFailures() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubThumbProtocol.self]
        let session = URLSession(configuration: config)
        let images = ["https://t.example/ok.jpg", "https://t.example/missing.jpg"].map {
            AskImage(thumb: $0, full: $0, pageURL: "", title: "", width: 1, height: 1)
        }
        let done = expectation(description: "thumbs")
        store.saveImageThumbs(images, turnID: "t1", session: session) { done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(try Data(contentsOf: store.imageThumbURL(turnID: "t1", index: 0)), Data("jpeg".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageThumbURL(turnID: "t1", index: 1).path))
    }

    func testSearchMatchesQuestionOrAnswerIgnoringCase() {
        let thread = AskHistoryThread(id: "a", turns: [turn("a", 0, "Swift 是什么", "一门编程语言")])
        XCTAssertTrue(thread.matches("swift"))
        XCTAssertTrue(thread.matches("编程"))
        XCTAssertFalse(thread.matches("Python"))
    }
}

/// 缩略图下载的假网络：ok.jpg 回 200，其他回 404
private final class StubThumbProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let ok = request.url?.lastPathComponent == "ok.jpg"
        let response = HTTPURLResponse(url: request.url!, statusCode: ok ? 200 : 404, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((ok ? "jpeg" : "nope").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
