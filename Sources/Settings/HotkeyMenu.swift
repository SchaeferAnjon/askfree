import Cocoa
import Combine
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension SettingsWindowController {
    /// 两套快捷键共用的选择按钮。标题订阅 store：任何一页改了键，各页的按钮当场换字，不重建页面
    func makeHotkeyPickerButton(for hotkey: AskHotkey, compact: Bool = false) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(showHotkeyMenu(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.font = .systemFont(ofSize: 18, weight: .semibold)
        button.alignment = .center
        button.contentTintColor = theme.text
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.setAppearanceBorder(theme.sep)
        button.layer?.setAppearanceBackground(theme.cardAlt)
        button.layer?.masksToBounds = true
        button.setButtonType(.momentaryChange)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: compact ? 112 : 134).isActive = true
        button.heightAnchor.constraint(equalToConstant: compact ? 30 : 38).isActive = true
        // identifier 告诉 showHotkeyMenu 这是哪一套；无障碍标签让读屏和自动化能认出是哪个键的按钮
        button.identifier = NSUserInterfaceItemIdentifier(hotkey.prefix)
        button.toolTip = "设置「\(hotkey.title)」的快捷键"
        button.setAccessibilityLabel("\(hotkey.title)快捷键")
        button.subscribe(SettingsStore.shared.$hotkeys.map { $0.title(of: hotkey) }.removeDuplicates()) { button, title in
            button.title = "\(title)  ▾"
        }
        return button
    }


    private func makeHotkeyMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let currentShortcut = hotkeyMenuTarget.current
        if case .custom(let custom)? = currentShortcut {
            addHotkeyMenuItem(to: menu,
                              title: custom.displayName,
                              representedObject: "custom-current",
                              symbolName: "keyboard",
                              isSelected: true)
            menu.addItem(.separator())
        }

        for modifier in [
            RecordingHotkeyModifier.option,
            .command,
            .control,
            .shift,
            .fn,
            .rightCommand,
            .rightOption,
        ] {
            let isSelected: Bool
            if case .modifier(let selectedModifier)? = currentShortcut {
                isSelected = selectedModifier == modifier
            } else {
                isSelected = false
            }
            // 别的行在用这颗键时标出来，选了会先问要不要把那一行清空
            let owners = isSelected ? [] : hotkeyOwners(of: .modifier(modifier)).map(\.title)
            let title = owners.isEmpty ? modifier.menuTitle
                : "\(modifier.menuTitle)（「\(owners.joined(separator: "」「"))」在用）"
            addHotkeyMenuItem(to: menu,
                              title: title,
                              representedObject: modifier.rawValue,
                              symbolName: modifier.symbolName,
                              isSelected: isSelected)
        }

        menu.addItem(.separator())
        addHotkeyMenuItem(to: menu,
                          title: "自定义快捷键…",
                          representedObject: "custom",
                          symbolName: "keyboard.badge.ellipsis",
                          isSelected: false)
        addHotkeyMenuItem(to: menu,
                          title: "不设置",
                          representedObject: "none",
                          symbolName: "nosign",
                          isSelected: currentShortcut == nil)

        return menu
    }

    @discardableResult
    private func addHotkeyMenuItem(to menu: NSMenu,
                                   title: String,
                                   representedObject: String,
                                   symbolName: String,
                                   isSelected: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(hotkeyMenuItemSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        item.image = hotkeyMenuImage(symbolName: symbolName)
        item.state = isSelected ? .on : .off
        menu.addItem(item)
        return item
    }

    private func hotkeyMenuImage(symbolName: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        let image = base.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? base
        image.isTemplate = true
        return image
    }

    @objc private func showHotkeyMenu(_ sender: NSButton) {
        hotkeyMenuTarget = sender.identifier?.rawValue == AskHotkey.plain.prefix ? .plain : .screen
        let menu = makeHotkeyMenu()
        let selectedItem = menu.items.first { $0.state == .on }
        menu.popUp(positioning: selectedItem, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
    }

    @objc private func hotkeyMenuItemSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        if raw == "custom" {
            presentCustomHotkeyPanel()
            return
        }
        if raw == "custom-current" {
            return
        }
        if raw == "none" {
            hotkeyMenuTarget.clear()
            applyHotkeyChange()
            return
        }
        guard let modifier = RecordingHotkeyModifier(rawValue: raw) else { return }
        if case .modifier(let current)? = hotkeyMenuTarget.current, current == modifier { return }   // 选的就是现在这颗
        guard resolveHotkeyClash(.modifier(modifier)) else { return }
        hotkeyMenuTarget.useModifier(modifier)
        applyHotkeyChange()
        if modifier == .fn { warnIfGlobeKeyHasSystemAction() }
    }

    /// 除了正在设置的这一行，还有哪几行的快捷键和 shortcut 撞（相同或重叠）。clear 把那一行改成「不设置」
    private func hotkeyOwners(of shortcut: RecordingHotkeyShortcut) -> [(title: String, clear: () -> Void)] {
        var owners: [(title: String, clear: () -> Void)] = []
        for hotkey in [AskHotkey.screen, AskHotkey.plain] where hotkey.prefix != hotkeyMenuTarget.prefix {
            if let current = hotkey.current, current.overlaps(shortcut) {
                owners.append((hotkey.title, { hotkey.clear() }))
            }
        }
        return owners
    }

    /// 新键被别的行占着：两行同一个键时只有一行会响应，所以保存前问一次，确认后把那一行清空。
    /// 返回 false 表示用户取消，这次什么都不改
    private func resolveHotkeyClash(_ shortcut: RecordingHotkeyShortcut) -> Bool {
        let owners = hotkeyOwners(of: shortcut)
        guard !owners.isEmpty else { return true }
        let names = owners.map { "「\($0.title)」" }.joined(separator: "、")
        let alert = NSAlert()
        alert.messageText = "\(names)已经在用 \(shortcut.displayName)"
        alert.informativeText = "同一个键只能给一个功能用。保存后\(names)会改成「不设置」，之后可以再给它选别的键。"
        alert.addButton(withTitle: "保存并清空\(names)")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        owners.forEach { $0.clear() }
        return true
    }

    /// 选了 Fn 当快捷键，而系统里「按下 🌐 键时」还设着切换输入法 / 表情与符号 / 系统听写：
    /// 每按一次 Fn 系统动作也会跟着出来。说清楚去哪里改成「无操作」
    private func warnIfGlobeKeyHasSystemAction() {
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

    /// 两套快捷键互相影响（撞键时谁让谁、Option 只认左边），任何一套变了都让所有监听重读。
    /// 各页的按钮和撞键提示订阅了 SettingsStore，在这里当场换字，不重建页面
    private func applyHotkeyChange() {
        SettingsStore.shared.hotkeysDidChange()
    }

    private func presentCustomHotkeyPanel() {
        let recorder = HotkeyRecorderView(frame: NSRect(x: 0, y: 0, width: 360, height: 118))
        if case .custom(let custom)? = hotkeyMenuTarget.current {
            recorder.setShortcut(custom)
        }

        let alert = NSAlert()
        alert.messageText = "自定义快捷键"
        alert.informativeText = "点击输入框，然后按下你想用于「\(hotkeyMenuTarget.title)」的快捷键。"
        alert.accessoryView = recorder
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")

        // 录键期间现有热键全部不响应：不然录 ⌥Space 时一按 ⌥ 就开始提问了。
        // 结束时（保存、取消、中途 return 都算）恢复，并发一次通知让各监听按实际按键状态重新同步、各页按钮换字
        HotkeyManager.isSuspended = true
        defer {
            HotkeyManager.isSuspended = false
            applyHotkeyChange()
        }
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            guard let shortcut = recorder.shortcut else {
                showHotkeyAlert("还没有录入快捷键", detail: "请点击输入框，然后按下一个组合键。")
                return
            }
            if let warning = shortcut.conflictWarning, !confirmRiskyHotkey(warning) {
                return
            }
            guard resolveHotkeyClash(.custom(shortcut)) else { return }
            hotkeyMenuTarget.useCustom(shortcut)
        case .alertSecondButtonReturn:
            let hotkey = hotkeyMenuTarget
            if let modifier = hotkey.defaultModifier {
                guard resolveHotkeyClash(.modifier(modifier)) else { return }
                hotkey.useModifier(modifier)
            } else {
                hotkey.clear()
            }
        default:
            break
        }
    }

    private func confirmRiskyHotkey(_ warning: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "这个快捷键可能会冲突"
        alert.informativeText = warning
        alert.addButton(withTitle: "仍然保存")
        alert.addButton(withTitle: "重新设置")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showHotkeyAlert(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
