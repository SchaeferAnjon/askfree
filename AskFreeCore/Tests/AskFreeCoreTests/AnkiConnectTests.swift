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

    private func card(_ id: String, screenshot: Bool = true, points: String = "- 要点 $x^2$\n- 第二条 `code`\n- 第三条") -> AnkiCard {
        AnkiCardBuilder.card(item: DayNoteItem(id: id, turnID: "turn-\(id)", title: "题", points: points),
                             question: "问题 \(id) <b>", kind: "看屏幕问", day: "2026-10-29", time: "14:05", screenshot: screenshot ? Data([1, 2, 3]) : nil)
    }

    /// 假 Anki 的笔记类型：名字 → (字段, 样式)
    private func fake(models: [String: (fields: [String], css: String)], found: Set<String> = [], decks: [String: Int] = [:],
                      added: (([[String: Any]]) -> [Any])? = nil) {
        FakeAnki.handler = { action, params in
            switch action {
            case "version": return 6
            case "modelNames": return Array(models.keys)
            case "modelFieldNames": return models[params["modelName"] as? String ?? ""]?.fields ?? []
            case "modelStyling": return ["css": models[params["modelName"] as? String ?? ""]?.css ?? ""]
            case "createModel", "updateModelStyling", "updateModelTemplates": return NSNull()
            case "findNotes":
                let q = params["query"] as? String ?? ""
                return found.contains(where: { q.contains($0) }) ? [55] : [Int]()
            case "storeMediaFile": return "x.jpg"
            case "addNotes":
                let notes = params["notes"] as? [[String: Any]] ?? []
                return added?(notes) ?? notes.indices.map { 100 + $0 }
            case "deckNamesAndIds": return decks
            case "createDeck": return 99
            default: XCTFail("没想到的动作 \(action)"); return nil
            }
        }
    }

    private var actions: [String] { FakeAnki.log.map(\.action) }

    // MARK: 卡片

    func testCardFieldsFollowTheSharedStudyCard() {
        let c = card("a")
        XCTAssertEqual(Set(c.fields.keys), Set(StudyCard.fields))
        XCTAssertEqual(c.fields["Question"], "问题 a &lt;b&gt;", "问题里的 < 要转义")
        XCTAssertEqual(c.fields["Answer"], "要点 \\(x^2\\)", "第一条是答案；公式用 Anki 自带的 MathJax 写法")
        XCTAssertTrue(c.fields["More"]!.hasPrefix("<ul"), "其余两条是补充，写成圆点")
        XCTAssertTrue(c.fields["More"]!.contains("<code>code</code>"))
        XCTAssertEqual(c.fields["Image"], "<img class=\"lead\" src=\"askfree-turn-a.jpg\">", "看屏幕问的截图放在问题下面")
        XCTAssertEqual(c.fields["Label"], "Ask Free · 看屏幕问")
        XCTAssertEqual(c.fields["Source"], "题 · 2026-10-29 14:05")
        XCTAssertEqual(c.fields["ID"], "askfree-turn-a")
        XCTAssertEqual(c.mediaName, "askfree-turn-a.jpg")
        XCTAssertEqual(c.mediaData, Data([1, 2, 3]))
        XCTAssertEqual(c.tags, ["来自::Ask_Free", "askfree-2026-10-29"])
    }

    func testOnlyOneExtraPointIsAParagraphNotABullet() {
        let c = card("b", screenshot: false, points: "- 答案\n- 补充一条")
        XCTAssertEqual(c.fields["Answer"], "答案")
        XCTAssertEqual(c.fields["More"], "补充一条")
        XCTAssertEqual(c.fields["Image"], "")
        XCTAssertNil(c.mediaName)
        XCTAssertEqual(card("c", screenshot: false, points: "- 只有一条").fields["More"], "")
    }

    func testKindLabel() {
        XCTAssertEqual(AnkiCardBuilder.kind(via: "type", hasScreenshot: false), "打字问")
        XCTAssertEqual(AnkiCardBuilder.kind(via: nil, hasScreenshot: true), "看屏幕问")
        XCTAssertEqual(AnkiCardBuilder.kind(via: nil, hasScreenshot: false), "只提问")
    }

    /// 三个软件的「学习卡 · 问答」要一字不差：这里钉住版本行和九个字段
    func testSharedNoteTypeIsVersioned() {
        XCTAssertEqual(StudyCard.version(ofCSS: StudyCard.css), StudyCard.version)
        XCTAssertNil(StudyCard.version(ofCSS: LegacyNote.originalCSS))
        XCTAssertEqual(StudyCard.fields, ["Question", "Answer", "More", "Quote", "Image", "Label", "Source", "Link", "ID"])
        XCTAssertFalse(StudyCard.back.contains("id=\"answer\""))
    }

    func testDevOverrideOnlyAppliesToDevBuilds() {
        let env = ["ASKFREE_ANKI_URL": "http://127.0.0.1:18765"]
        XCTAssertEqual(AnkiConnect.configuredURL(environment: env, isDevBuild: true).port, 18765)
        XCTAssertEqual(AnkiConnect.configuredURL(environment: env, isDevBuild: false), AnkiConnect.defaultURL, "正式版不认这个变量")
        XCTAssertEqual(AnkiConnect.configuredURL(environment: ["ASKFREE_ANKI_URL": "https://evil.example"], isDevBuild: true), AnkiConnect.defaultURL)
    }

    // MARK: 送进 Anki

    func testSendAddsNewCardsAndSkipsOnesAlreadyThereById() async throws {
        fake(models: ["Basic": (["Front", "Back"], "")], found: ["askfree-turn-b"])
        let result = try await anki.add([card("a"), card("b"), card("c")], deck: "知识")
        XCTAssertEqual(result.added, ["a", "c"])
        XCTAssertEqual(result.skipped, ["b"])
        XCTAssertEqual(result.failed, [])
        let model = FakeAnki.log.first { $0.action == "createModel" }!.params
        XCTAssertEqual(model["modelName"] as? String, "学习卡 · 问答")
        XCTAssertEqual(model["inOrderFields"] as? [String], StudyCard.fields)
        let queries = FakeAnki.log.filter { $0.action == "findNotes" }.compactMap { $0.params["query"] as? String }
        XCTAssertEqual(queries[1], "\"ID:askfree-turn-b\" OR \"Front:*askfree-turn-b*\"", "按编号找，也认老版本放在正面的编号")
        XCTAssertEqual(actions.filter { $0 == "storeMediaFile" }.count, 2, "只给要加的卡传截图")
        let notes = FakeAnki.log.last { $0.action == "addNotes" }!.params["notes"] as! [[String: Any]]
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0]["deckName"] as? String, "知识")
        XCTAssertEqual(notes[0]["modelName"] as? String, "学习卡 · 问答")
        XCTAssertEqual((notes[0]["options"] as? [String: Any])?["allowDuplicate"] as? Bool, true, "问法一样的两个问题是两张卡，判重靠编号")
    }

    /// Anki 存截图时可能换个名字（重名、大小写）：卡片里引用 Anki 回的那个
    func testImageUsesTheFileNameAnkiStored() async throws {
        fake(models: [StudyCard.name: (StudyCard.fields, StudyCard.css)])
        let base = FakeAnki.handler!
        FakeAnki.handler = { action, params in action == "storeMediaFile" ? "askfree-turn-a-1.jpg" : try base(action, params) }
        _ = try await anki.add([card("a")], deck: "知识")
        let notes = FakeAnki.log.last { $0.action == "addNotes" }!.params["notes"] as! [[String: Any]]
        XCTAssertEqual((notes[0]["fields"] as? [String: String])?["Image"], "<img class=\"lead\" src=\"askfree-turn-a-1.jpg\">")
    }

    func testSameQuestionTwiceIsTwoCards() async throws {
        fake(models: [StudyCard.name: (StudyCard.fields, StudyCard.css)])
        let a = AnkiCardBuilder.card(item: DayNoteItem(id: "A", turnID: "turn-A", title: "题", points: "- x"), question: "这是什么意思？", kind: "看屏幕问", day: "2026-10-29", time: "10:00", screenshot: nil)
        let b = AnkiCardBuilder.card(item: DayNoteItem(id: "B", turnID: "turn-B", title: "题", points: "- y"), question: "这是什么意思？", kind: "看屏幕问", day: "2026-10-29", time: "10:00", screenshot: nil)
        let result = try await anki.add([a, b], deck: "知识")
        XCTAssertEqual(result.added, ["A", "B"])
        XCTAssertFalse(actions.contains("createModel"), "笔记类型已经有了就不再建")
        XCTAssertFalse(actions.contains("updateModelStyling"), "同一版本不重换")
    }

    func testAnkiReturningNullIsFailedNotSkipped() async throws {
        fake(models: [StudyCard.name: (StudyCard.fields, StudyCard.css)], added: { _ in [7, NSNull()] })
        let result = try await anki.add([card("a"), card("b")], deck: "知识")
        XCTAssertEqual(result.added, ["a"])
        XCTAssertEqual(result.skipped, [])
        XCTAssertEqual(result.failed, ["b"])
    }

    /// 只往新的换：旧版本换；比我们新的不动；第一行不是版本号说明你改过，先问
    func testRestyleOnlyOlderVersionsAndAskWhenCustomized() async throws {
        let cases: [(css: String, choice: CustomizedStyle, restyle: Bool, asks: Bool)] = [
            ("/* 卡片家族 v2 */\n.card {}", .ask, true, false),
            (StudyCard.css, .ask, false, false),
            ("/* 卡片家族 v9 */\n.card {}", .ask, false, false),
            (".card { color: hotpink }", .ask, false, true),
            (".card { color: hotpink }", .keep, false, false),
            (".card { color: hotpink }", .replace, true, false),
        ]
        for c in cases {
            FakeAnki.log = []
            fake(models: [StudyCard.name: (StudyCard.fields, c.css)])
            do {
                _ = try await anki.add([card("a", screenshot: false)], deck: "知识", customized: c.choice)
                XCTAssertFalse(c.asks, "应当先问")
            } catch {
                XCTAssertTrue(c.asks)
                XCTAssertEqual(error as? AnkiConnectError, .customizedStyle(model: StudyCard.name))
                XCTAssertFalse(actions.contains("addNotes"))
            }
            XCTAssertEqual(actions.contains("updateModelStyling"), c.restyle, "\(c.css.prefix(16)) \(c.choice)")
        }
    }

    func testSomeoneElsesNoteTypeWithTheSameNameIsLeftAlone() async throws {
        fake(models: [StudyCard.name: (["正面", "背面"], ".card {}")])
        _ = try await anki.add([card("a", screenshot: false)], deck: "知识")
        XCTAssertEqual(FakeAnki.log.first { $0.action == "createModel" }?.params["modelName"] as? String, "学习卡 · 问答 2")
        XCTAssertFalse(actions.contains("updateModelStyling"))
    }

    /// 老的「Ask Free 笔记」：当初建的样子换成纸；你改过的不动
    func testLegacyNoteTypeGetsThePaperOnlyIfUntouched() async throws {
        fake(models: [AnkiCardBuilder.legacyModel: (["Front", "Back", "Source"], LegacyNote.originalCSS), StudyCard.name: (StudyCard.fields, StudyCard.css)])
        _ = try await anki.add([card("a", screenshot: false)], deck: "知识")
        let styled = FakeAnki.log.filter { $0.action == "updateModelStyling" }.compactMap { ($0.params["model"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(styled, [AnkiCardBuilder.legacyModel])
        let css = (FakeAnki.log.first { $0.action == "updateModelStyling" }!.params["model"] as! [String: Any])["css"] as! String
        XCTAssertEqual(StudyCard.version(ofCSS: css), StudyCard.version)

        FakeAnki.log = []
        fake(models: [AnkiCardBuilder.legacyModel: (["Front", "Back", "Source"], ".card { font-size: 30px }"), StudyCard.name: (StudyCard.fields, StudyCard.css)])
        _ = try await anki.add([card("a", screenshot: false)], deck: "知识")
        XCTAssertFalse(actions.contains("updateModelStyling"), "你改过的老模板不动")
    }

    func testDeckFollowsRenameById() async throws {
        fake(models: [:], decks: ["Default": 1, "我的知识": 42])
        var deck = try await anki.deck(id: 42, orCreate: "知识")
        XCTAssertEqual(deck.name, "我的知识")
        fake(models: [:], decks: ["Default": 1])
        deck = try await anki.deck(id: 42, orCreate: "知识")
        XCTAssertEqual(deck.id, 99)
        XCTAssertEqual(FakeAnki.log.last { $0.action == "createDeck" }?.params["deck"] as? String, "知识")
    }

    func testMovingTheLegacyDeckOnlyDeletesItWhenEmpty() async throws {
        var left = [1, 2]
        FakeAnki.handler = { action, params in
            switch action {
            case "findCards": return left
            case "changeDeck": left = []; return NSNull()
            case "deleteDecks": return NSNull()
            default: return NSNull()
            }
        }
        try await anki.moveLegacyCards(to: "知识")
        XCTAssertEqual(FakeAnki.log.map(\.action), ["findCards", "changeDeck", "findCards", "deleteDecks"])
        XCTAssertEqual(FakeAnki.log[1].params["deck"] as? String, "知识")

        FakeAnki.log = []
        FakeAnki.handler = { action, _ in action == "findCards" ? [1] : NSNull() }
        do {
            try await anki.moveLegacyCards(to: "知识")
            XCTFail("没搬空不该删")
        } catch {}
        XCTAssertFalse(FakeAnki.log.map(\.action).contains("deleteDecks"))
    }

    func testEditorOpenErrorIsReadable() async {
        FakeAnki.handler = { action, _ in
            struct E: Error, CustomStringConvertible { var description: String { "Close the affected editor before this API write, even if its content is saved." } }
            throw E()
        }
        do {
            _ = try await anki.version()
            XCTFail("应当抛错")
        } catch {
            XCTAssertEqual(error as? AnkiConnectError, .api("Anki 里开着卡片浏览器或「添加」窗口，Anki 不让这时改笔记类型；关掉它再送"))
        }
    }

    func testAnkiNotRunningIsReportedAndNothingIsSent() async {
        FakeAnki.handler = { _, _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await anki.add([card("a")], deck: "知识")
            XCTFail("应当抛错")
        } catch {
            XCTAssertEqual(error as? AnkiConnectError, .notRunning)
        }
        XCTAssertEqual(FakeAnki.log.map(\.action), ["version"])
    }
}
