import XCTest
@testable import AskFreeCore

/// 假的 AnkiConnect：按动作名回话，记下每个请求；挂在 URLProtocol 上，不碰本机的 8765
private final class FakeAnki: URLProtocol {
    static var handler: ((String, [String: Any]) throws -> Any?)?
    static var log: [(action: String, params: [String: Any])] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            return data
        } ?? request.httpBody ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let action = json["action"] as? String ?? ""
        let params = json["params"] as? [String: Any] ?? [:]
        Self.log.append((action, params))
        let ok = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        do {
            let result = try Self.handler?(action, params)
            let reply = try JSONSerialization.data(withJSONObject: ["result": result ?? NSNull(), "error": NSNull()])
            client?.urlProtocol(self, didReceive: ok, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply)
        } catch let e as URLError {
            client?.urlProtocol(self, didFailWithError: e)
            return
        } catch {
            let reply = try! JSONSerialization.data(withJSONObject: ["result": NSNull(), "error": "\(error)"])
            client?.urlProtocol(self, didReceive: ok, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class AnkiConnectTests: XCTestCase {
    private var anki: AnkiConnect!

    override func setUp() {
        super.setUp()
        FakeAnki.log = []
        FakeAnki.handler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeAnki.self]
        anki = AnkiConnect(url: URL(string: "http://127.0.0.1:18765")!, session: URLSession(configuration: config))
    }

    private func card(_ id: String, screenshot: Bool = true) -> AnkiCard {
        AnkiCardBuilder.card(item: DayNoteItem(id: id, turnID: "turn-\(id)", title: "题", points: "- 要点 $x^2$\n- 第二条 `code`"),
                             question: "问题 \(id) <b>", day: "2026-10-29", time: "14:05", screenshot: screenshot ? Data([1, 2, 3]) : nil)
    }

    // MARK: 卡片

    func testCardFrontIsQuestionWithScreenshotAndBackIsPointsWithAnkiMath() {
        let c = card("a")
        XCTAssertTrue(c.front.contains("问题 a &lt;b&gt;"), "问题里的 < 要转义")
        XCTAssertTrue(c.front.contains("<img src=\"askfree-turn-a.jpg\">"))
        XCTAssertEqual(c.mediaName, "askfree-turn-a.jpg")
        XCTAssertEqual(c.mediaData, Data([1, 2, 3]))
        XCTAssertTrue(c.back.contains("\\(x^2\\)"), "公式用 Anki 自带的 MathJax 写法")
        XCTAssertTrue(c.back.contains("<code>code</code>"))
        XCTAssertEqual(c.source, "Ask Free · 2026-10-29 14:05")
        XCTAssertEqual(c.tags, ["askfree", "askfree-2026-10-29"])
    }

    func testCardWithoutScreenshotHasNoImage() {
        let c = card("b", screenshot: false)
        XCTAssertFalse(c.front.contains("<img"))
        XCTAssertNil(c.mediaName)
    }

    func testDevOverrideOnlyAppliesToDevBuilds() {
        let env = ["ASKFREE_ANKI_URL": "http://127.0.0.1:18765"]
        XCTAssertEqual(AnkiConnect.configuredURL(environment: env, isDevBuild: true).port, 18765)
        XCTAssertEqual(AnkiConnect.configuredURL(environment: env, isDevBuild: false), AnkiConnect.defaultURL, "正式版不认这个变量")
        XCTAssertEqual(AnkiConnect.configuredURL(environment: ["ASKFREE_ANKI_URL": "https://evil.example"], isDevBuild: true), AnkiConnect.defaultURL)
    }

    // MARK: 导入

    func testImportAddsNewCardsAndSkipsExistingOnes() async throws {
        FakeAnki.handler = { action, params in
            switch action {
            case "version": return 6
            case "createDeck": return 1
            case "modelNames": return [String]()
            case "createModel": return [String: Any]()
            case "canAddNotes": return [true, false, true]
            case "storeMediaFile": return "x.jpg"
            case "addNotes": return [101, 102]
            default: XCTFail("没想到的动作 \(action)"); return nil
            }
        }
        let result = try await anki.add([card("a"), card("b"), card("c")])
        XCTAssertEqual(result.added, ["a", "c"])
        XCTAssertEqual(result.skipped, ["b"])
        let actions = FakeAnki.log.map(\.action)
        XCTAssertEqual(actions.filter { $0 == "storeMediaFile" }.count, 2, "只给要加的卡传截图")
        XCTAssertEqual(actions.last, "addNotes")
        let added = (FakeAnki.log.last!.params["notes"] as! [[String: Any]])
        XCTAssertEqual(added.count, 2)
        XCTAssertEqual(added[0]["deckName"] as? String, "Ask Free")
        XCTAssertEqual(added[0]["modelName"] as? String, "Ask Free 笔记")
        XCTAssertEqual((added[0]["options"] as? [String: Any])?["allowDuplicate"] as? Bool, false)
    }

    func testImportWhenEverythingAlreadyThereAddsNothing() async throws {
        FakeAnki.handler = { action, _ in
            switch action {
            case "version": return 6
            case "modelNames": return ["Ask Free 笔记"]
            case "canAddNotes": return [false, false]
            default: return 1
            }
        }
        let result = try await anki.add([card("a"), card("b")])
        XCTAssertEqual(result.added, [])
        XCTAssertEqual(result.skipped, ["a", "b"])
        XCTAssertFalse(FakeAnki.log.map(\.action).contains("addNotes"))
        XCTAssertFalse(FakeAnki.log.map(\.action).contains("createModel"), "笔记类型已经有了就不再建")
    }

    func testRaceWhereAnkiRefusesALateDuplicateCountsAsSkipped() async throws {
        FakeAnki.handler = { action, _ in
            switch action {
            case "version": return 6
            case "modelNames": return ["Ask Free 笔记"]
            case "canAddNotes": return [true, true]
            case "addNotes": return [7, NSNull()]
            default: return 1
            }
        }
        let result = try await anki.add([card("a"), card("b")])
        XCTAssertEqual(result.added, ["a"])
        XCTAssertEqual(result.skipped, ["b"])
    }

    func testAnkiNotRunningIsReportedAndNothingIsSent() async {
        FakeAnki.handler = { _, _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await anki.add([card("a")])
            XCTFail("应当抛错")
        } catch {
            XCTAssertEqual(error as? AnkiConnectError, .notRunning)
        }
        XCTAssertEqual(FakeAnki.log.map(\.action), ["version"])
    }

    func testApiErrorIsSurfaced() async {
        FakeAnki.handler = { action, _ in
            struct E: Error, CustomStringConvertible { var description: String { "collection is not available" } }
            if action == "version" { return 6 }
            throw E()
        }
        do {
            _ = try await anki.add([card("a")])
            XCTFail("应当抛错")
        } catch {
            XCTAssertEqual(error as? AnkiConnectError, .api("collection is not available"))
        }
    }
}
