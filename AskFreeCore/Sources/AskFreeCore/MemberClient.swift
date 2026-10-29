import Foundation
import Combine

/// 会员：不登录，按这台电脑领试用（前 100 台各 30 个问题）；订阅或一次买以后这台电脑就是会员，别的电脑输授权码也能用。
/// 后台是 meetcaption-server（docs/multi-product.md §4），这里只管和它说话、记住设备令牌（钥匙串，开发版在 dev_secrets.json）。
/// 识别、问答、联网的计量请求不经过这里：它们拿 credentials() 自己发，返回头交回 apply(_:) 更新剩几次。
@MainActor
public final class MemberClient: ObservableObject {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// 后台的状态：剩几次、是不是会员、到哪天、价格。连不上时留着上次的，不清空
    @Published public private(set) var status: MemberStatus?
    /// 这台电脑注册时领没领到试用：granted / existing / closed / ip-limit / daily-limit
    @Published public private(set) var registration: String?
    /// 最近一次和后台说话出的错（连不上、令牌失效……）；成功一次就清掉
    @Published public private(set) var error: MemberAPIError?
    /// 正在等付款的那次结账：浏览器里付完，这里每 3 秒问一次
    @Published public private(set) var pendingCheckout: PendingCheckout?
    /// 正在问 /status
    @Published public private(set) var isRefreshing = false
    /// 计量接口回的、/status 里看不出来的上限：这张授权今天的成本到了（429 daily-limit）、识别分钟用完了（429 / 402 asr-limit）。
    /// 记到重置那一刻，按键时先看它（usageBlock），免得每按一次都白录一遍、上传一遍
    @Published public private(set) var dailyBlock: MemberAPIError?
    @Published public private(set) var asrBlock: MemberAPIError?

    public struct PendingCheckout: Equatable, Sendable {
        public let claim: String
        public let plan: String
        public let currency: String
        /// sub（自动续费）| pass（一次买）
        public let mode: String
        public let startedAt: Date
    }

    /// 付完款、状态已经是会员：弹一句「付款成功」
    public var onPaid: ((MemberStatus) -> Void)?
    /// 结账过期或放弃了
    public var onCheckoutEnded: (() -> Void)?
    public var log: ((String) -> Void)?

    public static let tokenAccount = "askfree_member_token"

    /// nil = 开发版没设 ASKFREE_API，不连后台
    public let base: URL?
    private let secrets: SecretStoring
    private let fingerprint: () -> String
    private let send: Send
    private let now: () -> Date
    private let version: String
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval
    private var cachedToken: String?
    /// 钥匙串读过一次就记住（没令牌也记住），侧栏每画一次不再去读钥匙串
    private var tokenLoaded = false
    private var registering: Task<String, Error>?
    private var refreshing: Task<Void, Never>?
    private var checkedAt: Date?
    private var pollTask: Task<Void, Never>?

    public init(base: URL?,
                secrets: SecretStoring,
                fingerprint: @escaping () -> String,
                version: String,
                send: @escaping Send = MemberClient.urlSessionSend,
                now: @escaping () -> Date = { Date() },
                pollInterval: TimeInterval = 3,
                pollTimeout: TimeInterval = 30 * 60) {
        self.base = base
        self.secrets = secrets
        self.fingerprint = fingerprint
        self.version = version
        self.send = send
        self.now = now
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    /// 默认的发法：不存 Cookie、不走缓存，每个请求 20 秒超时（§4.0）
    public nonisolated static let urlSessionSend: Send = { request in
        try await session.data(for: request)
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    // MARK: - 设备令牌

    private var token: String? {
        if !tokenLoaded {
            cachedToken = secrets.get(Self.tokenAccount).flatMap { $0.isEmpty ? nil : $0 }
            tokenLoaded = true
        }
        return cachedToken
    }

    private func saveToken(_ value: String?) {
        cachedToken = value
        tokenLoaded = true
        secrets.set(Self.tokenAccount, value)
    }

    /// 注册过没有（有没有存着令牌）
    public var hasDevice: Bool { token != nil }

    /// 第一次用：按这台电脑领试用，存下令牌。之后直接返回存着的。同时来的几次合成一次
    @discardableResult
    public func ensureDevice() async throws -> String {
        if let token { return token }
        if let registering { return try await registering.value }
        let task = Task { () throws -> String in
            let body: [String: Any] = ["device": fingerprint(), "platform": "darwin", "arch": UsagePing.currentArch, "version": version]
            let data = try await request("POST", "/device", body: body, auth: false, retry: false)
            let r = try MemberRegistration.decode(data)
            saveToken(r.token)
            registration = r.trial
            setStatus(r.status)
            log?("Member: registered trial=\(r.trial) left=\(r.status.trial.left)")
            return r.token
        }
        registering = task
        defer { registering = nil }
        return try await task.value
    }

    /// 计量请求用的凭据：没注册就先注册
    public func credentials() async throws -> MemberCredentials {
        guard let base else { throw MemberAPIError.noServer }
        return MemberCredentials(base: base, token: try await ensureDevice())
    }

    /// 计量请求回了 401 bad-device：这个令牌作废，重新注册（同一台电脑拿回原来的账），回新的凭据再试一次
    public func recoverDevice(after used: MemberCredentials) async throws -> MemberCredentials {
        if token == used.token { saveToken(nil) }
        return try await credentials()
    }

    // MARK: - 状态

    /// 问后台最新的状态（退款、别的电脑用掉了、门户里取消了都只有后台知道）。连不上就留着旧的。
    /// maxAge：有数据且上次问过不到这么久就不再问（启动、回到前台、打开会员页时用，别每次切窗口都打后台）
    public func refresh(maxAge: TimeInterval = 0) async {
        if let refreshing { return await refreshing.value }
        if maxAge > 0, status != nil, let checkedAt, now().timeIntervalSince(checkedAt) < maxAge { return }
        guard base != nil else { error = .noServer; return }
        let task = Task {
            isRefreshing = true
            defer { isRefreshing = false }
            do {
                try await ensureDevice()
                let data = try await request("GET", "/status")
                setStatus(try decodeStatus(data))
            } catch let e as MemberAPIError {
                error = e
                log?("Member: refresh failed \(e.code)")
            } catch {
                self.error = MemberAPIError(status: 0, code: "bad-response", message: "会员服务器回的内容看不懂")
            }
            checkedAt = now()
        }
        refreshing = task
        await task.value
        refreshing = nil
    }

    /// 计量接口的返回头：本地先改剩几次
    public func apply(_ headers: MemberUseHeaders) {
        guard var s = status else { return }
        s.apply(headers)
        if s != status { status = s }
    }

    /// 计量接口回了 402 / 429（试用用完、每天上限……）：马上问一次 /status，卡片和会员页跟后台对齐。
    /// 成本上限和识别分钟 /status 里没有：另外记下来，到重置那一刻为止
    public func noteUsageError(_ e: MemberAPIError) {
        if e.code == "daily-limit", e.resetAt != nil { dailyBlock = e }
        if e.code == "asr-limit" { asrBlock = e }
        guard [402, 429].contains(e.status) || e.code == "payment-failed" else { return }
        Task { await refresh() }
    }

    /// 按键时还拦着的那个：今天的用量到上限了（打字、语音都拦），voice 时再看识别分钟。
    /// 过了重置时刻的不算；试用的识别分钟（402，没有重置时刻）成了会员就不算了（会员有自己每天的分钟）
    public func usageBlock(voice: Bool) -> MemberAPIError? {
        let nowMs = now().timeIntervalSince1970 * 1000
        func active(_ e: MemberAPIError?) -> MemberAPIError? {
            guard let e else { return nil }
            if let reset = e.resetAt { return nowMs < reset ? e : nil }
            return status?.isMember == true ? nil : e
        }
        if let e = active(dailyBlock) { return e }
        return voice ? active(asrBlock) : nil
    }

    /// 侧栏状态卡、菜单栏、会员页第一行的一句（带上 /status 里没有的成本上限；没注册的写还没领试用）
    public var summary: MemberSummary.Line {
        MemberSummary.line(status, error: error ?? (base == nil ? .noServer : nil), block: usageBlock(voice: false), registered: hasDevice)
    }

    /// 换了授权（输码、解绑）：上一张授权记下的上限不再算。付完款授权不变：成本上限照旧，试用的识别分钟 usageBlock 自己不算了
    private func clearBlocks() {
        dailyBlock = nil
        asrBlock = nil
    }

    // MARK: - 授权码

    /// 在别的电脑上买的、官网买的：输授权码，这台电脑改用那张授权（大小写、空格、少前缀都认）
    public func activate(code: String) async throws {
        try await ensureDevice()
        let data = try await request("POST", "/license/activate", body: ["code": code])
        setStatus(try decodeStatus(data))
        clearBlocks()
    }

    /// 这台电脑退回自己的试用授权（剩几次就几次）
    public func unbind() async throws {
        try await ensureDevice()
        let data = try await request("POST", "/license/unbind", body: [:])
        setStatus(try decodeStatus(data))
        clearBlocks()
    }

    // MARK: - 买

    /// 开结账：plan month | year，currency cny | usd，mode sub（自动续费）| pass（一次买，只有人民币）。
    /// 回 Stripe 结账页的网址（调用方用浏览器打开），之后每 3 秒问一次付了没有，最多等 30 分钟
    public func checkout(plan: String, currency: String, mode: String) async throws -> URL {
        try await ensureDevice()
        let data = try await request("POST", "/checkout", body: ["plan": plan, "currency": currency, "mode": mode])
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlText = obj["url"] as? String, let url = URL(string: urlText),
              let claim = obj["claim"] as? String else {
            throw MemberAPIError(status: 200, code: "bad-response", message: "会员服务器回的内容看不懂")
        }
        pendingCheckout = PendingCheckout(claim: claim, plan: plan, currency: currency, mode: mode, startedAt: now())
        startPolling(claim)
        log?("Member: checkout plan=\(plan) currency=\(currency) mode=\(mode)")
        return url
    }

    /// 「不等了」：不再问，结账页在浏览器里付了也不要紧，下次刷新状态就会是会员
    public func cancelCheckout() {
        pollTask?.cancel()
        pollTask = nil
        pendingCheckout = nil
    }

    private func startPolling(_ claim: String) {
        pollTask?.cancel()
        let started = now()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                if Task.isCancelled { return }
                if self.now().timeIntervalSince(started) > self.pollTimeout {
                    self.endCheckout(claim)
                    return
                }
                if await self.pollOnce(claim) { return }
            }
        }
    }

    /// 问一次这次结账：付了 → 状态换成会员；过期 → 停；还没付 → 接着等。回 true = 不用再问了
    func pollOnce(_ claim: String) async -> Bool {
        do {
            let data = try await request("GET", "/checkout/\(claim)")
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            switch obj?["status"] as? String {
            case "paid":
                let s = try decodeStatus(data)
                setStatus(s)
                checkedAt = now()
                pendingCheckout = nil
                pollTask = nil
                log?("Member: paid plan=\(s.plan)")
                onPaid?(s)
                return true
            case "expired":
                endCheckout(claim)
                return true
            default:
                return false
            }
        } catch let e as MemberAPIError where e.code == "bad-claim" {
            endCheckout(claim)
            return true
        } catch {
            return false   // 断网一下不算，接着等
        }
    }

    private func endCheckout(_ claim: String) {
        guard pendingCheckout?.claim == claim else { return }
        pendingCheckout = nil
        pollTask = nil
        onCheckoutEnded?()
    }

    /// 「管理订阅」：Stripe 的客户门户（换卡、取消、月付年付互换、看发票），网址几分钟内有效，拿到就开
    public func portal() async throws -> URL {
        try await ensureDevice()
        let data = try await request("POST", "/portal", body: [:])
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["url"] as? String, let url = URL(string: text) else {
            throw MemberAPIError(status: 200, code: "bad-response", message: "会员服务器回的内容看不懂")
        }
        return url
    }

    // MARK: - 发请求

    private func setStatus(_ s: MemberStatus) {
        if status != s { status = s }
        error = nil
    }

    private func decodeStatus(_ data: Data) throws -> MemberStatus {
        do {
            return try JSONDecoder().decode(MemberStatus.self, from: data)
        } catch {
            throw MemberAPIError(status: 200, code: "bad-response", message: "会员服务器回的内容看不懂")
        }
    }

    /// 发一个请求，2xx 回内容；令牌失效（401 bad-device）重新注册再试一次；其余的错按后台给的 code 抛 MemberAPIError
    private func request(_ method: String, _ path: String, body: [String: Any]? = nil,
                         auth: Bool = true, retry: Bool = true) async throws -> Data {
        guard let base else { throw MemberAPIError.noServer }
        var req = URLRequest(url: MemberEndpoint.url(base, path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("AskFree/\(version)", forHTTPHeaderField: "User-Agent")
        let used = auth ? token : nil
        if let used { req.setValue("Bearer \(used)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(req)
        } catch {
            throw MemberAPIError.network(error)
        }
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        if (200..<300).contains(code) { return data }
        let err = MemberAPIError.from(status: code, data: data, response: http)
        if err.isBadDevice, auth, retry {
            // 令牌失效（重装后钥匙串里留着别处的、后台换过库）：重新领一个，同一台电脑拿回原来的账
            if token == used { saveToken(nil) }
            try await ensureDevice()
            return try await request(method, path, body: body, auth: auth, retry: false)
        }
        throw err
    }
}
