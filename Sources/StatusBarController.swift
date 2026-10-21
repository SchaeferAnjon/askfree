import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

class StatusBarController {
    private let statusItem: NSStatusItem
    private let appearanceObserver = AppearanceObservingView(frame: .zero)
    private weak var delegate: AppDelegate?
    private let micItem = NSMenuItem(title: "麦克风", action: nil, keyEquivalent: "")
    private let hotkeyHintItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(delegate: AppDelegate) {
        self.delegate = delegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.addSubview(appearanceObserver)
            appearanceObserver.onAppearanceChange = { [weak self] in self?.refreshStatusBarIcon() }
        }
        refreshStatusBarIcon()

        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Ask Free", action: #selector(openSettingsCenter), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "历史记录", action: #selector(openHistory), keyEquivalent: "")
            .target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(micItem)
        rebuildMicSubmenu()
        menu.addItem(NSMenuItem.separator())
        updateHotkeyHint()
        menu.addItem(hotkeyHintItem)
        menu.addItem(withTitle: "打开辅助功能设置", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            .target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 Ask Free", action: #selector(quitApp), keyEquivalent: "q")
            .target = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onMicListOrSelectionChanged),
            name: .askFreeMicrophoneListDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onMicListOrSelectionChanged),
            name: .askFreeMicrophoneSelectionDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onHotkeySettingsChanged),
            name: .askFreeHotkeyDidChange,
            object: nil
        )
    }

    @objc private func onMicListOrSelectionChanged() {
        rebuildMicSubmenu()
        refreshStatusBarIcon()
    }

    private func rebuildMicSubmenu() {
        let mgr = MicrophoneManager.shared
        let submenu = NSMenu()

        let defaultName = mgr.systemDefaultDeviceName ?? "未知"
        // 选的麦克风拔掉了：勾会落在「跟随系统默认」上，先说一句为什么，插回来会自动切回去
        if mgr.isPreferredDeviceMissing {
            let note = NSMenuItem(title: "所选麦克风未连接，暂用系统默认", action: nil, keyEquivalent: "")
            note.isEnabled = false
            submenu.addItem(note)
        }
        let defaultItem = NSMenuItem(
            title: "跟随系统默认（\(defaultName)）",
            action: #selector(selectMicrophone(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.representedObject = MicrophoneManager.systemDefaultUID
        defaultItem.state = mgr.selectedUID == MicrophoneManager.systemDefaultUID ? .on : .off
        submenu.addItem(defaultItem)
        submenu.addItem(NSMenuItem.separator())

        for device in mgr.devices {
            let title = device.isBuiltIn ? "\(device.name)（推荐）" : device.name
            let item = NSMenuItem(title: title, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = mgr.selectedUID == device.uid ? .on : .off
            submenu.addItem(item)
        }

        micItem.submenu = submenu
    }

    @objc private func onHotkeySettingsChanged() {
        updateHotkeyHint()
    }

    private func updateHotkeyHint() {
        hotkeyHintItem.isEnabled = false
        let hints = [AskHotkey.screen, AskHotkey.plain].filter(\.isActive).map { "\($0.title) \($0.displayName)" }
            + (TypeAskHotkey.isActive() ? ["\(TypeAskHotkey.title) \(TypeAskHotkey.displayName())"] : [])
        hotkeyHintItem.title = hints.isEmpty ? "快捷键：未设置（在设置里选择）" : "快捷键：" + hints.joined(separator: " · ")
    }

    private func refreshStatusBarIcon() {
        guard let baseIcon = NSImage(named: "statusbar-icon") else {
            statusItem.button?.title = "Ask"
            statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            return
        }

        let displayIcon: NSImage
        if MicrophoneManager.shared.isUsingNonDefault {
            var tintedIcon: NSImage?
            statusItem.button?.effectiveAppearance.performAsCurrentDrawingAppearance {
                tintedIcon = baseIcon.withBlueDotOverlay()
            }
            displayIcon = tintedIcon ?? baseIcon
            displayIcon.isTemplate = false
        } else {
            displayIcon = baseIcon
            displayIcon.isTemplate = true
        }
        displayIcon.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = displayIcon
        statusItem.button?.title = ""
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        MicrophoneManager.shared.select(uid: uid)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openSettingsCenter() {
        DispatchQueue.main.async {
            self.delegate?.showSettingsCenter()
        }
    }

    @objc private func openHistory() {
        DispatchQueue.main.async {
            guard let delegate = self.delegate else { return }
            SettingsWindowController.show(delegate: delegate, initialPage: .history)
        }
    }

    @objc private func openAccessibilitySettings() {
        delegate?.openAccessibilitySettings()
    }

}

private extension NSImage {
    /// 在图标右下角合成一个小蓝点，用于状态栏角标
    func withBlueDotOverlay() -> NSImage? {
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        // 先把基础图标按模板着色为深色画上去
        let rect = NSRect(origin: .zero, size: size)
        NSColor.labelColor.set()
        rect.fill()
        draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)

        // 角标：右下角小蓝点
        let dotDiameter = max(size.width * 0.32, 5)
        let dot = NSRect(
            x: size.width - dotDiameter,
            y: 0,
            width: dotDiameter,
            height: dotDiameter
        )
        NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.95, alpha: 1).set()
        NSBezierPath(ovalIn: dot).fill()
        return result
    }
}
