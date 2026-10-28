import Foundation

/// 自动更新走到哪一步（App 里的 AppUpdater 按 Sparkle 的回调换这里的值，「通用 → 更新」那一行照它写）。
/// 和 MeetCaption 的 main/updater.js 同一套：后台查、后台下，下好了点「重启更新」才重启；不点也行，退出时装上。
public enum UpdatePhase: Equatable {
    /// 这个包不更新
    case off(UpdateOffReason)
    case idle
    case checking
    /// percent 为 nil：服务器没说多大
    case downloading(version: String, percent: Int?)
    /// 下完了，在解包、验签
    case preparing(version: String)
    case ready(version: String)
    case latest(checkedAt: Date)
    case error(String)

    /// 「检查更新」能不能按
    public var canCheck: Bool {
        switch self {
        case .off, .checking, .downloading, .preparing, .ready: return false
        case .idle, .latest, .error: return true
        }
    }

    public var readyVersion: String? {
        if case .ready(let version) = self { return version }
        return nil
    }

    /// 「通用 → 更新」开关下面那一行
    public func line(currentVersion: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .off(.devBuild): return "开发版不自动更新。"
        case .off(.selfBuilt): return "自己编译的版本（临时签名）不自动更新：到官网下载正式版，就能自动收到新版本。"
        case .idle: return "当前版本 \(currentVersion)"
        case .checking: return "正在检查…"
        case .downloading(let version, let percent):
            return percent.map { "正在下载新版本 \(version)，\($0)%" } ?? "正在下载新版本 \(version)…"
        case .preparing(let version): return "新版本 \(version) 下载好了，正在核对签名…"
        case .ready(let version): return "新版本 \(version) 已下载好，重启就能用。"
        case .latest(let checkedAt):
            return "已是最新版本 \(currentVersion)，\(Self.when(checkedAt, now: now, calendar: calendar))查过"
        case .error(let message): return "更新出错：\(message)"
        }
    }

    /// 「23:50 」/「昨天 23:50 」/「10月25日 23:50 」（后面带空格，好接「查过」）
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let hm = calendar.dateComponents([.hour, .minute], from: date)
        let time = String(format: "%02d:%02d", hm.hour ?? 0, hm.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) { return "今天 \(time) " }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time) "
        }
        let md = calendar.dateComponents([.month, .day], from: date)
        return "\(md.month ?? 0)月\(md.day ?? 0)日 \(time) "
    }

    /// 下载进度：收到的字节 / 服务器说的总大小 → 0...100；总大小不知道或不对时 nil
    public static func percent(received: UInt64, expected: UInt64) -> Int? {
        guard expected > 0 else { return nil }
        return Int(min(100, Double(received) / Double(expected) * 100))
    }
}

/// 哪些包不自动更新
public enum UpdateOffReason: Equatable {
    /// 开发版：feed 是正式版的，装上会把开发版换成正式版
    case devBuild
    /// 自己从源码编的临时签名（ad hoc）包：正式版是 Developer ID 签的，Sparkle 验签时对不上，下了也装不上
    case selfBuilt
}

public enum UpdateLocation {
    /// 放在「应用程序」（/Applications 或 ~/Applications）里才稳妥：从「下载」、dmg 里直接打开的，
    /// 系统会把它挪到只读的临时位置（App Translocation），新版本换不进去
    public static func isInApplications(bundlePath: String, home: String) -> Bool {
        let path = (bundlePath as NSString).standardizingPath
        return [ "/Applications/", (home as NSString).appendingPathComponent("Applications") + "/" ]
            .contains { path.hasPrefix($0) }
    }

    public static let notInApplicationsHint = "Ask Free 不在「应用程序」文件夹里，可能装不上更新：把它拖进「应用程序」后再打开。"
}

/// Sparkle 的报错换成看得懂的话，认不出的原样给
public enum UpdateErrorText {
    /// Sparkle 的 SUSparkleErrorDomain
    public static let sparkleDomain = "SUSparkleErrorDomain"

    /// foundVersion：这一轮已经查到的新版本；nil = 还在取 appcast 时就出错了
    public static func message(for error: NSError, foundVersion: String? = nil) -> String {
        // Sparkle 一层套一层：「取更新信息出错」←「下载出错」←「…not found (404)」或 NSURLError
        let chain = Array(sequence(first: error) { $0.userInfo[NSUnderlyingErrorKey] as? NSError }.prefix(8))
        if chain.contains(where: { $0.domain == NSURLErrorDomain }) {
            return "连不上 GitHub，过一会儿会再查"
        }
        guard error.domain == sparkleDomain else { return error.localizedDescription }
        // 装不上的真正原因常在里层：验签失败时最外层是 4005「安装出错」，里面才是 3002
        let codes = Set(chain.filter { $0.domain == sparkleDomain }.map(\.code))
        if !codes.isDisjoint(with: [3001, 3002, 4009]) {
            // 签名不对：EdDSA 对不上（3001）、更新包验不过（3002）、Developer ID 和装着的这一版不是同一个（4009）
            return "新版本的签名和装着的这一版对不上，没有装"
        }
        if !codes.isDisjoint(with: [1003, 1005]) {
            // 从 dmg 里直接打开（1003），或者没拖进「应用程序」被系统挪到了临时位置（1005）
            return "Ask Free 在只读的位置（比如直接从安装包里打开），装不上新版本：把它拖进「应用程序」后再打开"
        }
        if !codes.isDisjoint(with: [4000, 4012]) {
            return "没有权限替换 Ask Free：把它放进「应用程序」文件夹后再试"
        }
        switch error.code {
        case 2001:
            let status = chain.lazy.compactMap(httpStatus).first
            guard let foundVersion else {
                // GitHub 上最新的那一版没带 appcast.xml（1.1.0 及更早的都没有）
                if status == 404 { return "GitHub 上还没有能自动更新的新版本" }
                return status.map { "取不到更新信息（\($0)），过一会儿再试" } ?? "取不到更新信息，过一会儿再试"
            }
            return status.map { "新版本 \(foundVersion) 的安装包下载不到（\($0)），过一会儿再试" }
                ?? "新版本 \(foundVersion) 的安装包下载不到，过一会儿再试"
        case 1000, 1002:
            return "GitHub 上的更新信息读不了，过一会儿再试"
        default:
            return error.localizedDescription
        }
    }

    /// Sparkle 下载出错时写的「… not found (404)」里那个 HTTP 状态码
    public static func httpStatus(_ error: NSError) -> Int? {
        guard error.domain == sparkleDomain,
              let match = error.localizedDescription.range(of: #"\((\d{3})\)\s*$"#, options: .regularExpression) else { return nil }
        return Int(error.localizedDescription[match].filter(\.isNumber))
    }
}
