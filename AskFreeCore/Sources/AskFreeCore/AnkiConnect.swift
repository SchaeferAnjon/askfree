import Foundation

/// 写问答卡的软件（ChatCards、Ask Free、GetNewWord 的知识片段）共用的笔记类型「学习卡 · 问答」。
/// 规范在 DESIGN.md「往 Anki 里加卡」：九个英文字段、顺序固定；样式是「卡片家族」，CSS 第一行写版本号，只往新的换。
/// 三个软件里的这份定义要一字不差：改了就三个仓库一起改，版本号加一。
public enum StudyCard {
    public static let name = "学习卡 · 问答"
    /// 同名的笔记类型不是我们的（字段对不上）就改用这个名字，不碰你的
    static let otherName = "学习卡 · 问答 2"
    public static let fields = ["Question", "Answer", "More", "Quote", "Image", "Label", "Source", "Link", "ID"]
    static let templateName = "问答"
    public static let version = 3

    /// CSS 第一行：`/* 卡片家族 v3 */`；不是这个格式就说明你在 Anki 里改过
    public static func version(ofCSS css: String) -> Int? {
        let first = (css.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespaces)
        let head = "/* 卡片家族 v", tail = " */"
        guard first.hasPrefix(head), first.hasSuffix(tail), first.count > head.count + tail.count else { return nil }
        return Int(first.dropFirst(head.count).dropLast(tail.count))
    }

    /// 截图：Ask Free 写成 `<img class="lead">`，放在问题下面；别的软件的截图收进纸底「当时的画面」
    static let top = """
    <div class="top">{{#Label}}<div class="meta">{{Label}}</div>{{/Label}}<div class="q">{{Question}}</div>{{#Image}}<div class="shot">{{Image}}</div>{{/Image}}</div>
    """

    public static let front = """
    <div class="fam">
    \(top)
    </div>
    """

    /// 不用 {{FrontSide}}：纸要把问题和答案包在同一个元素里；也不用 id="answer"，翻面时问题不跳
    public static let back = """
    <div class="fam back">
    \(top)
    <div class="ans"><div class="a">{{Answer}}</div>{{#More}}<div class="more">{{More}}</div>{{/More}}</div>
    <div class="foot"><div class="src">{{#Source}}<span>{{Source}}</span>{{/Source}}{{#Link}}<a class="open" href="{{text:Link}}">打开原文</a>{{/Link}}</div>{{#Quote}}<details><summary>原文</summary><div class="body">{{Quote}}</div></details>{{/Quote}}{{#Image}}<details class="pic"><summary>当时的画面</summary><div class="body">{{Image}}</div></details>{{/Image}}</div>
    </div>
    """

    public static let css = """
    /* 卡片家族 v3 */
    .card {
      --bg: #FFFFFF; --surface: #F4F4F6;
      --text: #18191C; --text2: #5F636C; --text3: #969AA2;
      --border: rgba(0,0,0,.09); --accent: #5460D2;
      --backdrop: #F2F2F4; --sheet: #FFFFFF; --band: #F8F8FA;
      --shadow: 0 1px 2px rgba(0,0,0,.04), 0 12px 32px -12px rgba(0,0,0,.10);
      --sans: -apple-system, BlinkMacSystemFont, "PingFang SC", "Segoe UI", "Microsoft YaHei UI", "Noto Sans CJK SC", system-ui, sans-serif;
      --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
      margin: 0; padding: 40px 24px 64px; background: var(--backdrop); color: var(--text);
      font-family: var(--sans); font-size: 17px; line-height: 1.6; text-align: left;
      letter-spacing: 0; font-kerning: normal; text-autospace: normal;
      -webkit-font-smoothing: antialiased; overflow-wrap: break-word;
    }
    .card.nightMode, .nightMode .card, .card.night_mode, .night_mode .card {
      --bg: #16171A; --surface: rgba(255,255,255,.07);
      --text: #EDEDEF; --text2: #9A9FA8; --text3: #6E7480;
      --border: rgba(255,255,255,.09); --accent: #8A94F5;
      --backdrop: #0F1012; --sheet: #1B1C1F; --band: #202125; --shadow: none;
    }
    .card code { font-family: var(--mono); font-size: .88em; padding: .08em .36em; border-radius: 5px; background: var(--surface); overflow-wrap: anywhere; -webkit-box-decoration-break: clone; box-decoration-break: clone; }
    .card pre { font-family: var(--mono); font-size: 14px; line-height: 1.55; white-space: pre-wrap; overflow-wrap: anywhere; background: var(--surface); padding: 12px 14px; border-radius: 8px; margin: 8px 0; }
    .card pre code { padding: 0; background: none; font-size: inherit; }
    .card .code-h, .card .copy { display: none; }
    .card .scrollx { overflow-x: auto; }
    .card b, .card strong { font-weight: 600; }
    .card a { color: var(--accent); text-decoration: none; }
    .card img { max-width: 100%; height: auto; border-radius: 8px; border: 1px solid var(--border); display: block; }

    /* 纸：四种卡都一样 */
    .fam { max-width: 620px; margin: 0 auto; background: var(--sheet); border: 1px solid var(--border); border-radius: 12px; box-shadow: var(--shadow); overflow: hidden; }
    .fam .top { padding: 28px 32px 30px; }
    .fam .meta { font-size: 12px; line-height: 1.5; color: var(--text2); margin-bottom: 8px; }
    .fam .q { font-size: 24px; line-height: 1.45; font-weight: 600; text-wrap: pretty; }
    .fam.back .q { color: var(--text2); }
    .fam .shot { margin-top: 16px; }
    .fam .ans { padding: 24px 32px 28px; border-top: 1px solid var(--border); }
    .fam .a { font-size: 24px; line-height: 1.45; font-weight: 600; text-wrap: pretty; }
    .fam .a code { font-size: .84em; }
    .fam .more { margin-top: 14px; font-size: 16px; line-height: 1.65; color: var(--text2); text-wrap: pretty; }
    .fam .more ul { list-style: none; margin: 0; padding: 0; }
    .fam .more li { position: relative; padding-left: 16px; }
    .fam .more li + li { margin-top: 6px; }
    .fam .more li::before { content: ""; position: absolute; left: 3px; top: .74em; width: 5px; height: 5px; border-radius: 50%; background: var(--text3); }
    /* 答案本身是几条要点（知识片段、Ask Free 的老卡）：正文字号，编号方块 */
    .fam .a ol { list-style: none; margin: 0; padding: 0; counter-reset: p; font-size: 17px; font-weight: 400; line-height: 1.6; }
    .fam .a ol li { position: relative; counter-increment: p; padding-left: 30px; }
    .fam .a ol li + li { margin-top: 10px; }
    .fam .a ol li::before { content: counter(p); position: absolute; left: 0; top: .2em; width: 20px; height: 20px; border-radius: 5px; background: var(--surface); color: var(--text2); font-size: 12px; line-height: 20px; text-align: center; font-variant-numeric: tabular-nums; }
    /* 截图：带 class="lead" 的放在问题下面，别的收进「当时的画面」 */
    .fam .shot:not(:has(img.lead)) { display: none; }
    .fam details.pic:has(img.lead) { display: none; }

    /* 纸底一条：出处在左，「打开原文」在右，折叠在下 */
    .fam .foot { padding: 14px 32px 16px; border-top: 1px solid var(--border); background: var(--band); }
    .fam .foot:not(:has(.src > *, details:not(.pic), img:not(.lead))) { display: none; }
    .fam .src { display: flex; flex-wrap: wrap; align-items: baseline; gap: 0 16px; font-size: 13px; line-height: 1.6; color: var(--text2); }
    .fam .src:empty { display: none; }
    .fam .src .open { margin-left: auto; font-weight: 500; white-space: nowrap; }
    .fam .src + details { margin-top: 6px; }
    .fam details > summary { display: inline-flex; align-items: center; gap: 8px; list-style: none; cursor: pointer; font-size: 13px; font-weight: 500; color: var(--text2); padding: 2px 0; }
    .fam details > summary::-webkit-details-marker { display: none; }
    .fam details > summary::before { content: ""; width: 5px; height: 5px; margin: 0 2px; border-right: 1.5px solid var(--text3); border-bottom: 1.5px solid var(--text3); transform: rotate(-45deg); transition: transform .15s; }
    .fam details[open] > summary::before { transform: rotate(45deg); }
    .fam details .body { margin: 6px 0 4px 17px; font-size: 15px; line-height: 1.6; color: var(--text2); text-wrap: pretty; }

    /* 单词卡：句子在前 */
    .fam .ctx { font-size: 24px; line-height: 1.5; text-wrap: pretty; }
    .fam .kw { --c: var(--accent); --l: .34em; --w: 1.5px; padding: 0 .16em; margin: 0 .03em;
      background: linear-gradient(var(--c),var(--c)) left top / var(--l) var(--w) no-repeat, linear-gradient(var(--c),var(--c)) left top / var(--w) var(--l) no-repeat,
      linear-gradient(var(--c),var(--c)) right top / var(--l) var(--w) no-repeat, linear-gradient(var(--c),var(--c)) right top / var(--w) var(--l) no-repeat,
      linear-gradient(var(--c),var(--c)) left bottom / var(--l) var(--w) no-repeat, linear-gradient(var(--c),var(--c)) left bottom / var(--w) var(--l) no-repeat,
      linear-gradient(var(--c),var(--c)) right bottom / var(--l) var(--w) no-repeat, linear-gradient(var(--c),var(--c)) right bottom / var(--w) var(--l) no-repeat; }
    .fam .tr { margin-top: 10px; font-size: 16px; color: var(--text2); }
    .fam .tr u { text-decoration: none; color: var(--text); box-shadow: inset 0 -2px var(--accent); }
    .fam .sense { font-size: 30px; line-height: 1.3; font-weight: 600; }
    .fam .hw { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 10px; margin-top: 8px; font-size: 14px; color: var(--text2); }
    .fam .hw b { font-size: 17px; font-weight: 600; color: var(--text); }
    .fam .hw .ipa { font-family: var(--mono); }
    .fam .mean { margin-top: 12px; font-size: 15px; color: var(--text2); }

    @media (max-width: 520px) {
      .card { padding: 0; background: var(--sheet); font-size: 16px; }
      .fam { max-width: none; border: 0; border-radius: 0; box-shadow: none; }
      .fam .top, .fam .ans { padding: 20px 16px 22px; }
      .fam .foot { padding: 12px 16px 16px; }
      .fam .q, .fam .a, .fam .ctx { font-size: 20px; }
      .fam .sense { font-size: 26px; }
      .fam .more { font-size: 15px; }
      .fam details > summary { padding: 8px 0; margin: -6px 0; }
    }
    """
}

/// 要放进 Anki 的一张卡：写进共用的「学习卡 · 问答」（规范在 DESIGN.md「往 Anki 里加卡」）
public struct AnkiCard: Equatable, Sendable {
    /// 话题 id：导完记「已在 Anki」用
    public let threadID: String
    /// 「学习卡 · 问答」的九个字段
    public let fields: [String: String]
    public let tags: [String]
    /// 截图在 Anki 媒体库里的文件名和内容（没有截图的问题是 nil）
    public let mediaName: String?
    public let mediaData: Data?
    /// 每个问题唯一的编号（ID 字段）：判重、在 Anki 里找这张都靠它。老版本放在「Ask Free 笔记」正面末尾，样子一样
    public let marker: String
}

public enum AnkiCardBuilder {
    /// 卡片默认进的牌组（设置里能改）
    public static let defaultDeck = "知识"
    /// 老版本的牌组和笔记类型：老卡留在原来的笔记类型里，只换成同一张纸
    public static let legacyDeck = "Ask Free"
    public static let legacyModel = "Ask Free 笔记"
    public static let fromTag = "来自::Ask_Free"

    public static func idMarker(turnID: String) -> String { "askfree-\(turnID)" }

    /// 纸顶小字里的「怎么问的」：和笔记页上每题时间后面那几个字一样
    public static func kind(via: String?, hasScreenshot: Bool) -> String {
        switch via {
        case "type": return "打字问"
        case "plain": return "只提问"
        case "screen": return "看屏幕问"
        default: return hasScreenshot ? "看屏幕问" : "只提问"
        }
    }

    static let renderer = AnswerHTML(math: { tex, display in
        let body = AnswerHTML.escape(tex)
        return display ? "\\[\(body)\\]" : "\\(\(body)\\)"
    })

    /// 整理好的要点拆成「一句答案 + 补充」：第一条是答案，其余是补充（两条以上是圆点，一条就一段）
    static func answerAndMore(_ points: String) -> (answer: String, more: String) {
        let blocks = AnswerBlocks.parse(points, streaming: false)
        guard let first = blocks.firstIndex(where: {
            switch $0 {
            case .bullet, .numbered, .paragraph: return true
            default: return false
            }
        }) else { return (renderer.html(points), "") }
        let answer: String
        switch blocks[first] {
        case .bullet(let text), .paragraph(let text): answer = renderer.inline(text)
        case .numbered(_, let text): answer = renderer.inline(text)
        default: answer = ""
        }
        var rest = blocks
        rest.remove(at: first)
        let items = rest.filter { if case .pending = $0 { return false } else { return true } }
        if items.count == 1, case .bullet(let text) = items[0] { return (answer, renderer.inline(text)) }
        if items.count == 1, case .numbered(_, let text) = items[0] { return (answer, renderer.inline(text)) }
        return (answer, renderer.html(blocks: items))
    }

    /// item：这个问题整理出的笔记；screenshot：它的截图（没有就 nil）。公式在 Anki 里用它自带的 MathJax（\( \)、\[ \]）
    public static func card(item: DayNoteItem, question: String, kind: String, day: String, time: String, screenshot: Data?) -> AnkiCard {
        let mediaName = screenshot == nil ? nil : "askfree-\(item.turnID).jpg"
        let marker = idMarker(turnID: item.turnID)
        let (answer, more) = answerAndMore(item.points)
        let fields: [String: String] = [
            "Question": AnswerHTML.escape(question).replacingOccurrences(of: "\n", with: "<br>"),
            "Answer": answer,
            "More": more,
            "Quote": "",
            // 看屏幕问的那一屏是问题的一部分：class="lead" 放在问题下面
            "Image": mediaName.map { "<img class=\"lead\" src=\"\($0)\">" } ?? "",
            "Label": "Ask Free · \(kind)",
            "Source": AnswerHTML.escape("\(item.title) · \(day) \(time)"),
            "Link": "",
            "ID": marker,
        ]
        return AnkiCard(threadID: item.id, fields: fields, tags: [fromTag, "askfree-\(day)"],
                        mediaName: mediaName, mediaData: screenshot, marker: marker)
    }
}

/// 导进 Anki 的结果
public struct AnkiImportResult: Equatable, Sendable {
    /// 新加的卡片：话题 id
    public let added: [String]
    /// Anki 里已经有的，没有重复加
    public let skipped: [String]
    /// 没加进去：Anki 回了空
    public let failed: [String]
}

public enum AnkiConnectError: LocalizedError, Equatable {
    /// 连不上：Anki 没开，或者没装 AnkiConnect 插件
    case notRunning
    case api(String)
    case badResponse
    /// 「学习卡 · 问答」的样式第一行不是「卡片家族 vN」：你在 Anki 里改过模板，要先问你换不换
    case customizedStyle(model: String)

    public var errorDescription: String? {
        switch self {
        case .notRunning: return "Anki 没开着，或者没装 AnkiConnect 插件"
        case .api(let message): return "Anki 回了一个错误：\(message)"
        case .badResponse: return "Anki 的回答读不懂"
        case .customizedStyle(let model): return "「\(model)」的模板在 Anki 里改过"
        }
    }
}

/// 遇到你在 Anki 里改过的模板怎么办
public enum CustomizedStyle: String, Sendable {
    case ask, replace, keep
}

/// 老的「Ask Free 笔记」（Front、Back、Source 三个字段）换成同一张纸：字段不动，只换模板和样式
enum LegacyNote {
    /// 1.4.0 及以前建它时写的样式：Anki 里还是这一份，说明没被你改过，可以直接换
    static let originalCSS = """
    .card { font-family: -apple-system, "PingFang SC", "Helvetica Neue", Arial, sans-serif; font-size: 17px; line-height: 1.5; text-align: left; color: #222; background: #fff; }
    .q { font-size: 20px; font-weight: 600; }
    .shot img { max-width: 100%; border-radius: 8px; margin-top: 12px; }
    .source { margin-top: 16px; font-size: 12px; color: #888; }
    ul.pts { padding-left: 1.2em; } ul.pts li { margin: 6px 0; } li.blk { list-style: none; margin-left: -1.2em; }
    code { font-family: Menlo, monospace; font-size: 0.9em; background: #f1f1f3; padding: 1px 4px; border-radius: 4px; }
    pre { background: #f6f6f8; padding: 10px 12px; border-radius: 8px; overflow-x: auto; white-space: pre-wrap; }
    pre code { background: none; padding: 0; }
    .code-h, .copy { display: none; }
    """

    static let templateName = "问答"
    static let front = """
    <div class="fam"><div class="top"><div class="meta">Ask Free</div>{{Front}}</div></div>
    """
    static let back = """
    <div class="fam back"><div class="top"><div class="meta">Ask Free</div>{{Front}}</div>
    <div class="ans"><div class="a">{{Back}}</div></div>
    <div class="foot"><div class="src"><span>{{Source}}</span></div></div></div>
    """
    /// 同一张纸，加上老字段里的写法：正面的 .shot 截图照样显示，背面的要点是编号方块
    static var css: String {
        StudyCard.css + """

        /* 老的「Ask Free 笔记」：截图在 Front 里，要点在 Back 里 */
        .fam .top .shot { display: block; }
        .fam .a ul.pts { list-style: none; margin: 0; padding: 0; counter-reset: p; font-size: 17px; font-weight: 400; line-height: 1.6; }
        .fam .a ul.pts > li { position: relative; counter-increment: p; padding-left: 30px; }
        .fam .a ul.pts > li + li { margin-top: 10px; }
        .fam .a ul.pts > li::before { content: counter(p); position: absolute; left: 0; top: .2em; width: 20px; height: 20px; border-radius: 5px; background: var(--surface); color: var(--text2); font-size: 12px; line-height: 20px; text-align: center; font-variant-numeric: tabular-nums; }
        .fam .a ul.pts > li.blk { counter-increment: none; }
        .fam .a ul.pts > li.blk::before { content: none; }
        """
    }
}

/// AnkiConnect（Anki 的插件，只听本机 8765 端口）的客户端。和 GetNewWord、ChatCards 连 Anki 的办法一样：
/// 一个 JSON 请求 {action, version, params}，回 {result, error}
public final class AnkiConnect: @unchecked Sendable {
    public static let defaultURL = URL(string: "http://127.0.0.1:8765")!
    /// AnkiConnect 在 AnkiWeb 上的编号，也是 addons21 下的文件夹名
    public static let addonCode = "2055492159"
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
        if let error = json["error"] as? String, !error.isEmpty { throw AnkiConnectError.api(Self.readable(error)) }
        return json["result"]
    }

    /// AnkiConnect 的英文错误里，常见的换成能看懂的话
    static func readable(_ error: String) -> String {
        if error.contains("Close the affected editor") {
            return "Anki 里开着卡片浏览器或「添加」窗口，Anki 不让这时改笔记类型；关掉它再送"
        }
        return error
    }

    // MARK: 动作

    /// Anki 开着、AnkiConnect 在听就返回它的版本
    public func version() async throws -> Int {
        guard let v = try await call("version") as? Int else { throw AnkiConnectError.badResponse }
        return v
    }

    public func deckNamesAndIds() async throws -> [String: Int] {
        guard let raw = try await call("deckNamesAndIds") as? [String: Any] else { throw AnkiConnectError.badResponse }
        return raw.compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    /// 牌组按 id 记：你在 Anki 里改了名，跟着你改的名字走；id 找不到（删了）就按 name 找或建
    public func deck(id: Int?, orCreate name: String) async throws -> (name: String, id: Int) {
        let decks = try await deckNamesAndIds()
        if let id, let current = decks.first(where: { $0.value == id })?.key { return (current, id) }
        if let existing = decks[name] { return (name, existing) }
        guard let created = (try await call("createDeck", ["deck": name]) as? NSNumber)?.intValue else { throw AnkiConnectError.badResponse }
        return (name, created)
    }

    /// 「学习卡 · 问答」缺了就建；Anki 里的版本旧了就换模板和样式（不加删字段，不用单向同步）。
    /// 同名的不是我们的（字段对不上）就不碰它，改用「学习卡 · 问答 2」。返回要往哪个笔记类型里写
    func prepareNoteType(customized: CustomizedStyle) async throws -> String {
        let names = (try await call("modelNames") as? [String]) ?? []
        if names.contains(AnkiCardBuilder.legacyModel) { try await restyleLegacyIfUntouched() }
        for name in [StudyCard.name, StudyCard.otherName] {
            guard names.contains(name) else {
                _ = try await call("createModel", [
                    "modelName": name,
                    "inOrderFields": StudyCard.fields,
                    "css": StudyCard.css,
                    "isCloze": false,
                    "cardTemplates": [["Name": StudyCard.templateName, "Front": StudyCard.front, "Back": StudyCard.back]],
                ])
                return name
            }
            let fields = (try await call("modelFieldNames", ["modelName": name]) as? [String]) ?? []
            guard fields == StudyCard.fields else { continue }
            let css = try await styling(name)
            if let v = StudyCard.version(ofCSS: css) {
                // 只往新的换：Anki 里的比我们带的新（别的软件先更新了），不动
                if v < StudyCard.version { try await restyle(name, css: StudyCard.css, front: StudyCard.front, back: StudyCard.back, template: StudyCard.templateName) }
            } else {
                switch customized {
                case .ask: throw AnkiConnectError.customizedStyle(model: name)
                case .replace: try await restyle(name, css: StudyCard.css, front: StudyCard.front, back: StudyCard.back, template: StudyCard.templateName)
                case .keep: break
                }
            }
            return name
        }
        throw AnkiConnectError.api("「\(StudyCard.name)」和「\(StudyCard.otherName)」都是别的笔记类型")
    }

    /// 老的「Ask Free 笔记」：还是当初建的样子才换成纸（版本旧了也换）；你改过的不动
    func restyleLegacyIfUntouched() async throws {
        let css = try await styling(AnkiCardBuilder.legacyModel)
        let untouched = css.trimmingCharacters(in: .whitespacesAndNewlines) == LegacyNote.originalCSS.trimmingCharacters(in: .whitespacesAndNewlines)
        let older = StudyCard.version(ofCSS: css).map { $0 < StudyCard.version } ?? false
        guard untouched || older else { return }
        try await restyle(AnkiCardBuilder.legacyModel, css: LegacyNote.css, front: LegacyNote.front, back: LegacyNote.back, template: LegacyNote.templateName)
    }

    private func styling(_ model: String) async throws -> String {
        let styling = try await call("modelStyling", ["modelName": model]) as? [String: Any]
        return styling?["css"] as? String ?? ""
    }

    private func restyle(_ model: String, css: String, front: String, back: String, template: String) async throws {
        _ = try await call("updateModelStyling", ["model": ["name": model, "css": css]])
        _ = try await call("updateModelTemplates", ["model": ["name": model, "templates": [template: ["Front": front, "Back": back]]]])
    }

    /// 这张在 Anki 里了没有：按 ID 字段找，也找老版本放在「Ask Free 笔记」正面的同一个编号
    static func query(for markers: [String]) -> String {
        markers.map { "\"ID:\($0)\" OR \"Front:*\($0)*\"" }.joined(separator: " OR ")
    }

    /// 把这些卡片放进牌组：Anki 里已经有的（按编号找到）不重复加。问法一样的两个问题（「这是什么意思？」）是两张卡，
    /// 所以不让 Anki 按问题判重。没连上 Anki 抛 notRunning，此时一张都没加
    public func add(_ cards: [AnkiCard], deck: String, customized: CustomizedStyle = .ask) async throws -> AnkiImportResult {
        _ = try await version()
        let model = try await prepareNoteType(customized: customized)
        var skipped: [String] = []
        var fresh: [AnkiCard] = []
        for card in cards {
            let found = try await call("findNotes", ["query": Self.query(for: [card.marker])]) as? [Any] ?? []
            if found.isEmpty { fresh.append(card) } else { skipped.append(card.threadID) }
        }
        var added: [String] = []
        var failed: [String] = []
        if !fresh.isEmpty {
            var notes: [[String: Any]] = []
            for card in fresh {
                var fields = card.fields
                if let name = card.mediaName, let data = card.mediaData {
                    // Anki 回的是它实际存下的文件名（重名、大小写不同时会和我们给的不一样），卡片里引用它
                    let stored = try await call("storeMediaFile", ["filename": name, "data": data.base64EncodedString()]) as? String ?? name
                    if stored != name { fields["Image"] = fields["Image"]?.replacingOccurrences(of: "src=\"\(name)\"", with: "src=\"\(AnswerHTML.escape(stored))\"") }
                }
                notes.append(["deckName": deck, "modelName": model, "fields": fields, "tags": card.tags,
                              "options": ["allowDuplicate": true]])
            }
            let ids = (try await call("addNotes", ["notes": notes]) as? [Any]) ?? []
            guard ids.count == fresh.count else { throw AnkiConnectError.badResponse }
            for (card, id) in zip(fresh, ids) {
                if id is NSNull { failed.append(card.threadID) } else { added.append(card.threadID) }
            }
        }
        return AnkiImportResult(added: added, skipped: skipped, failed: failed)
    }

    /// 在 Anki 的卡片浏览器里只看这些卡
    public func browse(markers: [String]) async throws {
        _ = try await call("guiBrowse", ["query": Self.query(for: markers)])
    }

    // MARK: 老牌组「Ask Free」

    /// 老版本放卡的「Ask Free」牌组里有几张卡（没有这个牌组就是 0）
    public func legacyCardCount() async throws -> Int {
        let decks = try await deckNamesAndIds()
        guard decks[AnkiCardBuilder.legacyDeck] != nil else { return 0 }
        return (try await call("findCards", ["query": "deck:\"\(AnkiCardBuilder.legacyDeck)\""]) as? [Any])?.count ?? 0
    }

    /// 把「Ask Free」里的卡搬进新牌组（复习记录跟着卡走，普通同步），搬空了再删掉这个牌组
    public func moveLegacyCards(to deck: String) async throws {
        let query = "deck:\"\(AnkiCardBuilder.legacyDeck)\""
        let cards = (try await call("findCards", ["query": query]) as? [Any]) ?? []
        if !cards.isEmpty { _ = try await call("changeDeck", ["cards": cards, "deck": deck]) }
        let left = (try await call("findCards", ["query": query]) as? [Any]) ?? []
        guard left.isEmpty else { throw AnkiConnectError.api("「\(AnkiCardBuilder.legacyDeck)」里还剩 \(left.count) 张没搬走") }
        _ = try await call("deleteDecks", ["decks": [AnkiCardBuilder.legacyDeck], "cardsToo": true])
    }
}
