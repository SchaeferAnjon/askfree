import Foundation

/// 没答成的几种情况：每种一句标题、一句怎么办、一两个按钮（design/panels A2）。回答面板的报错卡照这个画
public enum AskFailure: Equatable {
    case noKey, invalidKey, quota, timeout, offline
    case other(String)

    public enum Action { case openModels, retry }

    /// 回答失败的原因分成几类；认不出的原样写出来
    public init(error: Error) {
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
        case .other: return "exclamationmark.bubble"
        }
    }

    /// 橙 = 还差一步，红 = 出错了
    public var isError: Bool {
        switch self {
        case .noKey, .timeout, .offline: return false
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
        case .other(let reason): return reason
        }
    }

    /// 第一个是黑色主按钮
    public var actions: [(title: String, action: Action)] {
        switch self {
        case .noKey: return [("去填 Key", .openModels), ("填好了，再问一次", .retry)]
        case .invalidKey: return [("去换 Key", .openModels), ("重试", .retry)]
        case .quota: return [("去换一家", .openModels), ("重试", .retry)]
        case .timeout, .offline, .other: return [("再试一次", .retry)]
        }
    }
}
