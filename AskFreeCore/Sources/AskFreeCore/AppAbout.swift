import Foundation

/// App 能交给系统打开的外部地址：只放行 https 网页，和一个不带参数的 mailto 邮箱地址（「关于」页的发邮件）。
/// 回答里模型写出的链接、DuckDuckGo 返回的图片地址都要先过这一关：别的协议（file、自定义 URL scheme 等）
/// 点一下就可能拉起任意程序。和 MeetCaption 的 src/main/externalUrl.js 同一条规则。
public enum ExternalLink {
    /// 放行就返回 URL，不放行返回 nil
    public static func allowedURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return isAllowed(url) ? url : nil
    }

    public static func isAllowed(_ url: URL) -> Bool {
        let text = url.absoluteString
        switch url.scheme?.lowercased() {
        case "https":
            guard let host = url.host, !host.isEmpty else { return false }
            return text.range(of: #"^https://\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil
        case "mailto":
            return text.range(of: #"^mailto:[^\s@?&#/]+@[^\s@?&#/]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
        default:
            return false
        }
    }
}

/// 「关于」页的版本那一行和「复制版本信息」复制出去的文字
public struct AppVersionInfo: Equatable {
    public enum Chip: Equatable {
        case appleSilicon, intel
        public var label: String { self == .appleSilicon ? "Apple 芯片版" : "Intel 版" }
    }

    public let version: String
    public let build: String
    public let chip: Chip
    /// 「15.6.1」
    public let macOSVersion: String

    public init(version: String, build: String, chip: Chip, macOSVersion: String) {
        self.version = version
        self.build = build
        self.chip = chip
        self.macOSVersion = macOSVersion
    }

    /// 这个进程编出来的芯片
    public static var currentChip: Chip {
        #if arch(arm64)
        return .appleSilicon
        #else
        return .intel
        #endif
    }

    /// OperatingSystemVersion → 「15.6」/「15.6.1」（补丁号是 0 不写）
    public static func macOSString(_ v: OperatingSystemVersion) -> String {
        v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 「版本 1.1.0（3）· Apple 芯片版」；构建号缺了就不写括号
    public var displayLine: String {
        // 全角括号后面本身带空白，不再加空格
        let number = build.isEmpty || build == version ? "\(version) " : "\(version)（\(build)）"
        return "版本 \(number)· \(chip.label)"
    }

    /// 写信报问题时贴给开发者的几行
    public var copyText: String {
        [
            "Ask Free \(version)",
            "构建号：\(build.isEmpty ? "未知" : build)",
            "芯片：\(chip.label)",
            "macOS：\(macOSVersion)",
        ].joined(separator: "\n")
    }
}
