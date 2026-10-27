import Foundation

/// 主窗口侧栏的九页，从上到下就是这个顺序（「显示」菜单的 ⌘1 到 ⌘9、侧栏 ↑↓ 都按它走）。
public enum MainPage: String, CaseIterable, Identifiable {
    case start, history, hotkeys, models, answer, recording, permissions, general, about
    public var id: String { rawValue }

    /// 侧栏「设置」小标题下面那七页
    public static let settings: [MainPage] = [.hotkeys, .models, .answer, .recording, .permissions, .general, .about]

    public var title: String {
        switch self {
        case .start: return "开始"
        case .history: return "历史"
        case .hotkeys: return "快捷键"
        case .models: return "语音与模型"
        case .answer: return "回答方式"
        case .recording: return "录音"
        case .permissions: return "权限"
        case .general: return "通用"
        case .about: return "关于"
        }
    }

    public var symbol: String {
        switch self {
        case .start: return "flag"
        case .history: return "clock"
        case .hotkeys: return "keyboard"
        case .models: return "waveform"
        case .answer: return "text.bubble"
        case .recording: return "mic"
        case .permissions: return "lock"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }

    /// 侧栏、页头、「显示」菜单里的名字：第一页在三步都做完后叫「首页」
    public func title(setupDone: Bool) -> String {
        self == .start && setupDone ? "首页" : title
    }

    public func symbol(setupDone: Bool) -> String {
        self == .start && setupDone ? "house" : symbol
    }

    /// 启动参数 -openPage 和菜单栏用的名字
    public init?(argument: String) {
        switch argument.lowercased() {
        case "home", "start": self = .start
        case "model", "models": self = .models
        case "settings", "general": self = .general
        default:
            guard let page = MainPage(rawValue: argument.lowercased()) else { return nil }
            self = page
        }
    }

    /// 侧栏 ↑↓：上一页 / 下一页，到头停住不绕回
    public func stepped(by delta: Int) -> MainPage {
        let pages = Self.allCases
        let i = pages.firstIndex(of: self) ?? 0
        return pages[max(0, min(pages.count - 1, i + delta))]
    }

    /// 「显示」菜单的快捷键：第 1 到第 9 页是 ⌘1 到 ⌘9
    public var menuKeyEquivalent: String {
        let i = Self.allCases.firstIndex(of: self) ?? 0
        return i < 9 ? "\(i + 1)" : ""
    }
}
