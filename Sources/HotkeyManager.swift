import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension Notification.Name {
    static let askFreeHotkeyDidChange = Notification.Name("AskFreeHotkeyDidChange")
}

// 快捷键的数据类型、配置读写、撞键检测和手势状态机都在 AskFreeCore（HotkeyModel.swift、
// HotkeyGestureMachine.swift）。这里只做 NSEvent / CGEvent 和 Core 类型之间的转换，以及事件监听。

extension HotkeyModifierFlags {
    init(_ flags: NSEvent.ModifierFlags) { self.init(rawValue: flags.rawValue) }
}

extension RecordingHotkeyModifier {
    var eventFlag: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: flag.rawValue) }

    var cgFlag: CGEventFlags { CGEventFlags(rawValue: UInt64(flag.rawValue)) }

    /// optionLeftOnly：右 Option 让给了另一套热键（看屏幕问 AI）时，通用的 Option 只认左边那颗
    func matches(_ event: NSEvent, optionLeftOnly: Bool = false) -> Bool {
        matches(rawFlags: UInt64(event.modifierFlags.rawValue), optionLeftOnly: optionLeftOnly)
    }

    /// 此刻这颗键是不是按着（不依赖事件，松手确认时用）
    func isPressedNow(optionLeftOnly: Bool = false) -> Bool {
        matches(rawFlags: CGEventSource.flagsState(.combinedSessionState).rawValue, optionLeftOnly: optionLeftOnly)
    }

    static func capture(from event: NSEvent) -> RecordingHotkeyModifier? {
        capture(flags: HotkeyModifierFlags(event.modifierFlags), keyCode: event.keyCode)
    }
}

extension RecordingHotkeyCustomShortcut {
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyDisplay: String) {
        self.init(keyCode: keyCode, modifiers: HotkeyModifierFlags(modifiers), keyDisplay: keyDisplay)
    }

    func matchesKeyDown(_ event: NSEvent) -> Bool {
        matchesKeyDown(keyCode: event.keyCode, flags: HotkeyModifierFlags(event.modifierFlags))
    }

    func matchesKeyUp(_ event: NSEvent) -> Bool {
        matchesKeyUp(keyCode: event.keyCode)
    }

    static func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: normalized(HotkeyModifierFlags(flags)).rawValue)
    }

    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        symbols(for: HotkeyModifierFlags(flags))
    }

    static func keyDisplayName(for event: NSEvent) -> String {
        keyDisplayName(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
    }
}

/// 一套热键从哪读配置。看屏幕问、纯提问各一份，按住 / 轻点锁定 / Esc 取消这些手势逻辑共用。
struct HotkeyProfile {
    let name: String
    let shortcut: () -> RecordingHotkeyShortcut?
    let tapToggleEnabled: () -> Bool
    /// 通用的 Option 是否只认左边那颗
    let optionLeftOnly: () -> Bool
    /// false = 这一套整个不响应
    let isActive: () -> Bool

    static func ask(_ hotkey: AskHotkey) -> HotkeyProfile {
        HotkeyProfile(
            name: hotkey.prefix,
            shortcut: { hotkey.current },
            tapToggleEnabled: { true },   // 触控板用户按住说话很累：轻点一下开始、再点一下结束一直可用
            optionLeftOnly: { HotkeyArbiter.leftOnly(for: hotkey.prefix, shortcut: hotkey.current) },
            isActive: { hotkey.isActive })
    }
}


/// 把 NSEvent 转成 HotkeyGestureMachine 的输入，把输出接到回调和定时器上。手势规则本身在 Core 的状态机里。
class HotkeyManager {
    /// 全局暂停：设置里正在录「自定义快捷键」时置 true，所有热键都不响应，免得录 ⌥Space 时一按 ⌥ 就开始提问。
    /// 恢复后发一次 askFreeHotkeyDidChange，让各实例按实际按键状态重新同步 wasModifierDown。
    static var isSuspended = false

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private let onStart: () -> Bool
    private let onStop: () -> Void
    private let profile: HotkeyProfile
    private let environment: HotkeyGestureMachine.Environment

    private var machine: HotkeyGestureMachine
    private var pendingStopWorkItem: DispatchWorkItem?
    private var holdPromotionWorkItem: DispatchWorkItem?

    var debugLog: ((String) -> Void)?
    /// 手势定性：true=长按（松手即停）、false=单击切换（已锁定，需要再按/点按钮结束）
    var onGestureClassified: ((Bool) -> Void)?
    /// 键盘长按期间按 Esc：丢弃本次录音
    var onCancel: (() -> Void)?

    init(
        profile: HotkeyProfile,
        onStart: @escaping () -> Bool,
        onStop: @escaping () -> Void,
        isRecording: @escaping () -> Bool
    ) {
        self.profile = profile
        self.machine = HotkeyGestureMachine(
            shortcut: profile.shortcut() ?? .modifier(.option),   // 未设置时 isActive 为 false，不会用到
            tapToggleEnabled: profile.tapToggleEnabled())
        self.environment = HotkeyGestureMachine.Environment(
            isSuspended: { HotkeyManager.isSuspended },
            isActive: profile.isActive,
            optionLeftOnly: profile.optionLeftOnly,
            isRecording: isRecording)
        self.onStart = onStart
        self.onStop = onStop
        startListening()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidChange),
            name: .askFreeHotkeyDidChange,
            object: nil
        )
    }

    func stop() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m); globalFlagsMonitor = nil }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m); localFlagsMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        pendingStopWorkItem?.cancel()
        pendingStopWorkItem = nil
        holdPromotionWorkItem?.cancel()
        holdPromotionWorkItem = nil
        NotificationCenter.default.removeObserver(self)
    }

    func recordingDidLeaveActiveState() {
        let pressed = isHotkeyCurrentlyPressed(machine.shortcut)
        perform(machine.recordingDidLeaveActiveState(isPressedNow: pressed))
    }

    private func startListening() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        send(.flagsChanged(rawFlags: UInt64(event.modifierFlags.rawValue), keyCode: event.keyCode,
                           at: ProcessInfo.processInfo.systemUptime))
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        switch event.type {
        case .keyDown:
            send(.keyDown(keyCode: event.keyCode, flags: HotkeyModifierFlags(event.modifierFlags),
                          isRepeat: event.isARepeat, at: now))
        case .keyUp:
            send(.keyUp(keyCode: event.keyCode, at: now))
        default:
            break
        }
    }

    private func send(_ input: HotkeyGestureMachine.Input) {
        perform(machine.handle(input, env: environment))
    }

    /// 按顺序执行状态机给出的动作。回调排在每批最后，回调里同步重入（recordingDidLeaveActiveState）也没问题
    private func perform(_ actions: [HotkeyGestureMachine.Action]) {
        for action in actions {
            switch action {
            case .start(let at):
                let accepted = onStart()
                send(.startResult(accepted: accepted, at: at))
            case .stop:
                onStop()
            case .cancel:
                onCancel?()
            case .chordCancel:
                onCancel?()
            case .classified(let hold):
                onGestureClassified?(hold)
            case .scheduleHoldPromotion(let startedAt, let delay):
                holdPromotionWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.send(.holdPromotionDue(startedAt: startedAt))
                }
                holdPromotionWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            case .cancelHoldPromotion:
                holdPromotionWorkItem?.cancel()
                holdPromotionWorkItem = nil
            case .scheduleReleaseCheck(let delay):
                pendingStopWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let stillDown = self.isHotkeyCurrentlyPressed(self.machine.shortcut)
                    self.send(.releaseCheckDue(stillDown: stillDown, at: ProcessInfo.processInfo.systemUptime))
                }
                pendingStopWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            case .cancelReleaseCheck:
                pendingStopWorkItem?.cancel()
                pendingStopWorkItem = nil
            case .log(let message):
                debugLog?(message)
            }
        }
    }

    private func isHotkeyCurrentlyPressed(_ shortcut: RecordingHotkeyShortcut) -> Bool {
        switch shortcut {
        case .modifier(let modifier):
            return modifier.isPressedNow(optionLeftOnly: profile.optionLeftOnly())
        case .custom(let shortcut):
            return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.keyCode))
        }
    }

    @objc private func hotkeyDidChange() {
        let shortcut = profile.shortcut() ?? .modifier(.option)
        let tapToggleEnabled = profile.tapToggleEnabled()
        perform(machine.reconfigure(shortcut: shortcut, tapToggleEnabled: tapToggleEnabled,
                                    isPressedNow: isHotkeyCurrentlyPressed(shortcut)))
    }
}

/// 打字问 AI 的双击监听。和 HotkeyManager 一样只旁听，不拦事件；双击规则在 Core 的 DoubleTapDetector。
final class DoubleTapMonitor {
    private var monitors: [Any] = []
    private var detector = DoubleTapDetector(target: [])
    /// nil = 没设或和说话提问的键撞了，这时不响应。config 每读一次都要读盘，所以只在设置变了时重读
    private var modifier: RecordingHotkeyModifier?
    private let onDoubleTap: () -> Void

    init(onDoubleTap: @escaping () -> Void) {
        self.onDoubleTap = onDoubleTap
        reload()
        let flags = NSEvent.EventTypeMask.flagsChanged
        let interrupts: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: flags) { [weak self] in self?.handle($0) },
            NSEvent.addLocalMonitorForEvents(matching: flags) { [weak self] in self?.handle($0); return $0 },
            NSEvent.addGlobalMonitorForEvents(matching: interrupts) { [weak self] _ in self?.interrupt() },
            NSEvent.addLocalMonitorForEvents(matching: interrupts) { [weak self] in self?.interrupt(); return $0 },
        ].compactMap { $0 }
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .askFreeHotkeyDidChange, object: nil)
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        NotificationCenter.default.removeObserver(self)
    }

    private func handle(_ event: NSEvent) {
        guard modifier != nil, !HotkeyManager.isSuspended else { return }
        if detector.handle(.flagsChanged(rawFlags: UInt64(event.modifierFlags.rawValue), at: event.timestamp)) {
            onDoubleTap()
        }
    }

    private func interrupt() {
        _ = detector.handle(.interrupt)
    }

    @objc private func reload() {
        modifier = TypeAskHotkey.isActive() ? TypeAskHotkey.current() : nil
        detector = DoubleTapDetector(target: modifier?.flag ?? [])
    }
}
