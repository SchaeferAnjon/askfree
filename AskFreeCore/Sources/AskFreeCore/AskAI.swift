import Foundation

/// 一问里的图只认一份：模型点名的 `[[图片: …]]` 优先，联网路线顺手找的图在点名之后到就丢掉。
/// 回调来自不同线程，用锁。
final class AskImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var named = false

    /// 第一次点名返回 true（只找一次图）
    func markNamed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if named { return false }
        named = true
        return true
    }

    var isNamed: Bool {
        lock.lock(); defer { lock.unlock() }
        return named
    }
}

/// 会员模式下这一问要带的：凭据、用量号（同一个问题下的请求只算一次）、计量返回头交回哪里（后台线程回调）
public struct AskMember {
    public let credentials: MemberCredentials
    public let useId: String
    public let onUse: (MemberUseHeaders) -> Void

    public init(credentials: MemberCredentials, useId: String, onUse: @escaping (MemberUseHeaders) -> Void = { _ in }) {
        self.credentials = credentials
        self.useId = useId
        self.onUse = onUse
    }

    var headers: [String: String] { credentials.headers(useId: useId) }
}

/// 问答走的那一家：自带 Key 的服务商（qwen / deepseek / zhipu / doubao），或会员后台。
/// 会员后台把请求转给 deepseek-flash，所以名字也是 deepseek：联网工具、看屏幕工具、视觉候选都照 DeepSeek 走，
/// 只是地址换成后台、Key 换成设备令牌、多带一个 X-Use-Id，思考一律关（后台也会关）
struct AskProvider {
    let name: String
    let url: URL
    let model: String
    let apiKey: String
    var member: AskMember? = nil

    var isMember: Bool { member != nil }

    /// 带图的请求发到哪：会员也是同一个后台地址
    var visionURL: URL? { member != nil ? url : AskVision.visionEndpoint(provider: name) }

    static func member(_ member: AskMember) -> AskProvider {
        AskProvider(name: "deepseek", url: MemberEndpoint.url(member.credentials.base, MemberEndpoint.chatPath),
                    model: MemberEndpoint.model, apiKey: member.credentials.token, member: member)
    }
}

/// 已经发出去的一个请求，能中途掐掉（整理笔记时的「停下」）
public final class AskRequestHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private weak var task: URLSessionTask?

    public init() {}

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    fileprivate func attach(_ task: URLSessionTask?) {
        lock.lock()
        self.task = task
        let already = cancelled
        lock.unlock()
        if already { task?.cancel() }
    }
}

/// 语音问答：把问题（可带屏幕截图）交给用户配置的模型，流式返回回答；要联网时自己搜或转千问联网。
/// 会员模式下（answer 带了 member）问答和联网都走我们的后台
public class AskAI {
    private static let defaultDoubaoModel = "doubao-seed-2-0-pro-260215"
    private let doubaoURL = URL(string: "https://ark.cn-beijing.volces.com/api/v3/chat/completions")!
    public var debugLog: ((String) -> Void)?

    public init() {}

    /// 千问问答用的模型：未选过 → 自动选择（质量优先 + 额度用完自动降级）；手动选过的值原样保留。
    static func qwenModel(config: AskFreeConfig) -> String {
        let saved = config.string(forKey: "qwen_ask_model")
        return (saved?.isEmpty == false) ? saved! : QwenModelRouter.autoValue
    }

    /// 问答用的通道：「模型」页选的那家；它没填 Key 时按千问、DeepSeek、智谱、豆包的顺序取第一个填了 Key 的。
    private func askProvider() -> AskProvider? {
        let provider = AskFreeConfig.shared.string(forKey: "ask_provider") ?? "qwen"
        if let found = providerConfig(provider) { return found }
        for name in ["qwen", "deepseek", "zhipu", "doubao"] {
            if let found = providerConfig(name) { return found }
        }
        return nil
    }

    /// 有没有一家能用的问答模型（首页健康卡用）。会员模式下不用 Key，连得到后台就算有
    public func isConfigured() -> Bool {
        if UsageMode.current() == .member { return MemberEndpoint.current != nil }
        return askProvider() != nil
    }

    private func providerConfig(_ provider: String) -> AskProvider? {
        let config = AskFreeConfig.shared

        switch provider {
        case "qwen":
            guard let key = config.string(forKey: "dashscope_api_key", envKey: "DASHSCOPE_API_KEY"),
                  !key.isEmpty else { return nil }
            let model = Self.qwenModel(config: config)
            let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
            return AskProvider(name: "qwen", url: url, model: model, apiKey: key)
        case "deepseek":
            guard let key = config.string(forKey: DeepSeekEndpoint.secretKey, envKey: DeepSeekEndpoint.envKey),
                  !key.isEmpty else { return nil }
            let saved = config.string(forKey: DeepSeekEndpoint.modelConfigKey)
            let model = (saved?.isEmpty == false) ? saved! : DeepSeekEndpoint.defaultModel
            guard let url = DeepSeekEndpoint.chatCompletions else { return nil }
            return AskProvider(name: "deepseek", url: url, model: model, apiKey: key)
        case "zhipu":
            guard let key = config.string(forKey: "zhipu_api_key", envKey: "ZHIPU_API_KEY"),
                  !key.isEmpty else { return nil }
            let model = config.string(forKey: "zhipu_ask_model") ?? ZhipuEndpoint.defaultModel
            // Coding Plan 的 Key 只能走 /api/coding/paas/v4；按量付费的 Key 在配置里把
            // zhipu_base_url 改回 /api/paas/v4（见 ZhipuEndpoint）。
            guard let url = ZhipuEndpoint.chatCompletions else { return nil }
            return AskProvider(name: "zhipu", url: url, model: model, apiKey: key)
        default:
            guard let key = getAPIKey() else { return nil }
            let saved = config.string(forKey: "doubao_ask_model")
            let doubaoModel = (saved?.isEmpty == false) ? saved! : Self.defaultDoubaoModel
            return AskProvider(name: "doubao", url: doubaoURL, model: doubaoModel, apiKey: key)
        }
    }


    private func getAPIKey() -> String? {
        // 统一走 AskFreeConfig：secret 路由到 Keychain（env 命中后经 saveSecret 持久化）。
        // 旧版遗留的 Keychain item 由 reconcileSecrets / migrateLegacyArkKeychainItem 迁移，此处不再回写明文。
        AskFreeConfig.shared.string(forKey: "ark_api_key", envKey: "ARK_API_KEY", persistEnvValue: true)
    }

    // MARK: - 语音问答

    static let askSystemPrompt = """
    你是用户身边的语音问答助手。用户用语音提问，问题可能带口语、可能不完整。直接回答：先给结论，再展开要点；用用户提问的语言回答；不要客套，不要复述问题，结尾不要追问「要不要……」；不确定就说不确定。篇幅随问题而定：简单问题两三句说完，复杂问题可以分组展开，但不要注水。
    排版用轻量 Markdown（面板会渲染）：段落之间空一行，每段只说一件事；列举多项时逐条分行，用「1. 」或「- 」开头；内容分几组时用「### 组名」做小标题；每条里的关键词用 **加粗** 标出（一条最多一处）；不用表格、引用。代码和命令用 Markdown 代码块，开头的 ``` 后面标上语言（如 ```python）。数学公式用 LaTeX：行内公式用 $...$，单独成行的公式用 $$...$$ 并单独占一行；不用 \\(、\\[、\\boxed、\\tag。
    """

    /// 设置里开着「附图」才告诉模型面板能放图
    static var imagePromptSuffix: String { ImageSearch.isEnabled ? ImageSearch.promptSuffix : "" }

    /// 模型没有时钟：每次提问都把「现在」写进提示词。不写的话它只能从搜到的网页里猜今天几号
    /// （网页常是前一两天发的，2026-09-11 实测 4 次全答成前一天），问「现在几点」也答不出。
    static func askTimeLine(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)
        let week = ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, (c.weekday ?? 1) - 1))]
        let offset = timeZone.secondsFromGMT(for: now)
        let zone: String
        if offset == 8 * 3600 {
            zone = "北京时间"
        } else {
            let h = offset / 3600, m = abs(offset % 3600) / 60
            zone = m == 0 ? String(format: "UTC%+d", h) : String(format: "UTC%+d:%02d", h, m)
        }
        return "当前时间：\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日 星期\(week) "
            + String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) + "（\(zone)）。"
    }

    /// 问题里带时效词（今天/最新/价格…）→ 联网时强制搜索。
    static func isTimeSensitive(_ question: String) -> Bool {
        let cues = ["今天", "现在", "目前", "最近", "最新", "新闻", "价格", "股价", "汇率", "天气", "几号", "星期",
                                 "多少钱", "发布", "更新", "今年", "本周", "这周", "昨天", "明天", "上市", "2025", "2026", "2027"]
        return cues.contains { question.contains($0) }
    }

    /// 提问时附带的屏幕内容。只随当轮发送：对话上下文里只留文字，不重复传图（历史另存一份，见 AskHistoryStore）。
    public struct AskScreenContext {
        public let overviewJPEG: Data
        public let closeUpJPEG: Data

        public init(overviewJPEG: Data, closeUpJPEG: Data) {
            self.overviewJPEG = overviewJPEG
            self.closeUpJPEG = closeUpJPEG
        }

        public var sizeSummary: String {
            AskVision.sizeSummary(overviewJPEG: overviewJPEG, closeUpJPEG: closeUpJPEG)
        }
    }

    /// 用「模型」页配置的模型回答一个问题（千问附带联网搜索；问题带时效词时强制搜）。
    /// history：本话题之前的问答对（多轮续聊时带上，最多 6 轮）。
    /// screen：这一轮附带的屏幕内容，非 nil 时换成同一家的视觉模型、走 OpenAI 兼容的 content 数组。
    /// 追问（history 非空）时屏幕按需看：先只发文字，模型调用 look_at_screen 才把 screen 发过去（AskScreenTool）。
    /// onScreenUsed：这一问真的把 screen 发给了模型（主线程回调），面板据此挂截图。
    /// onPartial：流式输出，每收到一段就回调累计文本。
    /// onStats：一段可以直接拼进日志的元信息（模型、思考字数、首字耗时），不含任何问答内容。
    /// member：会员模式下这一问的凭据和用量号；给了就不看用户自己填的 Key，问答和联网都走后台
    public func answer(question: String,
                       history: [(question: String, answer: String)] = [],
                       screen: AskScreenContext? = nil,
                       member: AskMember? = nil,
                       onPartial: ((String) -> Void)? = nil,
                       onImages: (([AskImage]) -> Void)? = nil,
                       onScreenUsed: (() -> Void)? = nil,
                       onRouteNote: ((String) -> Void)? = nil,
                       onThinking: (() -> Void)? = nil,
                       onStats: ((String) -> Void)? = nil,
                       completion: @escaping (Result<String, Error>) -> Void) {
        // 模型点名要图（`[[图片: 搜索词]]`）：标记行不给用户看，一出现就去找图，和回答并行
        let imageRequest = AskImageRequest()
        let onPartial: (String) -> Void = { [weak self] text in
            let (display, query) = ImageSearch.extractMarker(text)
            if let query, imageRequest.markNamed() { self?.searchImages(query: query, question: question, onImages: onImages) }
            onPartial?(display)
        }
        let completion: (Result<String, Error>) -> Void = { [weak self] result in
            guard case .success(let text) = result else { completion(result); return }
            let (display, query) = ImageSearch.extractMarker(text, isFinal: true)
            if let query, imageRequest.markNamed() { self?.searchImages(query: query, question: question, onImages: onImages) }
            completion(.success(display))
        }
        let ownProvider = member.map(AskProvider.member) ?? askProvider()
        let looksOnRequest = screen != nil && !history.isEmpty && AskScreenTool.isSupported(provider: ownProvider?.name)
        // 已经发给模型的屏幕：按需看的追问一开始没有，模型要看之后才有；联网作答时跟着它走
        var sentScreen = looksOnRequest ? nil : screen
        if sentScreen != nil { onScreenUsed?() }
        // 会员没有千问联网这条路（要用户自己的百炼 Key）：要联网时走后台的搜索转发
        let qwenKey = member != nil ? "" : (AskFreeConfig.shared.string(forKey: "dashscope_api_key", envKey: "DASHSCOPE_API_KEY") ?? "")
        let searchProvider: AskProvider? = {
            guard !qwenKey.isEmpty, let url = AskVision.qwenChatCompletions else { return nil }
            return AskProvider(name: "qwen", url: url, model: AskVision.searchModel, apiKey: qwenKey)
        }()

        // 转给千问联网回答：三家里只有它能真的搜。这一问不带图：2026-09-21 实测千问联网不带图首字 2.1 秒，
        // 带一张图 4.8 到 6.8 秒，带两张 4.7 到 9.3 秒且很不稳。屏幕上下文改由 query 带过去：
        // 那是当前模型看完屏幕后写的搜索词（指着一张显卡问「这个多少钱」，query 就是显卡型号 + 价格）。
        // decidedMs：当前模型判断「要联网」花了多久（显式口令直接走这里时为 nil）。
        func askQwenSearch(_ provider: AskProvider, decidedMs: Int?, query: String?) {
            debugLog?("Ask route=qwen-search model=\(provider.model) decide=\(decidedMs.map { "\($0)ms" } ?? "explicit") hasQuery=\(query?.isEmpty == false)")
            onRouteNote?(AskSearch.searchingNotice)
            searchImages(query: query, question: question, onImages: onImages, unlessNamed: imageRequest)
            var announced = false
            let partial: (String) -> Void = { text in
                if !announced { announced = true; onRouteNote?(AskSearch.searchedNotice) }
                onPartial(text)
            }
            let stats: (String) -> Void = { line in
                onStats?("decide=\(decidedMs.map { "\($0)ms" } ?? "explicit") " + line)
            }
            answerDirectText(question: AskSearch.searchQuestion(question, query: query), history: history, provider: provider,
                             route: .qwenSearch, offerSearchTool: false, onPartial: partial,
                             onThinking: onThinking, onStats: stats, completion: completion)
        }

        // DeepSeek 自己搜（DeepSeekSearch），把结果连同原问题和截图交回它作答。
        // 搜索失败不硬编：照常回答，但面板上写明这次没查成、答案凭记忆。
        func askDeepSeekSearch(_ provider: AskProvider, decidedMs: Int?, query: String?) {
            let q = (query?.isEmpty == false) ? query! : AskSearch.stripExplicitSearchPrefix(question)
            onRouteNote?(AskSearch.searchingNotice)
            searchImages(query: query, question: question, onImages: onImages, unlessNamed: imageRequest)
            let started = ProcessInfo.processInfo.systemUptime
            DeepSeekSearch.search(query: q, apiKey: provider.apiKey, member: provider.member) { [weak self] result in
                guard let self else { return }
                let searchMs = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                var context: String?
                switch result {
                case .success(let results):
                    self.debugLog?("Ask route=deepseek-search decide=\(decidedMs.map { "\($0)ms" } ?? "explicit") results=\(results.count) in \(searchMs)ms")
                    context = DeepSeekSearch.promptSection(query: q, results: results)
                case .failure(let err):
                    self.debugLog?("Ask deepseek-search failed in \(searchMs)ms: \(err.localizedDescription)")
                    onRouteNote?("联网查询失败（\(err.localizedDescription)），下面是模型凭记忆的回答，可能过时。")
                }
                var announced = context == nil
                let partial: (String) -> Void = { text in
                    if !announced { announced = true; onRouteNote?(AskSearch.searchedNotice) }
                    onPartial(text)
                }
                let stats: (String) -> Void = { line in
                    onStats?("decide=\(decidedMs.map { "\($0)ms" } ?? "explicit") webSearch=\(searchMs)ms " + line)
                }
                if let sentScreen {
                    self.answerWithScreen(question: question, history: history, screen: sentScreen, provider: provider,
                                          route: .deepseekSearch, offerSearchTool: false, searchContext: context,
                                          onPartial: partial, onThinking: onThinking, onStats: stats, completion: completion)
                } else {
                    self.answerDirectText(question: question, history: history, provider: provider,
                                          route: .deepseekSearch, offerSearchTool: false, searchContext: context,
                                          onPartial: partial, onThinking: onThinking, onStats: stats, completion: completion)
                }
            }
        }

        // 用户明说要联网（「搜一下……」）：不用问模型，DeepSeek 自己搜，其他家直接走千问
        if let ownProvider, ownProvider.name == "deepseek", AskSearch.hasExplicitSearchPrefix(question) {
            askDeepSeekSearch(ownProvider, decidedMs: nil, query: nil)
            return
        }
        if let searchProvider, ownProvider?.name != "qwen", AskSearch.hasExplicitSearchPrefix(question) {
            askQwenSearch(searchProvider, decidedMs: nil, query: nil)
            return
        }

        // 其余问题带一个 web_search 函数工具让当前模型自己判断：它一调用，这条流就被掐掉、
        // 以 needsWebSearch 失败返回，这里接住去搜（DeepSeek 自己搜，其他家转千问）；它直接回答则和平时完全一样，不多花时间。
        let offerTool = AskSearch.shouldOfferTool(provider: ownProvider?.name, hasQwenKey: searchProvider != nil)
        // 追问时模型要看屏幕（needsScreen）：带上按键那一刻的截图重问一次，这一轮照样能再要联网
        func routed(_ result: Result<String, Error>) {
            if case .failure(let err) = result, case AskError.needsScreen(let ms) = err, let screen, let ownProvider {
                debugLog?("Ask follow-up looks at screen decide=\(ms)ms")
                sentScreen = screen
                DispatchQueue.main.async { onScreenUsed?() }
                answerWithScreen(question: question, history: history, screen: screen, provider: ownProvider,
                                 route: .direct, offerSearchTool: offerTool, onPartial: onPartial,
                                 onThinking: onThinking, onStats: onStats, completion: routed)
                return
            }
            if case .failure(let err) = result, case AskError.needsWebSearch(let ms, let query) = err {
                if let ownProvider, ownProvider.name == "deepseek" {
                    askDeepSeekSearch(ownProvider, decidedMs: ms, query: query)
                    return
                }
                if let searchProvider {
                    askQwenSearch(searchProvider, decidedMs: ms, query: query)
                    return
                }
            }
            completion(result)
        }

        if let sentScreen, let provider = ownProvider {
            answerWithScreen(question: question, history: history, screen: sentScreen, provider: provider,
                             route: .direct, offerSearchTool: offerTool, onPartial: onPartial,
                             onThinking: onThinking, onStats: onStats, completion: routed)
            return
        }

        guard let provider = ownProvider else {
            completion(.failure(AskError.noAPIKey))
            return
        }
        answerDirectText(question: question, history: history, provider: provider, route: .direct,
                         offerSearchTool: offerTool, offerScreenTool: looksOnRequest, onPartial: onPartial,
                         onThinking: onThinking, onStats: onStats, completion: routed)
    }

    /// 不是问答的一次性请求（整理一天的笔记）：和回答走同一条通道（用户自己的 Key，或会员后台），
    /// 不联网、不看屏幕、不思考，流式收文字。onPartial 在主线程，completion 在后台线程。
    /// 返回的 handle 能中途掐掉；掐掉之后调用方别再等回调
    @discardableResult
    public func complete(system: String, user: String, maxTokens: Int, member: AskMember? = nil,
                         onPartial: ((String) -> Void)? = nil,
                         completion: @escaping (Result<String, Error>) -> Void) -> AskRequestHandle {
        let handle = AskRequestHandle()
        guard let provider = member.map(AskProvider.member) ?? askProvider() else {
            completion(.failure(AskError.noAPIKey))
            return handle
        }
        let messages: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": user]]
        let candidates: [String] = (provider.name == "qwen" && QwenModelRouter.isAuto(provider.model))
            ? QwenModelRouter.candidates(for: provider.model) : [provider.model]
        func attempt(_ index: Int) {
            guard index < candidates.count else {
                completion(.failure(AskError.apiError("问答模型均不可用（额度用完）")))
                return
            }
            let model = candidates[index]
            var body: [String: Any] = ["model": model, "messages": messages, "stream": true, "temperature": 0.3,
                                       "max_tokens": maxTokens]
            if provider.name == "qwen" { body["top_p"] = 0.8 }
            AskVision.applyThinkingSettings(in: &body, provider: provider.name, model: model, thinking: nil)
            debugLog?("Notes request provider=\(provider.name) model=\(model) maxTokens=\(maxTokens) chars=\(user.count)")
            streamChat(url: provider.url, apiKey: provider.apiKey, body: body, member: provider.member,
                       onPartial: onPartial, handle: handle) { result in
                if case .failure(let err) = result, case AskError.quotaExhausted = err, index + 1 < candidates.count {
                    QwenModelRouter.markExhausted(model)
                    attempt(index + 1)
                    return
                }
                completion(result)
            }
        }
        attempt(0)
        return handle
    }

    /// 找几张图，和回答并行：模型点名的搜索词，或联网时顺手用搜索词（它看过屏幕），都没有就用问题本身。
    /// unlessNamed：联网顺手找的图，模型已经点名要图时就不用了（点名的词更准）
    private func searchImages(query: String?, question: String, onImages: (([AskImage]) -> Void)?,
                              unlessNamed request: AskImageRequest? = nil) {
        guard ImageSearch.isEnabled, let onImages else { return }
        let imageQuery = (query?.isEmpty == false) ? query! : AskSearch.stripExplicitSearchPrefix(question)
        let started = ProcessInfo.processInfo.systemUptime
        ImageSearch.search(imageQuery) { [weak self] images in
            let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            self?.debugLog?("Ask images: \(images.count) in \(ms)ms (\(request == nil ? "named" : "search"))")
            DispatchQueue.main.async {
                if let request, request.isNamed { return }
                onImages(images)
            }
        }
    }

    /// 纯文字提问（不带屏幕内容）：用指定通道流式回答。
    /// 千问联网默认由模型自己判断要不要搜，它觉得会答的就不搜、答案可能过期；
    /// 问题里带时效词时强制搜，其他问题维持智能判断。
    /// 搜索档位一律用默认，别指定 search_strategy="standard"：它只拿回默认档约一半的资料、结果偏旧
    /// （2026-09-11 实测「美联储主席是谁」standard 档 3 次都答成已卸任的前任，默认档每次都对）。
    private func answerDirectText(question: String,
                                  history: [(question: String, answer: String)],
                                  provider: AskProvider,
                                  route: AskVision.AskRoute,
                                  offerSearchTool: Bool,
                                  offerScreenTool: Bool = false,
                                  searchContext: String? = nil,
                                  allowThinking: Bool = true,
                                  onPartial: ((String) -> Void)?,
                                  onThinking: (() -> Void)?,
                                  onStats: ((String) -> Void)?,
                                  completion: @escaping (Result<String, Error>) -> Void) {
        let system = Self.askSystemPrompt + Self.imagePromptSuffix + (offerSearchTool ? AskSearch.toolPromptSuffix : "")
            + (offerScreenTool ? AskScreenTool.promptSuffix : "") + "\n" + Self.askTimeLine() + (searchContext ?? "")
            + AskReplyLanguage.promptLine(for: question)
        let tools = (offerSearchTool ? AskSearch.tools() : []) + (offerScreenTool ? [AskScreenTool.tool()] : [])
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for turn in history.suffix(6) {
            messages.append(["role": "user", "content": turn.question])
            messages.append(["role": "assistant", "content": turn.answer])
        }
        messages.append(["role": "user", "content": question])

        let forceSearch = Self.isTimeSensitive(question)
        // 转千问联网的那一问不思考：它要的是查到的事实，再想几秒不值
        // 会员一律不思考：后台定死关思考，开了也只会让 max_tokens 留得太多
        let thinking = (route == .qwenSearch || !allowThinking || provider.isMember) ? nil : AskThinkingSettings.current
        debugLog?("Ask route=\(route.rawValue) provider=\(provider.name) model=\(provider.model) forceSearch=\(forceSearch) thinking=\(thinking?.rawValue ?? "off") history=\(history.count) screenTool=\(offerScreenTool)")
        func makeBody(_ model: String, search: Bool) -> [String: Any] {
            var body: [String: Any] = ["model": model, "messages": messages, "stream": true]
            if provider.name == "qwen" {
                body["top_p"] = 0.8; body["temperature"] = 0.5
                AskVision.applyThinkingSettings(in: &body, provider: "qwen", model: model, thinking: thinking)
                if thinking != nil { body["max_tokens"] = AskVision.thinkingMaxTokens }
                if search {
                    body["enable_search"] = true
                    if forceSearch { body["search_options"] = ["forced_search": true] }
                }
            } else {
                body["temperature"] = 0.5
                // 关思考万一没生效，思考内容占 max_tokens，给 1200 会被截断，所以多留余量
                body["max_tokens"] = thinking != nil ? AskVision.thinkingMaxTokens
                    : (AskVision.forcesThinking(model: model) ? 2048 : 1200)
                AskVision.applyThinkingSettings(in: &body, provider: provider.name, model: model, thinking: thinking)
            }
            if !tools.isEmpty { body["tools"] = tools }
            if let choice = AskSearch.forcedToolChoice(provider: provider.name, question: question,
                                                       offered: offerSearchTool, thinking: thinking != nil) {
                // 带时效词的追问也可能是在问屏幕（「现在这个画面是哪集」）：只要求它调一个工具，联网还是看屏幕由它定
                body["tool_choice"] = offerScreenTool ? "required" : choice
            }
            return body
        }
        // 联网这一问模型已经定死，不走自动路由
        let candidates: [String] = (provider.name == "qwen" && route == .direct)
            ? (QwenModelRouter.isAuto(provider.model) ? QwenModelRouter.candidates(for: provider.model) : [provider.model])
            : [provider.model]
        func attempt(_ index: Int, search: Bool) {
            guard index < candidates.count else {
                completion(.failure(AskError.apiError("问答模型均不可用（额度用完）")))
                return
            }
            let model = candidates[index]
            streamChat(url: provider.url, apiKey: provider.apiKey, body: makeBody(model, search: search),
                       member: provider.member,
                       onPartial: onPartial, onThinking: onThinking,
                       toolNames: tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String },
                       thinkingDeadline: thinking?.deadline,
                       onStats: { reasoningChars, firstTokenMs in
                           let first = firstTokenMs.map { "\($0)ms" } ?? "n/a"
                           onStats?("route=\(route.rawValue) model=\(model) vision=0 search=\(search || searchContext != nil ? 1 : 0) reasoning=\(reasoningChars)ch firstToken=\(first)")
                       }) { [weak self] result in
                switch result {
                case .success(let text):
                    completion(.success(text))
                case .failure(let err):
                    if case AskError.emptyAnswer = err, thinking != nil, let self {
                        // 开着思考时偶发：想了一大段却没有正文。关掉思考重问一次，保证用户拿得到答案
                        self.debugLog?("Ask: \(err.localizedDescription) → 关思考重问")
                        self.answerDirectText(question: question, history: history, provider: provider, route: route,
                                              offerSearchTool: offerSearchTool, offerScreenTool: offerScreenTool,
                                              searchContext: searchContext,
                                              allowThinking: false, onPartial: onPartial,
                                              onThinking: onThinking, onStats: onStats, completion: completion)
                        return
                    }
                    if case AskError.quotaExhausted = err, index + 1 < candidates.count {
                        QwenModelRouter.markExhausted(model)
                        self?.debugLog?("Ask: \(model) 额度类失败，降级到下一个")
                        attempt(index + 1, search: search)
                    } else if search, case AskError.apiError = err {
                        self?.debugLog?("Ask with enable_search failed, retrying without: \(err)")
                        attempt(index, search: false)
                    } else {
                        completion(.failure(err))
                    }
                }
            }
        }
        attempt(0, search: provider.name == "qwen")
    }

    /// 带屏幕内容的提问：同一家的视觉模型 + OpenAI 兼容的 content 数组（image_url + data:image/jpeg;base64）。
    /// 历史只带文字，图片只随当轮发，多轮追问不会重复传图。
    /// 速度上的三件事：显式关思考、压住输出长度（max_tokens）、照常走流式，首字越早越好。
    private func answerWithScreen(question: String,
                                  history: [(question: String, answer: String)],
                                  screen: AskScreenContext,
                                  provider: AskProvider,
                                  route: AskVision.AskRoute,
                                  offerSearchTool: Bool,
                                  searchContext: String? = nil,
                                  allowThinking: Bool = true,
                                  onPartial: ((String) -> Void)?,
                                  onThinking: (() -> Void)?,
                                  onStats: ((String) -> Void)?,
                                  completion: @escaping (Result<String, Error>) -> Void) {
        let override = provider.isMember ? nil : AskSettings.visionOverride(provider: provider.name)
        // 联网这一问模型已经定死（AskVision.searchModel），不走视觉候选表；会员的模型由后台定
        let all = route == .qwenSearch || provider.isMember
            ? [provider.model]
            : AskVision.visionCandidates(provider: provider.name, override: override)
        // 沿用千问那套额度标记：某个模型免费额度用完了就跳过，冷却到期自动再试
        let fresh = all.filter { !QwenModelRouter.isExhausted($0) }
        let candidates = fresh.isEmpty ? all : fresh
        guard let url = provider.visionURL else {
            completion(.failure(AskError.apiError("这家服务商没有可用的视觉模型端点")))
            return
        }

        var messages: [[String: Any]] = [
            ["role": "system", "content": Self.askSystemPrompt + Self.imagePromptSuffix + AskVision.screenPromptSuffix
                + (history.isEmpty ? "" : AskScreenTool.followUpScreenNote) + (offerSearchTool ? AskSearch.toolPromptSuffix : "") + "\n" + Self.askTimeLine() + (searchContext ?? "")
                + AskReplyLanguage.promptLine(for: question)]
        ]
        for turn in history.suffix(6) {
            messages.append(["role": "user", "content": turn.question])
            messages.append(["role": "assistant", "content": turn.answer])
        }
        messages.append(["role": "user",
                         "content": AskVision.visionUserContent(question: question,
                                                                overviewJPEG: screen.overviewJPEG,
                                                                closeUpJPEG: screen.closeUpJPEG)])

        // 一般情况下带图不开联网：智谱的视觉请求 schema 里根本没有 web_search 这个工具类型。
        // 但 2026-09-21 本机实测千问 enable_search + forced_search + 两张 image_url 能同时用，
        // 而且搜索结果确实被用上了（关掉搜索同一问就答成两年前的旧数据），所以走千问联网时照样带图。
        let search = route == .qwenSearch
        let thinking = (search || !allowThinking || provider.isMember) ? nil : AskThinkingSettings.current
        func makeBody(_ model: String) -> [String: Any] {
            var body: [String: Any] = ["model": model, "messages": messages, "stream": true, "temperature": 0.5,
                                       "max_tokens": thinking != nil ? AskVision.thinkingMaxTokens : AskVision.maxTokens(provider: provider.name)]
            AskVision.applyThinkingSettings(in: &body, provider: provider.name, model: model, thinking: thinking)
            if search {
                body["enable_search"] = true
                body["search_options"] = ["forced_search": true]
            }
            if offerSearchTool { body["tools"] = AskSearch.tools() }
            if let choice = AskSearch.forcedToolChoice(provider: provider.name, question: question,
                                                       offered: offerSearchTool, thinking: thinking != nil) {
                body["tool_choice"] = choice
            }
            return body
        }

        debugLog?("Ask vision route=\(route.rawValue) provider=\(provider.name) models=\(candidates.joined(separator: ",")) search=\(search ? "on" : "off") thinking=\(thinking?.rawValue ?? "off") history=\(history.count) \(screen.sizeSummary)")

        func attempt(_ index: Int) {
            guard index < candidates.count else {
                completion(.failure(AskError.apiError("视觉模型均不可用（额度用完）")))
                return
            }
            let model = candidates[index]
            streamChat(url: url, apiKey: provider.apiKey, body: makeBody(model), member: provider.member,
                       // 开了思考，难题可能想很久，30 秒不够
                       timeout: thinking != nil ? 120 : AskVision.requestTimeout, onPartial: onPartial,
                       onThinking: onThinking,
                       toolNames: offerSearchTool ? [AskSearch.toolName] : [],
                       thinkingDeadline: thinking?.deadline,
                       onStats: { reasoningChars, firstTokenMs in
                           let first = firstTokenMs.map { "\($0)ms" } ?? "n/a"
                           onStats?("route=\(route.rawValue) model=\(model) vision=1 search=\(search || searchContext != nil ? 1 : 0) reasoning=\(reasoningChars)ch firstToken=\(first)")
                       }) { [weak self] result in
                switch result {
                case .success(let text):
                    completion(.success(text))
                case .failure(let err):
                    if case AskError.emptyAnswer = err, thinking != nil, let self {
                        self.debugLog?("Ask vision: \(err.localizedDescription) → 关思考重问")
                        self.answerWithScreen(question: question, history: history, screen: screen, provider: provider,
                                              route: route, offerSearchTool: offerSearchTool, searchContext: searchContext,
                                              allowThinking: false,
                                              onPartial: onPartial, onThinking: onThinking, onStats: onStats, completion: completion)
                        return
                    }
                    if case AskError.quotaExhausted = err, index + 1 < candidates.count {
                        QwenModelRouter.markExhausted(model)
                        self?.debugLog?("Ask vision: \(model) 额度类失败，降级到 \(candidates[index + 1])")
                        attempt(index + 1)
                        return
                    }
                    completion(.failure(err))
                }
            }
        }
        attempt(0)
    }

    /// OpenAI 兼容的流式对话（SSE）：每收到一段增量就回调累计文本，结束时给完整文本。
    private func streamChat(url: URL, apiKey: String, body: [String: Any],
                            member: AskMember? = nil,
                            timeout: TimeInterval = 90,
                            onPartial: ((String) -> Void)?,
                            onThinking: (() -> Void)? = nil,
                            toolNames: [String] = [],
                            thinkingDeadline: TimeInterval? = nil,
                            handle: AskRequestHandle? = nil,
                            onStats: ((Int, Int?) -> Void)? = nil,
                            completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in member?.headers ?? [:] { request.setValue(value, forHTTPHeaderField: name) }
        request.timeoutInterval = timeout
        let reader = SSEReader(onPartial: onPartial, onThinking: onThinking,
                               toolNames: toolNames, onStats: onStats, member: member, completion: completion)
        reader.armThinkingDeadline(thinkingDeadline)
        // 带截图的请求体有几百 KB，序列化和发出去放到后台：调用方多半在主线程上，
        // 堵住它的这几百毫秒里回答浮窗没法重新布局
        let payload = body
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            if handle?.isCancelled == true { return }
            StreamHub.shared.send(request, reader: reader)
            handle?.attach(reader.task)
        }
    }

    /// 常驻的流式会话。整个 App 只有这一个 URLSession，连接池和 TLS 会话能跨请求复用；
    /// 每个请求自己的解析器按 taskIdentifier 分发。
    private final class StreamHub: NSObject, URLSessionDataDelegate {
        static let shared = StreamHub()

        private lazy var session: URLSession = {
            let config = URLSessionConfiguration.default
            config.httpMaximumConnectionsPerHost = 4
            config.waitsForConnectivity = false
            return URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }()
        private let lock = NSLock()
        private var readers: [Int: SSEReader] = [:]

        func send(_ request: URLRequest, reader: SSEReader) {
            let task = session.dataTask(with: request)
            reader.task = task   // 模型改口要联网时，解析器要能立刻掐掉这条流
            lock.lock(); readers[task.taskIdentifier] = reader; lock.unlock()
            task.resume()
        }

        /// 预热：只是为了把 TLS 握手做掉，响应内容一概不管。
        func warmUp(_ url: URL) {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            // 带 completionHandler 的任务不走 delegate，不会打扰上面的分发表
            session.dataTask(with: request) { _, _, _ in }.resume()
        }

        private func reader(for task: URLSessionTask) -> SSEReader? {
            lock.lock(); defer { lock.unlock() }
            return readers[task.taskIdentifier]
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            reader(for: dataTask)?.receive(response: response)
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            reader(for: dataTask)?.receive(data: data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let reader = readers.removeValue(forKey: task.taskIdentifier)
            lock.unlock()
            reader?.finish(error: error)
        }
    }

    /// 提问前预热与模型端点的连接：用户说话那几秒里把 TLS 握手做掉，首字能早几百毫秒。
    public func warmUpConnection() {
        if UsageMode.current() == .member {
            if let base = MemberEndpoint.current { StreamHub.shared.warmUp(MemberEndpoint.url(base, MemberEndpoint.chatPath)) }
            return
        }
        guard let provider = askProvider() else { return }
        StreamHub.shared.warmUp(AskVision.visionEndpoint(provider: provider.name) ?? provider.url)
    }

    /// 逐块解析 SSE，把 delta.content 累计起来；非 200 时把服务端错误原样带出（403 = 额度类）。
    /// 由 StreamHub 驱动，自己不当 URLSession 的 delegate。
    private final class SSEReader {
        private let onPartial: ((String) -> Void)?
        /// 模型开始吐思考内容了（智谱 GLM-5.3 系列关不掉思考），只在第一段时回调一次
        private let onThinking: (() -> Void)?
        /// 这条流带的函数工具：模型调用其中一个就不再当回答显示，交给上层联网或看屏幕
        private let toolNames: [String]
        /// (思考内容字数, 首字耗时 ms)。关得掉思考的模型这里应该是 0，不是 0 说明参数没生效。
        private let onStats: ((Int, Int?) -> Void)?
        private let completion: (Result<String, Error>) -> Void
        /// 会员后台的请求：错误按后台的 {"error": {"code", "message"}} 读，返回头里的剩几次交回去
        private let member: AskMember?
        private var response: HTTPURLResponse?
        private var buffer = Data()
        private var accumulated = ""
        private var reasoningChars = 0
        private var statusCode = 200
        private var errorBody = Data()
        private var finished = false
        private let startedAt = ProcessInfo.processInfo.systemUptime
        private var firstTokenMs: Int?
        private var toolCalls = ToolCallAccumulator()
        /// 流是怎么结束的（stop / tool_calls / length…）。回答为空时靠它判断出了什么事
        private var finishReason: String?
        private let stateLock = NSLock()

        /// 开着思考时给「想」设一个时间上限。DeepSeek 没有限制思考长度的参数，实测会失控：
        /// 屏幕上字多的时候想了 28706 个字、45 秒，把 max_tokens 全用在思考上，一个字的正文都没给（2026-09-22）。
        /// 到点还没出正文、也没发起联网，就掐掉这条流，以 emptyAnswer 结束，上层会关思考重问。
        func armThinkingDeadline(_ seconds: TimeInterval?) {
            guard let seconds else { return }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self else { return }
                self.stateLock.lock()
                let stillThinking = !self.finished && self.firstTokenMs == nil && self.toolDecidedMs == nil
                if stillThinking { self.finishReason = "thinking-timeout" }
                self.stateLock.unlock()
                if stillThinking { self.task?.cancel() }
            }
        }
        /// 模型发起了工具调用（联网 / 看屏幕）：判定耗时记在这里
        private var toolDecidedMs: Int?
        weak var task: URLSessionTask?

        init(onPartial: ((String) -> Void)?,
             onThinking: (() -> Void)? = nil,
             toolNames: [String] = [],
             onStats: ((Int, Int?) -> Void)? = nil,
             member: AskMember? = nil,
             completion: @escaping (Result<String, Error>) -> Void) {
            self.onPartial = onPartial
            self.onThinking = onThinking
            self.toolNames = toolNames
            self.onStats = onStats
            self.member = member
            self.completion = completion
        }

        func receive(response: URLResponse) {
            let http = response as? HTTPURLResponse
            self.response = http
            statusCode = http?.statusCode ?? 200
            // 只在 200 时改剩几次：出错的这一问后台不算
            if let member, let http, http.statusCode == 200, let headers = MemberUseHeaders(http) { member.onUse(headers) }
        }

        func receive(data: Data) {
            guard statusCode == 200 else { errorBody.append(data); return }
            buffer.append(data)
            while let range = buffer.range(of: Data([0x0A])) {   // 按行切
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0...range.lowerBound)
                guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { continue }
                guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                      let choice = (json["choices"] as? [[String: Any]])?.first else { continue }
                let delta = choice["delta"] as? [String: Any]
                let message = choice["message"] as? [String: Any]
                if let reason = choice["finish_reason"] as? String, !reason.isEmpty { finishReason = reason }
                // 模型要联网 / 看屏幕：不把工具调用当回答显示。不立刻掐流，让它把参数（搜索词）吐完，
                // 整个工具调用实测 0.1 秒内就结束；搜索词是模型看完屏幕后写的，转千问时要带上。
                if !toolNames.isEmpty, let delta {
                    toolCalls.ingest(delta: delta)
                    if toolDecidedMs == nil, toolNames.contains(where: toolCalls.called) {
                        toolDecidedMs = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
                    }
                    if toolDecidedMs != nil { continue }
                }
                // 思考内容：关掉之后应该一个字都没有，收到了就说明参数没生效，记进日志好排查
                if let reasoning = (delta?["reasoning_content"] as? String) ?? (message?["reasoning_content"] as? String),
                   !reasoning.isEmpty {
                    if reasoningChars == 0 { DispatchQueue.main.async { self.onThinking?() } }
                    reasoningChars += reasoning.count
                }
                let piece = (delta?["content"] as? String) ?? (message?["content"] as? String)
                if let piece, !piece.isEmpty {
                    if firstTokenMs == nil {
                        firstTokenMs = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
                    }
                    accumulated += piece
                    let snapshot = accumulated
                    DispatchQueue.main.async { self.onPartial?(snapshot) }
                }
            }
        }

        func finish(error: Error?) {
            guard !finished else { return }
            finished = true
            // 模型发起了工具调用：不报错、不给残缺的文字，只告诉上层「这一问要看屏幕」或「要联网、想搜什么」。
            // 流以 tool_calls 结束但名字没对上：只带了一个工具就算它，带了两个按联网算。并排调了两个时先看屏幕
            if toolDecidedMs == nil, !toolNames.isEmpty, finishReason == "tool_calls" {
                toolDecidedMs = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
            }
            if let decided = toolDecidedMs {
                if toolCalls.called(AskScreenTool.toolName) || toolNames == [AskScreenTool.toolName] {
                    completion(.failure(AskError.needsScreen(decided)))
                } else {
                    completion(.failure(AskError.needsWebSearch(decided, toolCalls.searchQuery(for: AskSearch.toolName))))
                }
                return
            }
            let reasoning = reasoningChars
            let first = firstTokenMs
            DispatchQueue.main.async { self.onStats?(reasoning, first) }
            if finishReason == "thinking-timeout" {
                completion(.failure(AskError.emptyAnswer(finish: "thinking-timeout", reasoningChars: reasoning, tools: "")))
                return
            }
            if let error {
                // 会员：连不上后台按会员的话说（「连不上会员服务器」），不说成某家服务商没回应
                completion(.failure(member != nil ? MemberAPIError.network(error) : error))
                return
            }
            if member != nil, statusCode != 200 {
                completion(.failure(MemberAPIError.from(status: statusCode, data: errorBody, response: response)))
                return
            }
            guard statusCode == 200 else {
                let json = try? JSONSerialization.jsonObject(with: errorBody) as? [String: Any]
                let message = AskAI.extractAPIErrorMessage(from: json) ?? "HTTP \(statusCode)"
                // 403 是阿里/火山的额度类失败，402 是 DeepSeek 的「余额不足」
                let quotaLike = statusCode == 403 || statusCode == 402
                completion(.failure(quotaLike ? AskError.quotaExhausted(message) : AskError.apiError(message)))
                return
            }
            let text = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                // 想完了却一个字没答：把结束原因和工具名带出去，日志里能看出是怎么回事
                completion(.failure(AskError.emptyAnswer(finish: finishReason ?? "none", reasoningChars: reasoning,
                                                           tools: toolCalls.completedNames.joined(separator: ","))))
                return
            }
            completion(.success(text))
        }
    }

    public enum AskError: LocalizedError {
        /// 一家模型的 Key 都没填
        case noAPIKey
        case apiError(String)   // 服务端返回的业务错误（鉴权/限流等），带真实原因
        case quotaExhausted(String)   // 403 额度类失败（免费额度用完即停/欠费），自动路由靠它降级
        /// 模型自己判断这一问要联网；参数是判定耗时（ms）和它写的搜索词。不会让用户看见，上层拿它转千问。
        case needsWebSearch(Int, String?)
        /// 追问时模型要看屏幕；参数是判定耗时（ms）。不会让用户看见，上层带上截图重问
        case needsScreen(Int)
        /// 流正常结束但回答是空的（开思考时偶发：想了一大段，然后没有正文）
        case emptyAnswer(finish: String, reasoningChars: Int, tools: String)

        public var errorDescription: String? {
            switch self {
            case .noAPIKey: return "还没有填问答模型的 API Key，到「模型」页填一个"
            case .apiError(let msg): return msg
            case .quotaExhausted(let msg): return msg
            case .needsWebSearch: return "这一问需要联网"
            case .needsScreen: return "这一问需要看屏幕"
            case .emptyAnswer(let finish, let reasoning, let tools):
                return "模型没有给出回答（finish=\(finish) reasoning=\(reasoning)ch tools=\(tools.isEmpty ? "-" : tools)）"
            }
        }
    }

    /// 从 OpenAI 兼容 / DashScope 的错误响应里取人话原因：
    /// 兼容 {"error":{"message":...}}、{"message":...,"code":...}、{"error":"..."}。
    static func extractAPIErrorMessage(from json: [String: Any]?) -> String? {
        guard let json = json else { return nil }
        if let err = json["error"] as? [String: Any] {
            let code = err["code"] as? String
            let type = err["type"] as? String
            let m = err["message"] as? String
            if let friendly = friendlyProviderError(code: code, type: type, message: m) { return friendly }
            if let m = m, !m.isEmpty { return m }
            if let c = code, !c.isEmpty { return c }
        }
        if let err = json["error"] as? String, !err.isEmpty {
            return friendlyProviderError(code: nil, type: nil, message: err) ?? err
        }
        if let m = json["message"] as? String, !m.isEmpty {
            let code = json["code"] as? String
            if let friendly = friendlyProviderError(code: code, type: nil, message: m) { return friendly }
            if let code = code, !code.isEmpty { return "\(m)（\(code)）" }
            return m
        }
        return nil
    }

    /// 把服务商（百炼 DashScope / 火山 Ark）最常见的两类错误翻成能照着办的中文；认不出的返回 nil、保留原话。
    /// 依据实测原文：百炼 Key 错 → code=invalid_api_key "Incorrect API key provided…"；
    /// 火山 Ark Key 错 → code=AuthenticationError "The API key format is incorrect…"；
    /// 百炼欠费 → code=Arrearage "…account is in good standing"；火山 Ark 欠费 → AccountOverdueError。
    static func friendlyProviderError(code: String?, type: String?, message: String?) -> String? {
        let c = (code ?? "").lowercased()
        let t = (type ?? "").lowercased()
        let m = (message ?? "").lowercased()
        let tag = (code?.isEmpty == false) ? "（\(code!)）" : ""

        if c == "invalid_api_key" || c == "invalidapikey" || c == "authenticationerror" || t == "unauthorized"
            || m.contains("incorrect api key") || m.contains("api key format is incorrect")
            || m.contains("didn't provide an api key") || m.contains("invalid api key")
            || m.contains("authentication fails") {   // DeepSeek 的 401 原文
            return "API Key 无效，请检查是否复制完整\(tag)"
        }
        if c == "arrearage" || c == "accountoverdueerror" || c == "insufficient_quota"
            || m.contains("in good standing") || m.contains("arrearage") || m.contains("overdue")
            || m.contains("quota exceeded") || m.contains("enough balance")
            || m.contains("insufficient balance") || m.contains("run out of balance") {   // DeepSeek 的 402 原文
            return "账号欠费或免费额度已用完，请到服务商控制台检查\(tag)"
        }
        if c == "quotaexceeded" || c == "ratelimitexceeded" || c == "throttling" || c.hasPrefix("throttling.")
            || c == "limit_requests" || m.contains("rate limit") || m.contains("too many requests") {
            return "请求太频繁或额度超限，稍后再试\(tag)"
        }
        return nil
    }
}
