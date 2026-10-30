import Foundation

/// 要放进 Anki 的一张卡：正面是问题（带截图），背面是回答要点
public struct AnkiCard: Equatable, Sendable {
    /// 话题 id：导完记「已在 Anki」用
    public let threadID: String
    public let front: String
    public let back: String
    public let source: String
    public let tags: [String]
    /// 截图在 Anki 媒体库里的文件名和内容（没有截图的问题是 nil）
    public let mediaName: String?
    public let mediaData: Data?
}

public enum AnkiCardBuilder {
    public static let deckName = "Ask Free"
    public static let modelName = "Ask Free 笔记"

    /// item：这个问题整理出的笔记；screenshot：它的截图（没有就 nil）。公式在 Anki 里用它自带的 MathJax（\( \)、\[ \]）
    public static func card(item: DayNoteItem, question: String, day: String, time: String, screenshot: Data?) -> AnkiCard {
        let mediaName = screenshot == nil ? nil : "askfree-\(item.turnID).jpg"
        var front = "<div class=\"q\">\(AnswerHTML.escape(question).replacingOccurrences(of: "\n", with: "<br>"))</div>"
        if let mediaName { front += "<div class=\"shot\"><img src=\"\(mediaName)\"></div>" }
        let renderer = AnswerHTML(math: { tex, display in
            let body = AnswerHTML.escape(tex)
            return display ? "\\[\(body)\\]" : "\\(\(body)\\)"
        })
        return AnkiCard(threadID: item.id, front: front, back: renderer.html(item.points),
                        source: "Ask Free · \(day) \(time)", tags: ["askfree", "askfree-\(day)"],
                        mediaName: mediaName, mediaData: screenshot)
    }
}

/// 导进 Anki 的结果
public struct AnkiImportResult: Equatable, Sendable {
    /// 新加的卡片：话题 id
    public let added: [String]
    /// Anki 里已经有的，没有重复加
    public let skipped: [String]
}

public enum AnkiConnectError: LocalizedError, Equatable {
    /// 连不上：Anki 没开，或者没装 AnkiConnect 插件
    case notRunning
    case api(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .notRunning: return "Anki 没开着，或者没装 AnkiConnect 插件"
        case .api(let message): return "Anki 回了一个错误：\(message)"
        case .badResponse: return "Anki 的回答读不懂"
        }
    }
}

/// AnkiConnect（Anki 的插件，只听本机 8765 端口）的客户端。和 GetNewWord 连 Anki 的办法一样：
/// 一个 JSON 请求 {action, version, params}，回 {result, error}
public final class AnkiConnect: @unchecked Sendable {
    public static let defaultURL = URL(string: "http://127.0.0.1:8765")!
    /// 开发版用环境变量 ASKFREE_ANKI_URL 指到本机的假 AnkiConnect（测试用）；正式版不认
    public static let devOverrideKey = "ASKFREE_ANKI_URL"

    public static func configuredURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                     isDevBuild: Bool = AppIdentity.isDevBuild) -> URL {
        guard isDevBuild, let raw = environment[devOverrideKey], let url = URL(string: raw), url.scheme == "http" else { return defaultURL }
        return url
    }

    private let url: URL
    private let session: URLSession

    public init(url: URL = AnkiConnect.configuredURL(), session: URLSession? = nil) {
        self.url = url
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: 底层

    private func call(_ action: String, _ params: [String: Any]? = nil) async throws -> Any? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["action": action, "version": 6]
        if let params { body["params"] = params }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut,
                                             .notConnectedToInternet, .dnsLookupFailed].contains(error.code) {
            throw AnkiConnectError.notRunning
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AnkiConnectError.badResponse }
        if let error = json["error"] as? String, !error.isEmpty { throw AnkiConnectError.api(error) }
        return json["result"]
    }

    // MARK: 动作

    /// Anki 开着、AnkiConnect 在听就返回它的版本
    public func version() async throws -> Int {
        guard let v = try await call("version") as? Int else { throw AnkiConnectError.badResponse }
        return v
    }

    /// 牌组和笔记类型都在才往下走：缺了就建
    public func prepare(deck: String = AnkiCardBuilder.deckName, model: String = AnkiCardBuilder.modelName) async throws {
        _ = try await call("createDeck", ["deck": deck])   // 已经有就原样留着
        let names = (try await call("modelNames") as? [String]) ?? []
        guard !names.contains(model) else { return }
        _ = try await call("createModel", [
            "modelName": model,
            "inOrderFields": ["Front", "Back", "Source"],
            "css": """
            .card { font-family: -apple-system, "PingFang SC", "Helvetica Neue", Arial, sans-serif; font-size: 17px; line-height: 1.5; text-align: left; color: #222; background: #fff; }
            .q { font-size: 20px; font-weight: 600; }
            .shot img { max-width: 100%; border-radius: 8px; margin-top: 12px; }
            .source { margin-top: 16px; font-size: 12px; color: #888; }
            ul.pts { padding-left: 1.2em; } ul.pts li { margin: 6px 0; } li.blk { list-style: none; margin-left: -1.2em; }
            code { font-family: Menlo, monospace; font-size: 0.9em; background: #f1f1f3; padding: 1px 4px; border-radius: 4px; }
            pre { background: #f6f6f8; padding: 10px 12px; border-radius: 8px; overflow-x: auto; white-space: pre-wrap; }
            pre code { background: none; padding: 0; }
            .code-h, .copy { display: none; }
            """,
            "isCloze": false,
            "cardTemplates": [[
                "Name": "问答",
                "Front": "{{Front}}",
                "Back": "{{FrontSide}}<hr id=answer>{{Back}}<div class=\"source\">{{Source}}</div>",
            ]],
        ])
    }

    /// 把这些卡片放进牌组：Anki 里已经有的（同一个问题的同一张截图）不重复加。
    /// 没连上 Anki 抛 notRunning，此时一张都没加
    public func add(_ cards: [AnkiCard], deck: String = AnkiCardBuilder.deckName,
                    model: String = AnkiCardBuilder.modelName) async throws -> AnkiImportResult {
        _ = try await version()
        try await prepare(deck: deck, model: model)
        func note(_ c: AnkiCard) -> [String: Any] {
            ["deckName": deck, "modelName": model,
             "fields": ["Front": c.front, "Back": c.back, "Source": c.source], "tags": c.tags,
             "options": ["allowDuplicate": false, "duplicateScope": "deck", "duplicateScopeOptions": ["deckName": deck, "checkChildren": false]]]
        }
        let can = (try await call("canAddNotes", ["notes": cards.map(note)]) as? [Bool]) ?? Array(repeating: true, count: cards.count)
        guard can.count == cards.count else { throw AnkiConnectError.badResponse }
        let fresh = zip(cards, can).filter(\.1).map(\.0)
        var added: [String] = []
        if !fresh.isEmpty {
            for card in fresh {
                if let name = card.mediaName, let data = card.mediaData {
                    _ = try await call("storeMediaFile", ["filename": name, "data": data.base64EncodedString()])
                }
            }
            let ids = (try await call("addNotes", ["notes": fresh.map(note)]) as? [Any]) ?? []
            guard ids.count == fresh.count else { throw AnkiConnectError.badResponse }
            for (card, id) in zip(fresh, ids) where !(id is NSNull) { added.append(card.threadID) }
        }
        let addedSet = Set(added)
        return AnkiImportResult(added: added, skipped: cards.map(\.threadID).filter { !addedSet.contains($0) })
    }

    /// 在 Anki 的卡片浏览器里打开这个牌组
    public func browse(deck: String = AnkiCardBuilder.deckName) async throws {
        _ = try await call("guiBrowse", ["query": "deck:\"\(deck)\""])
    }
}
