import Foundation

/// 匿名使用统计要用户先同意（照 MeetCaption 的 usagePing.js）：三态存在 config.json 的 usage_consent，
/// ""（没问过）| "yes" | "no"，只有 yes 才发，没问过和不同意都不发。
/// 新用户在欢迎引导里问；老用户更新后第一次打开主窗口时问一次；「通用 → 隐私」里的开关随时能改。
public enum UsageConsent: String, Equatable {
    case unasked = ""
    case yes
    case no

    public static let configKey = "usage_consent"

    public static func load(from config: AskFreeConfig = .shared) -> UsageConsent {
        UsageConsent(rawValue: config.string(forKey: configKey) ?? "") ?? .unasked
    }

    /// 点了「同意」/「不用了」，或者在设置里拨了开关
    public static func save(agree: Bool, in config: AskFreeConfig = .shared) {
        config.save(value: agree ? UsageConsent.yes.rawValue : UsageConsent.no.rawValue, forKey: configKey)
    }

    /// 只有明确同意才发
    public var allowsPing: Bool { self == .yes }

    /// 还没回答过：要问一次。点过「同意」或「不用了」就不再问
    public var needsAsking: Bool { self == .unasked }
}

/// 询问、设置里那一行用的字（用户 2026-10-27 定的 MeetCaption 原文，换成 Ask Free 和它会发的内容）。
/// 欢迎引导那一步和主窗口的询问共用一份正文
public enum UsageConsentCopy {
    public static let title = "帮我们知道有多少人在用 Ask Free？"
    /// 凡是统计人数的地方都写明原因（用户偏好「统计写明原因」）
    public static let reason = "我们会给前 100 位用户免费额度，所以需要统计有多少人在用。统计是匿名的。"
    public static let intro = "同意后，Ask Free 每天会发给我们一次："
    public static let items = [
        "一个随机编号：只用来数人数，是第一次发送时随机生成的，跟你的名字、邮箱和电脑硬件都没有关系",
        "是哪个软件（Ask Free）、版本号、系统（macOS）和芯片类型",
        "用会员还是自带 Key，界面是什么语言",
    ]
    public static let never = "不会发你问的话、回答、录音、截图和你的 Key，也不记你的 IP 地址。"
    public static let later = "不同意也能用全部功能。以后随时可以在主窗口「通用 → 匿名使用统计」里改。"
    public static let agree = "同意"
    public static let decline = "不用了"

    public static let settingTitle = "匿名使用统计"
    public static let settingDetail = reason
        + "开着时每天发一次：随机编号、是哪个软件、版本号、系统和芯片、用会员还是自带 Key、界面语言，只用来数每天有多少人在用。"
        + "不发你问的话、录音、截图和 Key；关着什么都不发。"
}

/// 每天匿名报到一次：POST {api}/v1/ping，不带 Authorization，body 只有下面 7 个字段。成功回 2xx（服务器回 204）。
/// 同一个本地日期只报一次：日期和随机编号存在配置目录的 usage-ping.json。
/// 失败（断网、4xx、5xx、10 秒超时）只记日志，这一天不记下，下一次再试。
public actor UsagePing {
    public enum Outcome: String, Equatable {
        /// 没同意
        case off
        /// 今天报过了
        case done
        case sent
        case failed
    }

    public struct Body: Codable, Equatable {
        public let id: String
        public let version: String
        public let platform: String
        public let arch: String
        public let plan: String
        public let lang: String
        public let product: String
    }

    /// 每次报到时现取：版本号、用会员还是自带 Key（member | own）、界面语言
    public struct Info: Equatable {
        public let version: String
        public let plan: String
        public let lang: String

        public init(version: String, plan: String, lang: String) {
            self.version = version
            self.plan = plan
            self.lang = lang
        }
    }

    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let defaultAPI = "https://api.us-cloud.uk"
    public static let product = "askfree"
    public static let timeout: TimeInterval = 10

    /// 这个进程编出来的芯片，写法和 MeetCaption（Node 的 process.arch）一样：arm64 | x64
    public static var currentArch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }

    /// 会员服务器地址：环境变量 ASKFREE_API 能换（测试时指到本机假服务器），末尾的 / 去掉。不是 http(s) 地址返回 nil
    public static func apiBase(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var text = (environment["ASKFREE_API"] ?? defaultAPI).trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    /// 开发版、启动自测不报；设了 ASKFREE_API（指到本机假服务器）的开发版照报，测试用
    public static func shouldRun(isDevBuild: Bool, isSelfTest: Bool,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard !isSelfTest else { return false }
        return !isDevBuild || environment["ASKFREE_API"] != nil
    }

    /// 本地日期 2026-10-28（不用 UTC：东八区早上 8 点前还算前一天）
    public static func localDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 默认的发法：不存 Cookie、不走缓存，整个请求 10 秒超时
    public static let urlSessionSend: Send = { request in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    private let file: URL
    private let endpoint: URL
    private let enabled: @Sendable () -> Bool
    private let info: @Sendable () -> Info
    private let send: Send
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone
    private let log: @Sendable (String) -> Void
    private let arch: String
    private var busy: Task<Outcome, Never>?

    /// file：配置目录里的 usage-ping.json；api：会员服务器地址（apiBase）；enabled：用户同意了没有（UsageConsent.load().allowsPing）
    public init(file: URL, api: URL,
                enabled: @escaping @Sendable () -> Bool,
                info: @escaping @Sendable () -> Info,
                send: @escaping Send = UsagePing.urlSessionSend,
                now: @escaping @Sendable () -> Date = { Date() },
                timeZone: TimeZone = .current,
                arch: String = UsagePing.currentArch,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.file = file
        self.endpoint = api.appendingPathComponent("v1").appendingPathComponent("ping")
        self.enabled = enabled
        self.info = info
        self.send = send
        self.now = now
        self.timeZone = timeZone
        self.arch = arch
        self.log = log
    }

    /// 看一眼：同意了、今天还没报过就报。同时来的几次合成一次
    @discardableResult
    public func tick() async -> Outcome {
        if let busy { return await busy.value }
        let task = Task { await self.run() }
        busy = task
        let outcome = await task.value
        busy = nil
        return outcome
    }

    private struct State: Codable {
        var id: String?
        var day: String?
    }

    private func run() async -> Outcome {
        guard enabled() else { return .off }
        var state = readState()
        let day = Self.localDay(now(), timeZone: timeZone)
        if state.day == day { return .done }
        if state.id.map({ UUID(uuidString: $0) == nil }) ?? true {
            state.id = UUID().uuidString.lowercased()
            writeState(state)
        }
        let current = info()
        let body = Body(id: state.id ?? "", version: current.version, platform: "darwin", arch: arch,
                        plan: current.plan == "member" ? "member" : "own", lang: current.lang, product: Self.product)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AskFree/\(current.version)", forHTTPHeaderField: "User-Agent")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try? encoder.encode(body)
        do {
            let (_, response) = try await send(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                log("Usage ping failed: HTTP \(status)")
                return .failed
            }
        } catch let error as URLError {
            log("Usage ping failed: URLError \(error.code.rawValue)")
            return .failed
        } catch {
            log("Usage ping failed: \(type(of: error))")
            return .failed
        }
        state.day = day
        writeState(state)
        return .sent
    }

    private func readState() -> State {
        guard let data = try? Data(contentsOf: file), let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    private func writeState(_ state: State) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            log("Usage ping: can't write \(file.lastPathComponent): \(type(of: error))")
        }
    }
}
