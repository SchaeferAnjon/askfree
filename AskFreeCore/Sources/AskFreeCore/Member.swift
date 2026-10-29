import Foundation
import CryptoKit
#if canImport(IOKit)
import IOKit
#endif

/// 两种用法（2026-10-28 用户定）：会员（语音识别、问答、联网都经我们的后台，不用填 Key）或自带 Key（永久免费，直接连服务商）。
/// 存在 config.json 的 usage_mode。没选过的新用户默认会员；更新上来、已经填了自己 Key 的老用户启动时记成自带 Key（migrate）。
public enum UsageMode: String, Equatable, Sendable {
    case member
    case own

    public static let configKey = "usage_mode"

    public static func current(config: AskFreeConfig = .shared) -> UsageMode {
        UsageMode(rawValue: config.string(forKey: configKey) ?? "") ?? .member
    }

    /// 用户明确选过没有（欢迎引导「用法」那一步、会员页、收费页里选的）
    public static func isChosen(config: AskFreeConfig = .shared) -> Bool {
        UsageMode(rawValue: config.string(forKey: configKey) ?? "") != nil
    }

    public static func save(_ mode: UsageMode, config: AskFreeConfig = .shared) {
        config.save(value: mode.rawValue, forKey: configKey)
    }

    /// 启动时调一次：没选过用法、但已经填了自己的 Key（更新上来的老用户）记成自带 Key，照旧直连服务商，不会突然改走会员
    public static func migrate(config: AskFreeConfig = .shared) {
        guard !isChosen(config: config), hasOwnKeys(config: config) else { return }
        save(.own, config: config)
    }

    /// 填过任何一家的 Key
    public static func hasOwnKeys(config: AskFreeConfig = .shared) -> Bool {
        ["bigasr_api_key", "bigasr_access_token", "dashscope_api_key", "deepseek_api_key", "zhipu_api_key", "ark_api_key"]
            .contains { config.string(forKey: $0)?.isEmpty == false }
    }
}

/// 会员后台的地址和接口路径（docs：meetcaption-server/docs/multi-product.md §4）
public enum MemberEndpoint {
    public static let product = "askfree"

    /// 后台地址：和匿名统计同一个（ASKFREE_API 能换，测试时指到本机）。
    /// 开发版没设 ASKFREE_API 就是 nil：开发版不连线上后台注册设备，免得占掉线上前 100 份免费名额。
    /// 启动自测（CI 在正式包上跑，每次一台新虚拟机）一律不连
    public static func base(environment: [String: String] = ProcessInfo.processInfo.environment,
                            isDevBuild: Bool = AppIdentity.isDevBuild,
                            isSelfTest: Bool = AppIdentity.isSelfTest) -> URL? {
        if isSelfTest { return nil }
        if isDevBuild && environment["ASKFREE_API"] == nil { return nil }
        return UsagePing.apiBase(environment: environment)
    }

    public static let current: URL? = base()

    /// base + /v1/askfree + path
    public static func url(_ base: URL, _ path: String) -> URL {
        URL(string: base.absoluteString + "/v1/\(product)" + path) ?? base
    }

    public static let chatPath = "/chat/completions"
    public static let searchPath = "/search"
    public static let asrPath = "/asr"
    /// 会员模式下回答用的模型：后台定死 deepseek-flash，关思考
    public static let model = "deepseek-flash"
}

/// 计量请求（识别、问答、联网）要的凭据：后台地址和这台电脑的设备令牌。值类型，可以带到后台线程
public struct MemberCredentials: Equatable, Sendable {
    public let base: URL
    public let token: String

    public init(base: URL, token: String) {
        self.base = base
        self.token = token
    }

    /// 计量请求的请求头：令牌和这一问的用量号（同一个问题下的识别、问答、联网、重试只算一次）
    public func headers(useId: String) -> [String: String] {
        ["Authorization": "Bearer \(token)", "X-Use-Id": useId]
    }
}

/// 一个问题一个用量号（UUID 小写）：追问、新问题换新号，「重试」用原来的号
public enum MemberUse {
    public static func newId() -> String { UUID().uuidString.lowercased() }

    /// 后台的重试窗口 15 分钟，从这个号第一次出现算（重试不往后挪）；留 1 分钟余量，钟差一点也不撞上 409 use-expired
    public static let retryWindow: TimeInterval = 14 * 60

    /// 「再试一次」用哪个号：没过窗口用原来的（开始的时刻不变），过了窗口或没有就换新号（会再算一次）
    public static func forRetry(_ last: MemberUseRef?, now: Date = Date()) -> MemberUseRef {
        if let last, now.timeIntervalSince(last.startedAt) < retryWindow { return last }
        return MemberUseRef(startedAt: now)
    }
}

/// 一个问题的用量号和它开出来的时刻（语音提问是松开键那一刻，打字提问是发出那一刻）
public struct MemberUseRef: Equatable, Sendable {
    public let id: String
    public let startedAt: Date

    public init(id: String = MemberUse.newId(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
    }
}

/// 计量接口的返回头：X-Use-Charged / X-Uses-Kind / X-Uses-Left / X-Uses-Reset
public struct MemberUseHeaders: Equatable, Sendable {
    public let charged: Bool
    /// trial | sub
    public let kind: String
    public let left: Int
    /// 下一个 UTC 0 点（毫秒），会员才有
    public let reset: Double?

    public init(charged: Bool, kind: String, left: Int, reset: Double?) {
        self.charged = charged
        self.kind = kind
        self.left = left
        self.reset = reset
    }

    public init?(_ response: HTTPURLResponse) {
        guard let kind = response.value(forHTTPHeaderField: "X-Uses-Kind"),
              let left = response.value(forHTTPHeaderField: "X-Uses-Left").flatMap({ Int($0) }) else { return nil }
        self.init(charged: response.value(forHTTPHeaderField: "X-Use-Charged") == "1", kind: kind, left: left,
                  reset: response.value(forHTTPHeaderField: "X-Uses-Reset").flatMap { Double($0) })
    }
}

/// 后台回的错：{"error": {"code": "…", "message": "给用户看的一句中文", "resetAt": …}}。status 0 = 没连上
public struct MemberAPIError: LocalizedError, Equatable, Sendable {
    public let status: Int
    public let code: String
    public let message: String
    /// 每天的额度、识别分钟用完时的重置时刻（毫秒）
    public var resetAt: Double?
    /// 429 的 Retry-After（秒）
    public var retryAfter: Int?

    public init(status: Int, code: String, message: String, resetAt: Double? = nil, retryAfter: Int? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.resetAt = resetAt
        self.retryAfter = retryAfter
    }

    public var errorDescription: String? { message }

    /// 从后台的错误响应读出来；读不出 code 的按 HTTP 状态给一句
    public static func from(status: Int, data: Data?, response: HTTPURLResponse? = nil) -> MemberAPIError {
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let err = json?["error"] as? [String: Any]
        let code = (err?["code"] as? String) ?? "http-\(status)"
        let message = (err?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "会员服务出错了（HTTP \(status)），稍后再试"
        let resetAt = (err?["resetAt"] as? NSNumber)?.doubleValue
        let retryAfter = response?.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
        return MemberAPIError(status: status, code: code, message: message, resetAt: resetAt, retryAfter: retryAfter)
    }

    /// 连不上后台（断网、超时、后台没开）
    public static func network(_ error: Error) -> MemberAPIError {
        let timedOut = (error as? URLError)?.code == .timedOut
        return MemberAPIError(status: 0, code: timedOut ? "timeout" : "network",
                              message: timedOut ? "会员服务器没有回应，稍后再试" : "连不上会员服务器，检查一下网络")
    }

    /// 开发版没设 ASKFREE_API（MemberEndpoint.base 是 nil）
    public static let noServer = MemberAPIError(status: 0, code: "no-server",
                                                message: "开发版没有设 ASKFREE_API，不连会员后台（免得占掉线上的免费名额）")

    /// 设备令牌失效：重新注册再试一次
    public var isBadDevice: Bool { status == 401 && code == "bad-device" }
}

/// GET /v1/askfree/status 的内容（§4.2）。注册、激活、解绑、付完款回的也是它
public struct MemberStatus: Decodable, Equatable, Sendable {
    public struct Trial: Decodable, Equatable, Sendable {
        public var granted: Bool
        public var total: Int
        public var used: Int
        public var left: Int
    }

    public struct Subscription: Decodable, Equatable, Sendable {
        public var status: String
        public var plan: String?
        public var currency: String?
        public var amount: Int?
        public var periodEnd: Double?
        public var cancelAtPeriodEnd: Bool?
        public var accessUntil: Double?
    }

    public struct Pass: Decodable, Equatable, Sendable {
        public var plan: String?
        public var currency: String?
        public var amount: Int?
        public var status: String?
        public var startAt: Double?
        public var until: Double?
    }

    public struct Today: Decodable, Equatable, Sendable {
        public var limit: Int
        public var used: Int
        public var left: Int
        public var resetAt: Double
    }

    /// 金额是最小单位（分、美分）
    public struct Price: Decodable, Equatable, Sendable {
        public var cny: Int?
        public var usd: Int?
    }

    public struct Prices: Decodable, Equatable, Sendable {
        public var month: Price?
        public var year: Price?

        public func amount(plan: String, currency: String) -> Int? {
            let price = plan == "year" ? year : month
            return currency == "usd" ? price?.usd : price?.cny
        }
    }

    /// trial（还有试用）| member（订阅或一次买在用）| none
    public var plan: String
    /// 授权码 AF-XXXX-XXXX-XXXX；只有试用的没有
    public var code: String?
    public var devices: Int
    public var maxDevices: Int
    /// 这台电脑用的是自己的试用授权（没输过别的码）
    public var trialOnly: Bool
    public var trial: Trial
    public var subscription: Subscription?
    public var pass: Pass?
    public var memberUntil: Double?
    public var autoRenew: Bool
    public var expiring: Bool
    public var today: Today?
    public var canUse: Bool
    /// canUse 为 false 时：trial-used-up / trial-closed / sub-ended / payment-failed / daily-limit
    public var reason: String?
    public var prices: Prices?
    public var passPrices: Prices?
    public var now: Double?

    public var isMember: Bool { plan == "member" }

    /// 收费页上开自动续费，后台一定会拒的几种情况（meetcaption-server billing.checkout）：照它换成走得通的那条路
    public enum SubscribeBlock: Equatable, Sendable {
        /// 自动续费中：改周期、取消都在「管理订阅」
        case autoRenew
        /// 续费没扣成（past_due，Stripe 还在重试）：后台回 409，在「管理订阅」换卡
        case paymentFailed
        /// 订阅点了到期取消、还没到期：后台回 409 already-subscribed，在「管理订阅」点续订
        case renewInPortal(until: Double)
        /// 一次买的会员离到期还超过 3 天：后台回 409 pass-active，到期前 3 天才能开
        case passActive(until: Double)
    }

    public func subscribeBlock(now: Date = Date()) -> SubscribeBlock? {
        if autoRenew { return .autoRenew }
        if let sub = subscription {
            if sub.status == "past_due" { return .paymentFailed }
            if let until = sub.accessUntil, until > now.timeIntervalSince1970 * 1000 { return .renewInPortal(until: until) }
        }
        // expiring = 会员、不自动续费、离到期不到 3 天：和后台放开订阅的那一刻是同一个判断
        if isMember, pass != nil, !expiring, let until = memberUntil { return .passActive(until: until) }
        return nil
    }

    /// 计量接口的返回头到了：本地先把剩几次改掉（会员是今天剩几次，试用是试用剩几次），不用再问一次 /status
    public mutating func apply(_ headers: MemberUseHeaders) {
        if headers.kind == "sub", var today {
            today.left = headers.left
            today.used = max(0, today.limit - headers.left)
            if let reset = headers.reset { today.resetAt = reset }
            self.today = today
            if headers.left <= 0 { canUse = false; reason = "daily-limit" }
        } else if headers.kind == "trial" {
            trial.left = headers.left
            trial.used = max(0, trial.total - headers.left)
            if headers.left <= 0 && !isMember { canUse = false; reason = "trial-used-up"; plan = "none" }
        }
    }
}

/// 注册设备的返回：令牌、这次注册领没领到试用，其余同 /status（次数明细在 trialUses，和注册结果的 trial 字段撞名）
public struct MemberRegistration: Equatable, Sendable {
    public let token: String
    /// granted（送了 30 次）| existing（这台以前注册过）| closed（名额发完）| ip-limit | daily-limit
    public let trial: String
    public let status: MemberStatus

    public static func decode(_ data: Data) throws -> MemberRegistration {
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["token"] as? String, !token.isEmpty else {
            throw MemberAPIError(status: 200, code: "bad-response", message: "会员服务器回的内容看不懂")
        }
        let trial = obj["trial"] as? String ?? ""
        obj["trial"] = obj["trialUses"]
        let status = try JSONDecoder().decode(MemberStatus.self, from: JSONSerialization.data(withJSONObject: obj))
        return MemberRegistration(token: token, trial: trial, status: status)
    }
}

/// 这台电脑的设备标识：sha256("askfree:" + IOPlatformUUID) 的十六进制（§4.1）；拿不到硬件编号就用本机存的随机值
public enum MemberFingerprint {
    public static func hash(hardwareID: String, product: String = MemberEndpoint.product) -> String {
        SHA256.hash(data: Data("\(product):\(hardwareID)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func hardwareUUID() -> String? {
        #if canImport(IOKit)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? String).flatMap { $0.isEmpty ? nil : $0 }
        #else
        return nil
        #endif
    }

    /// 随机值存在配置里（member_fallback_device），重装前后同一台电脑拿到同一个
    public static func current(config: AskFreeConfig = .shared) -> String {
        if let hw = hardwareUUID() { return hash(hardwareID: hw) }
        let key = "member_fallback_device"
        if let saved = config.string(forKey: key), saved.count == 64 { return saved }
        let random = hash(hardwareID: UUID().uuidString + "\(Date().timeIntervalSince1970)")
        config.save(value: random, forKey: key)
        return random
    }
}

/// 钱和日子怎么写
public enum MemberFormat {
    /// 990 → ¥9.9，9900 → ¥99，199 → $1.99，1990 → $19.9
    public static func money(_ minor: Int, currency: String) -> String {
        let value = Double(minor) / 100
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return (currency == "usd" ? "$" : "¥") + text
    }

    /// 毫秒 → 「11 月 27 日」（本地时区）
    public static func day(_ ms: Double, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: ms / 1000))
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }

    /// 毫秒 → 「08:00」（本地时区）
    public static func time(_ ms: Double, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: ms / 1000))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 每天的额度什么时候重置：后台按 UTC 0 点（北京时间早上 8 点）。不在东八区的人另写一句本地几点
    public static func resetLine(_ resetAt: Double?, timeZone: TimeZone = .current) -> String {
        let beijing = "北京时间早上 8 点"
        guard let resetAt else { return beijing }
        let offset = timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: resetAt / 1000))
        if offset == 8 * 3600 { return beijing }
        return "\(beijing)（你这里是 \(time(resetAt, timeZone: timeZone))）"
    }
}
