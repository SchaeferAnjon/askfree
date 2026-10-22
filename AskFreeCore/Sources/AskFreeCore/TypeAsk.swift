import Foundation

/// 打字问 AI：双击一颗修饰键（默认不设，用户自己选），截下此刻的屏幕，弹出输入框打字提问。
/// 配置键 ask_type_double_tap 存 RecordingHotkeyModifier.rawValue，"none" = 不设置。
public enum TypeAskHotkey {
    public static let key = "ask_type_double_tap"
    public static let title = "打字问 AI"
    /// 可选的键。Fn 双击常被系统占（听写），右 Option / 右 Command 和通用键分不开左右双击，都不给
    public static let choices: [RecordingHotkeyModifier] = [.control, .command, .shift, .option]

    public static func current(in config: AskFreeConfig = .shared) -> RecordingHotkeyModifier? {
        config.string(forKey: key).flatMap { RecordingHotkeyModifier(rawValue: $0) }
    }

    public static func set(_ modifier: RecordingHotkeyModifier?, in config: AskFreeConfig = .shared) {
        config.save(value: modifier?.rawValue ?? "none", forKey: key)
    }

    public static func displayName(in config: AskFreeConfig = .shared) -> String {
        current(in: config).map { "双击 \($0.symbol) \($0.displayName)" } ?? "未设置"
    }

    /// 说话提问的快捷键用的是同一颗修饰键（右 Option 和 Option 也算）：双击会先被那边当成「轻点开始、再点结束」，
    /// 分不清用户要干什么，这时双击不响应
    public static func conflict(in config: AskFreeConfig = .shared) -> String? {
        guard let mine = current(in: config) else { return nil }
        for hotkey in [AskHotkey.screen, AskHotkey.plain] where hotkey.isActive(in: config) {
            if case .modifier(let m)? = hotkey.current(in: config), m.flag == mine.flag {
                return "和「\(hotkey.title)」的快捷键（\(m.displayName)）是同一颗键"
            }
        }
        return nil
    }

    public static func isActive(in config: AskFreeConfig = .shared) -> Bool {
        current(in: config) != nil && conflict(in: config) == nil
    }
}

/// 认双击修饰键：只按这一颗、很快松开算一次轻点，两次轻点挨得够近就触发。
/// 中间按了别的键或别的修饰键、点了鼠标、按得太久（那是按住，比如 ⌃ 点鼠标右键），都从头数。
public struct DoubleTapDetector {
    public static let maxTapDuration: TimeInterval = 0.35
    public static let maxGap: TimeInterval = 0.4
    private static let modifierMask: HotkeyModifierFlags = [.shift, .control, .option, .command, .function]

    public var target: HotkeyModifierFlags
    private var downAt: TimeInterval?
    private var lastTapUpAt: TimeInterval?
    /// 上一刻按着的修饰键。只有从「一颗都没按」到「只按目标键」才算按下：⌃⇧ 松开 ⇧ 剩下的 ⌃ 不算
    private var previous: HotkeyModifierFlags = []

    public init(target: HotkeyModifierFlags) {
        self.target = target
    }

    public enum Input {
        case flagsChanged(rawFlags: UInt64, at: TimeInterval)
        /// 按了别的键、点了鼠标
        case interrupt
    }

    /// true = 这一下凑成了双击
    public mutating func handle(_ input: Input) -> Bool {
        guard case .flagsChanged(let rawFlags, let at) = input else {
            reset()
            return false
        }
        let flags = HotkeyModifierFlags(rawValue: UInt(truncatingIfNeeded: rawFlags)).intersection(Self.modifierMask)
        defer { previous = flags }
        if flags == target {
            if previous.isEmpty { downAt = at }
            return false
        }
        guard flags.isEmpty, let down = downAt else {
            reset()
            return false
        }
        downAt = nil
        guard at - down <= Self.maxTapDuration else {
            lastTapUpAt = nil
            return false
        }
        if let up = lastTapUpAt, down - up <= Self.maxGap {
            lastTapUpAt = nil
            return true
        }
        lastTapUpAt = at
        return false
    }

    public mutating func reset() {
        downAt = nil
        lastTapUpAt = nil
    }
}
