import Foundation

/// 用 Ask Free 之前要做的三件事，按配置顺序排：先授权、再填 Key、再选提问键（欢迎引导和主窗口「开始」都是这个顺序）
public enum SetupItem: CaseIterable {
    case permissions, keys, hotkey

    public var shortTitle: String {
        switch self {
        case .permissions: return "允许权限"
        case .keys: return "填 Key"
        case .hotkey: return "选提问键"
        }
    }
}

/// 「还差什么」的判断，只有这一套：欢迎引导、「开始」三步、侧栏橙点和状态卡、菜单栏第一行都从这里读。
/// App 里的 SetupStatus 负责读系统权限和配置，读到的值交给这里算。
public struct SetupChecklist: Equatable {
    public var micAuthorized: Bool
    public var accessibility: Bool
    public var screenRecording: Bool
    /// 关了「让 AI 看屏幕」就用不到屏幕录制，不拿它算还差几步
    public var screenshotEnabled: Bool
    public var asrReady: Bool
    public var askReady: Bool
    public var screenHotkeySet: Bool

    public init(micAuthorized: Bool = false, accessibility: Bool = false, screenRecording: Bool = false,
                screenshotEnabled: Bool = true, asrReady: Bool = false, askReady: Bool = false,
                screenHotkeySet: Bool = false) {
        self.micAuthorized = micAuthorized
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.screenshotEnabled = screenshotEnabled
        self.asrReady = asrReady
        self.askReady = askReady
        self.screenHotkeySet = screenHotkeySet
    }

    private var screenRecordingOK: Bool { screenRecording || !screenshotEnabled }

    public var keysReady: Bool { asrReady && askReady }
    public var permissionsReady: Bool { micAuthorized && accessibility && screenRecordingOK }
    /// 三项权限里还差几项（关了看屏幕时只算两项）
    public var missingPermissions: Int {
        [micAuthorized, accessibility, screenRecordingOK].filter { !$0 }.count
    }

    public func isDone(_ item: SetupItem) -> Bool {
        switch item {
        case .permissions: return permissionsReady
        case .keys: return keysReady
        case .hotkey: return screenHotkeySet
        }
    }

    /// 还没做的，按配置顺序
    public var missing: [SetupItem] { SetupItem.allCases.filter { !isDone($0) } }
    public var allDone: Bool { missing.isEmpty }
    /// 「开始」页当前那一步（全页唯一的黑按钮）：第一件没做完的
    public var current: SetupItem? { missing.first }

    /// 侧栏哪几页挂橙点
    public func needsAttention(_ page: MainPage) -> Bool {
        switch page {
        case .start: return !allDone
        case .hotkeys: return !screenHotkeySet
        case .models: return !keysReady
        case .permissions: return !permissionsReady
        default: return false
        }
    }

    /// 侧栏状态卡的第一行
    public var statusTitle: String { allDone ? "一切就绪" : "还差 \(missing.count) 步" }

    /// 「填 Key、选提问键」
    public var missingSummary: String { missing.map(\.shortTitle).joined(separator: "、") }

    /// 菜单栏第一行下面那句；做完时是「按住 右 ⌥ 看着屏幕问」
    public func menuDetail(screenHotkeyTitle: String) -> String {
        allDone ? "按住 \(screenHotkeyTitle) 看着屏幕问" : "还差 \(missing.count) 项：\(missingSummary)"
    }
}
