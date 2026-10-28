import Foundation

/// 截屏没成功的原因
public enum ScreenSnapshotError: Error, Equatable {
    /// 没给屏幕录制权限
    case noPermission
    case noDisplay
    case captureFailed(String)
    case encodeFailed

    /// 给用户看的一句话，要能照着办
    public var userMessage: String {
        switch self {
        case .noPermission: return "还没给屏幕录制权限，这次只按问题回答。去「系统设置 → 隐私与安全性 → 屏幕录制」勾上 Ask Free，然后退出并重新打开 Ask Free。"
        case .noDisplay: return "没找到指针所在的屏幕，这次只按问题回答。"
        case .captureFailed(let reason): return "截屏失败（\(reason)），这次只按问题回答。"
        case .encodeFailed: return "截屏编码失败，这次只按问题回答。"
        }
    }

    /// 日志用的短名（不含任何屏幕内容）
    public var debugName: String {
        switch self {
        case .noPermission: return "noPermission"
        case .noDisplay: return "noDisplay"
        case .captureFailed(let reason): return "captureFailed(\(reason))"
        case .encodeFailed: return "encodeFailed"
        }
    }
}

/// 「这次没看屏幕」那条右边的按钮
public enum ScreenNoteAction: Equatable {
    /// 还没给屏幕录制权限：去授权
    case grant
    /// 启动后才给的权限，这次运行还截不到：重新打开 Ask Free
    case relaunch
}

/// 回答上面那条橙底提示「这次没看屏幕：…」
public enum AskScreenNote {
    /// 截图在说完话时还没好
    public static let slowCapture = "截屏没赶上，这次只按问题回答。"

    /// note 是这次没带屏幕的原因（上面 userMessage 那几句）；needsRelaunch = 屏幕录制是启动后才给的
    public static func banner(for note: String, needsRelaunch: Bool) -> (text: String, action: ScreenNoteAction?) {
        if note == ScreenSnapshotError.noPermission.userMessage {
            return ("这次没看屏幕：还没给屏幕录制权限", .grant)
        }
        if needsRelaunch {
            // 权限是启动后才给的：截屏要换个新进程才生效，说清楚并给「重新打开」
            return ("这次没看屏幕：屏幕录制刚打开，重新打开 Ask Free 后生效", .relaunch)
        }
        // 去掉原因里「这次只按问题回答」那半句，面板上一行说完
        let reason = note.components(separatedBy: "，这次只按问题回答").first ?? note
        return ("这次没看屏幕：" + reason.trimmingCharacters(in: CharacterSet(charactersIn: "。")), nil)
    }
}
