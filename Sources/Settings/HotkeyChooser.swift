// HotkeyChooser.swift
// Ask Free
//
// 选提问键：键帽一点弹出菜单（几颗常用修饰键、自定义组合键、不设置），撞键时先问一句。
// 首页、快捷键页、欢迎引导都用这一套；改完发 .askFreeHotkeyDidChange，各处按钮当场换字。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 带闭包的菜单项，省得每项都写一个 @objc 方法
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, checked: Bool = false, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true
            self.image = image.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? image
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}

@MainActor
enum HotkeyChooser {
    /// 菜单里列的几颗键（Ask Free 不替你定键，没有默认）
    static let modifiers: [RecordingHotkeyModifier] = [.rightOption, .rightCommand, .fn, .control, .option, .command, .shift]

    // MARK: 说话提问的两套键

    static func showMenu(for hotkey: AskHotkey) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let current = hotkey.current
        if case .custom(let custom)? = current {
            menu.addItem(ClosureMenuItem(custom.displayName, symbol: "keyboard", checked: true) {})
            menu.addItem(.separator())
        }
        for modifier in modifiers {
            var selected = false
            if case .modifier(let m)? = current { selected = m == modifier }
            let owners = selected ? [] : owners(of: .modifier(modifier), except: hotkey).map(\.title)
            let title = owners.isEmpty ? modifier.menuTitle : "\(modifier.menuTitle)（「\(owners.joined(separator: "」「"))」在用）"
            menu.addItem(ClosureMenuItem(title, symbol: modifier.symbolName, checked: selected) {
                choose(modifier, for: hotkey)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("自定义组合键…", symbol: "keyboard.badge.ellipsis") { recordCustom(for: hotkey) })
        menu.addItem(ClosureMenuItem("不设置", symbol: "nosign", checked: current == nil) {
            hotkey.clear()
            SettingsStore.shared.hotkeysDidChange()
        })
        popUp(menu)
    }

    /// 选一颗修饰键。被别的问法占着时先问；选了 Fn 提醒去关系统的 🌐 键动作
    static func choose(_ modifier: RecordingHotkeyModifier, for hotkey: AskHotkey) {
        if case .modifier(let m)? = hotkey.current, m == modifier { return }
        guard resolveClash(.modifier(modifier), for: hotkey) else { return }
        hotkey.useModifier(modifier)
        SettingsStore.shared.hotkeysDidChange()
        if modifier == .fn { warnIfGlobeKeyHasSystemAction() }
    }

    static func recordCustom(for hotkey: AskHotkey) {
        let recorder = HotkeyRecorderView(frame: NSRect(x: 0, y: 0, width: 360, height: 118))
        if case .custom(let custom)? = hotkey.current { recorder.setShortcut(custom) }

        let alert = NSAlert()
        alert.messageText = "自定义组合键"
        alert.informativeText = "点一下输入框，然后按下你想用于「\(hotkey.title)」的组合键。"
        alert.accessoryView = recorder
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        // 录键期间现有热键全部不响应：不然录 ⌥Space 时一按 ⌥ 就开始提问了
        HotkeyManager.isSuspended = true
        defer {
            HotkeyManager.isSuspended = false
            SettingsStore.shared.hotkeysDidChange()
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let shortcut = recorder.shortcut else {
            simpleAlert("还没有录入组合键", "点一下输入框，然后按下一个组合键。")
            return
        }
        if let warning = shortcut.conflictWarning {
            let risky = NSAlert()
            risky.messageText = "这个组合键可能会冲突"
            risky.informativeText = warning
            risky.addButton(withTitle: "仍然保存")
            risky.addButton(withTitle: "重新设置")
            guard risky.runModal() == .alertFirstButtonReturn else { return }
        }
        guard resolveClash(.custom(shortcut), for: hotkey) else { return }
        hotkey.useCustom(shortcut)
    }

    // MARK: 打字问的双击键

    static func showTypeAskMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let current = TypeAskHotkey.current()
        for modifier in TypeAskHotkey.choices {
            menu.addItem(ClosureMenuItem("双击 \(modifier.symbol) \(modifier.displayName)", checked: current == modifier) {
                SettingsStore.shared.setTypeAsk(modifier)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("不设置", symbol: "nosign", checked: current == nil) {
            SettingsStore.shared.setTypeAsk(nil)
        })
        popUp(menu)
    }

    // MARK: 内部

    /// 在指针下面弹出（SwiftUI 按钮拿不到 NSView，按点击位置放）
    private static func popUp(_ menu: NSMenu) {
        let point = NSEvent.mouseLocation
        menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: point.x - 12, y: point.y - 6), in: nil)
    }

    private static func owners(of shortcut: RecordingHotkeyShortcut, except hotkey: AskHotkey) -> [AskHotkey] {
        [AskHotkey.screen, AskHotkey.plain].filter { other in
            other.prefix != hotkey.prefix && (other.current?.overlaps(shortcut) ?? false)
        }
    }

    /// 同一颗键只能给一个问法：保存前问一次，确认后把那一行改成「不设置」。false = 用户取消
    private static func resolveClash(_ shortcut: RecordingHotkeyShortcut, for hotkey: AskHotkey) -> Bool {
        let owners = owners(of: shortcut, except: hotkey)
        guard !owners.isEmpty else { return true }
        let names = owners.map { "「\($0.title)」" }.joined(separator: "、")
        let alert = NSAlert()
        alert.messageText = "\(names)已经在用 \(shortcut.displayName)"
        alert.informativeText = "同一个键只能给一种问法。保存后\(names)会改成「不设置」，之后可以再给它选别的键。"
        alert.addButton(withTitle: "保存并清空\(names)")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        owners.forEach { $0.clear() }
        return true
    }

    /// 系统里「按下 🌐 键时」不是「无操作」：每按一次 Fn 系统动作也会出来
    private static func warnIfGlobeKeyHasSystemAction() {
        let usage = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
        guard usage != 0 else { return }
        let alert = NSAlert()
        alert.messageText = "把系统的 🌐 键动作关掉"
        alert.informativeText = "系统设置里「按下 🌐 键时」现在不是「无操作」，每次按 Fn 提问时，系统也会切换输入法或弹出表情面板。到「系统设置 → 键盘」把它改成「无操作」。"
        alert.addButton(withTitle: "打开键盘设置")
        alert.addButton(withTitle: "知道了")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func simpleAlert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

/// 行尾的键帽按钮：设了写键名，没设是虚线框「选一个键」；撞键时字变橙
struct HotkeyButton: View {
    enum Kind { case screen, plain, typeAsk }
    let kind: Kind
    var height: CGFloat = 28
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        let title = self.title
        Button(action: tap) {
            HStack(spacing: 6) {
                Text(title ?? "选一个键").font(.system(size: height > 30 ? 14 : 12.5, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.text3)
            }
            .foregroundStyle(title == nil ? Theme.text2 : (conflict == nil ? Theme.text : Theme.warn))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(title == nil ? Color.clear : Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if title == nil {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else {
                    RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(conflict.map { "\($0)，现在不会响应" } ?? "点一下换键")
        .accessibilityLabel(accessibilityTitle)
    }

    private var title: String? {
        switch kind {
        case .screen: return store.hotkeys.screen == nil ? nil : store.hotkeys.screenTitle
        case .plain: return store.hotkeys.plain == nil ? nil : store.hotkeys.plainTitle
        case .typeAsk: return store.typeAsk.modifier.map { "双击 \($0.symbol) \($0.displayName)" }
        }
    }

    var conflict: String? {
        switch kind {
        case .screen: return store.hotkeys.screenConflict
        case .plain: return store.hotkeys.plainConflict
        case .typeAsk: return store.typeAsk.conflict
        }
    }

    private var accessibilityTitle: String {
        switch kind {
        case .screen: return "\(AskHotkey.screen.title)快捷键"
        case .plain: return "\(AskHotkey.plain.title)快捷键"
        case .typeAsk: return "\(TypeAskHotkey.title)快捷键"
        }
    }

    private func tap() {
        switch kind {
        case .screen: HotkeyChooser.showMenu(for: .screen)
        case .plain: HotkeyChooser.showMenu(for: .plain)
        case .typeAsk: HotkeyChooser.showTypeAskMenu()
        }
    }
}
