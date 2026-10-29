import Foundation

/// 没答成的几种情况：每种一句标题、一句怎么办、一两个按钮（design/panels A2）。回答面板的报错卡照这个画
public enum AskFailure: Equatable {
    case noKey, invalidKey, quota, timeout, offline
    /// 会员模式下后台回的错（试用用完、每天上限、欠费……），按错误码说白话（docs/multi-product.md §4.0）
    case member(MemberProblem)
    case other(String)

    public enum Action: Equatable, Sendable {
        case openModels, retry
        /// 打开会员页的收费页（订阅、续买）
        case openMembership
        /// 打开 Stripe 客户门户换卡
        case openPortal
        /// 改打字问（语音识别的分钟用完了）
        case typeInstead
        /// 换成自带 Key（永久免费）并打开「语音与模型」页：试用用完、没领到试用、会员到期时的另一条出路（§4.0）
        case useOwnKeys
    }

    /// 回答失败的原因分成几类；认不出的原样写出来
    public init(error: Error) {
        if let member = error as? MemberAPIError { self = .member(MemberProblem(member)); return }
        if case AskAI.AskError.noAPIKey = error { self = .noKey; return }
        if case AskAI.AskError.quotaExhausted = error { self = .quota; return }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: self = .timeout; return
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                self = .offline; return
            default: break
            }
        }
        // URLError 不算 LocalizedError：直接 "\(error)" 会把「Error Domain=NSURLErrorDomain Code=-1200 … UserInfo={…}」整段写上卡片
        let reason = (error as? LocalizedError)?.errorDescription
            ?? (error as? URLError)?.localizedDescription
            ?? "\(error)"
        // 这两句开头是 AskAI.friendlyProviderError 翻好的人话
        if reason.hasPrefix("API Key 无效") { self = .invalidKey; return }
        if reason.hasPrefix("账号欠费") { self = .quota; return }
        self = .other(reason)
    }

    public var symbol: String {
        switch self {
        case .noKey, .invalidKey: return "key"
        case .quota: return "creditcard"
        case .timeout: return "clock"
        case .offline: return "wifi.slash"
        case .member(let p): return p.symbol
        case .other: return "exclamationmark.bubble"
        }
    }

    /// 橙 = 还差一步，红 = 出错了
    public var isError: Bool {
        switch self {
        case .noKey, .timeout, .offline: return false
        case .member(let p): return p.isError
        case .invalidKey, .quota, .other: return true
        }
    }

    public func title(provider: String) -> String {
        switch self {
        case .noKey: return "还没填问答模型的 Key"
        case .invalidKey: return "\(provider) 不认这个 Key"
        case .quota: return "\(provider) 的额度用完了"
        case .timeout: return "\(provider) 没有回应"
        case .offline: return "连不上网络"
        case .member(let p): return p.title
        case .other: return "没答成"
        }
    }

    public func detail(provider: String) -> String {
        switch self {
        case .noKey: return "回答要用你自己的 AI Key。在「语音与模型」页填好 DeepSeek 或千问的 Key，就能接着问这一句。"
        case .invalidKey: return "可能复制少了几位，或者在官网删掉了。到「语音与模型」页重新粘贴，点「验证」试一下。"
        case .quota: return "账号欠费或免费额度用完了。到服务商控制台看看，或者在「语音与模型」页换一家。"
        case .timeout: return "可能是网络不稳，也可能是它正忙。"
        case .offline: return "检查一下网络，连上后再问一次。"
        case .member(let p): return p.detail
        case .other(let reason): return reason
        }
    }

    /// 第一个是黑色主按钮
    public var actions: [(title: String, action: Action)] {
        switch self {
        case .noKey: return [("去填 Key", .openModels), ("填好了，再问一次", .retry)]
        case .invalidKey: return [("去换 Key", .openModels), ("重试", .retry)]
        case .quota: return [("去换一家", .openModels), ("重试", .retry)]
        case .member(let p): return p.actions.map { ($0.title, $0.action) }
        case .timeout, .offline, .other: return [("再试一次", .retry)]
        }
    }

    /// 语音没识别出来就失败了（没有问题可以重问）：去掉「再试一次」
    public var withoutRetry: AskFailure {
        if case .member(let p) = self { return .member(p.withoutRetry) }
        return self
    }

    /// 是不是会员模式下后台说的错
    public var memberCode: String? {
        if case .member(let p) = self { return p.code }
        return nil
    }
}

/// 会员模式下后台回的一种错，翻成报错卡上的一句标题、一句怎么办和按钮。
/// 用不了会员的三种（试用用完、没领到试用、到期）照后台规格 §4.0 给两条出路：订阅，或改用自带 Key（永久免费）；
/// 其余的出路是换卡、改打字、等明天或再试一次，不提 Key
public struct MemberProblem: Equatable, Sendable {
    public struct Button: Equatable, Sendable {
        public let title: String
        public let action: AskFailure.Action
    }

    public let code: String
    public let title: String
    public let detail: String
    public let actions: [Button]
    public let isError: Bool
    public let symbol: String

    public init(code: String, title: String, detail: String, actions: [Button], isError: Bool, symbol: String) {
        self.code = code
        self.title = title
        self.detail = detail
        self.actions = actions
        self.isError = isError
        self.symbol = symbol
    }

    public var withoutRetry: MemberProblem {
        MemberProblem(code: code, title: title, detail: detail, actions: actions.filter { $0.action != .retry },
                      isError: isError, symbol: symbol)
    }

    public init(_ e: MemberAPIError, timeZone: TimeZone = .current) {
        let subscribe = Button(title: "订阅会员", action: .openMembership)
        let ownKeys = Button(title: "改用自带 Key", action: .useOwnKeys)
        let retry = Button(title: "再试一次", action: .retry)
        let typeInstead = Button(title: "打字问", action: .typeInstead)
        let orOwnKeys = "也可以改用自带 Key，永久免费。"
        /// 后台的话里写了「北京时间早上 8 点」；不在东八区的人另补一句本地几点
        let localReset: String = {
            guard let at = e.resetAt else { return "" }
            let line = MemberFormat.resetLine(at, timeZone: timeZone)
            return line.contains("你这里") ? "（你这里是 \(MemberFormat.time(at, timeZone: timeZone))）" : ""
        }()
        switch e.code {
        case "trial-used-up":
            self.init(code: e.code, title: "免费试用用完了", detail: "订阅会员就能接着问：每天 200 个问题，每月 ¥9.9 或每年 ¥99。" + orOwnKeys,
                      actions: [subscribe, ownKeys], isError: false, symbol: "gift")
        case "trial-closed":
            // 后台对「名额发完」和「同一网段 / 当天领的太多、没发」都回这个码，分不出是哪种：照实说没领到
            self.init(code: e.code, title: "这台电脑没有领到免费试用",
                      detail: "免费试用只发前 100 份，同一个网络里领得多了也会发不到。订阅会员就能问：每天 200 个问题，每月 ¥9.9 或每年 ¥99。" + orOwnKeys,
                      actions: [subscribe, ownKeys], isError: false, symbol: "gift")
        case "sub-ended":
            self.init(code: e.code, title: "会员到期了", detail: "续订或再买一段，就能接着问。" + orOwnKeys,
                      actions: [Button(title: "续订", action: .openMembership), ownKeys], isError: false, symbol: "calendar")
        case "payment-failed":
            self.init(code: e.code, title: "续费没扣成", detail: "打开「管理订阅」换一张卡，换好就能接着问。",
                      actions: [Button(title: "管理订阅", action: .openPortal)], isError: true, symbol: "creditcard")
        case "daily-limit":
            self.init(code: e.code, title: "今天的额度用完了", detail: e.message + localReset,
                      actions: [], isError: false, symbol: "calendar")
        case "asr-limit":
            let trial = e.status == 402
            self.init(code: e.code, title: trial ? "试用的语音识别用完了" : "今天的语音识别用完了",
                      detail: e.message + localReset,
                      actions: trial ? [typeInstead, subscribe] : [typeInstead], isError: false, symbol: "waveform")
        case "use-limit":
            self.init(code: e.code, title: "这个问题问到上限了",
                      detail: "一个问题里联网、看屏幕和重试的次数有限。换个问法重新问一次。",
                      actions: [], isError: false, symbol: "exclamationmark.bubble")
        case "use-expired":
            self.init(code: e.code, title: "这一问过了重试的时间", detail: "超过 15 分钟了，重新问一次（算一个新问题）。",
                      actions: [Button(title: "重新问", action: .retry)], isError: false, symbol: "clock")
        case "rate", "too-fast":
            // 后台限的是每分钟 60 个请求；Retry-After 写了要等多久就照写
            let wait = e.retryAfter.map { $0 >= 60 ? "稍等 \(($0 + 59) / 60) 分钟再问。" : "稍等 \(max(1, $0)) 秒再问。" } ?? "稍等几秒再问。"
            self.init(code: e.code, title: "问得太快了", detail: wait, actions: [retry], isError: false, symbol: "clock")
        case "bad-request", "bad-json", "bad-use-id", "bad-audio":
            // 后台把 DeepSeek 400 的原文放在 message 里（英文 JSON）：卡片上说白话，原文只进日志
            self.init(code: e.code, title: "这一问发不出去", detail: "换个问法，或者开一个新话题再问。",
                      actions: [], isError: true, symbol: "exclamationmark.bubble")
        case "busy":
            self.init(code: e.code, title: "会员 AI 今天太忙了", detail: "稍后再试。", actions: [retry], isError: false, symbol: "clock")
        case "upstream":
            self.init(code: e.code, title: "会员服务暂时不可用", detail: e.message.isEmpty ? "稍后再试。" : e.message,
                      actions: [retry], isError: true, symbol: "exclamationmark.bubble")
        case "asr-failed":
            self.init(code: e.code, title: "语音没识别成", detail: e.message, actions: [retry], isError: true, symbol: "waveform")
        case "too-large", "audio-too-long":
            self.init(code: e.code, title: "录音太长了", detail: "一次最长录 10 分钟，说短一点再问。",
                      actions: [], isError: false, symbol: "waveform")
        case "not-ready":
            self.init(code: e.code, title: "会员服务还没开通", detail: e.message, actions: [], isError: false, symbol: "clock")
        case "network":
            self.init(code: e.code, title: "连不上会员服务器", detail: "检查一下网络，连上后再问一次。",
                      actions: [retry], isError: false, symbol: "wifi.slash")
        case "timeout":
            self.init(code: e.code, title: "会员服务器没有回应", detail: "可能是网络不稳，稍后再问一次。",
                      actions: [retry], isError: false, symbol: "clock")
        case "bad-device":
            self.init(code: e.code, title: "这台电脑的会员凭据失效了", detail: "重新打开 Ask Free 再问一次。",
                      actions: [retry], isError: true, symbol: "exclamationmark.bubble")
        case "no-server":
            self.init(code: e.code, title: "开发版没连会员后台", detail: e.message, actions: [], isError: false, symbol: "exclamationmark.bubble")
        default:
            self.init(code: e.code, title: "没答成", detail: e.message, actions: [retry], isError: true, symbol: "exclamationmark.bubble")
        }
    }
}

/// 侧栏状态卡、菜单栏、会员页顶上的一句：现在剩几次、是不是会员、有没有要处理的事
public enum MemberSummary {
    public struct Line: Equatable {
        public let title: String
        public let detail: String
        /// 要用户处理（用完了、到期、欠费）：橙点
        public let warn: Bool
    }

    /// block：计量接口回过的今天的上限（成本到了，/status 里看不出来）。registered：这台电脑注册过没有
    public static func line(_ s: MemberStatus?, error: MemberAPIError? = nil, block: MemberAPIError? = nil, registered: Bool = true,
                            timeZone: TimeZone = .current) -> Line {
        guard let s else {
            if let error { return Line(title: "会员", detail: error.code == "no-server" ? "开发版没连会员后台" : "连不上会员服务器", warn: true) }
            // 启动时不替没注册的电脑领试用（免得白占前 100 份名额）：第一次提问或打开会员页时才领
            if !registered { return Line(title: "会员", detail: "还没领免费试用", warn: false) }
            return Line(title: "会员", detail: "正在连接会员服务器…", warn: false)
        }
        if block?.code == "daily-limit" {
            return Line(title: s.isMember ? "会员" : "免费试用", detail: "今天的用量到上限了", warn: true)
        }
        if s.isMember {
            if let today = s.today, today.left <= 0 {
                return Line(title: "会员", detail: "今天的 \(today.limit) 个问题用完了", warn: true)
            }
            if s.expiring, let until = s.memberUntil {
                return Line(title: "会员", detail: "\(MemberFormat.day(until, timeZone: timeZone)) 到期，记得续买", warn: true)
            }
            if let today = s.today { return Line(title: "会员", detail: "今天还能问 \(today.left) 个", warn: false) }
            return Line(title: "会员", detail: "可以问", warn: false)
        }
        if s.plan == "trial" { return Line(title: "免费试用", detail: "还剩 \(s.trial.left) 个问题", warn: false) }
        switch s.reason {
        case "trial-closed": return Line(title: "会员", detail: "没有领到免费试用", warn: true)
        case "sub-ended": return Line(title: "会员", detail: "已经到期了", warn: true)
        case "payment-failed": return Line(title: "会员", detail: "续费没扣成，要换卡", warn: true)
        default: return Line(title: "免费试用", detail: "\(s.trial.total) 个问题用完了", warn: true)
        }
    }

    /// 注册时的结果说给人听（欢迎引导「用法」那一步）
    public static func registration(_ trial: String?, status: MemberStatus?) -> String? {
        switch trial {
        case "granted": return "领到了 \(status?.trial.total ?? 30) 个问题的免费试用，不用填任何 Key。"
        case "existing":
            guard let status else { return nil }
            if status.isMember { return "这台电脑已经是会员了。" }
            return status.trial.left > 0 ? "这台电脑以前领过试用，还剩 \(status.trial.left) 个问题。" : "这台电脑以前领过试用，已经用完了。"
        case "closed": return "前 100 位新用户的免费名额已经发完了。可以订阅会员，或者改用自带 Key（永久免费）。"
        case "ip-limit": return "这台电脑没有领到免费试用：同一个网络里领过的电脑太多了。可以订阅会员，或者改用自带 Key（永久免费）。"
        case "daily-limit": return "这台电脑没有领到免费试用：领的人太多了。可以订阅会员，或者改用自带 Key（永久免费）。"
        default: return nil
        }
    }
}
