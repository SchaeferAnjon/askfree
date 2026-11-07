import Cocoa
import Combine
import SwiftUI
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 菜单栏图标和它的菜单（design/onboarding 方向 A5）：
/// 第一行说现在能不能问、还差哪几项；没设完时多一项「继续设置…」、图标右下角挂橙点；
/// 麦克风那一行右边直接写在用哪个。
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let appearanceObserver = AppearanceObservingView(frame: .zero)
    private weak var delegate: AppDelegate?
    private var statusSubscription: AnyCancellable?
    private var tipPopover: NSPopover?

    init(delegate: AppDelegate) {
        self.delegate = delegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.addSubview(appearanceObserver)
            appearanceObserver.onAppearanceChange = { [weak self] in self?.refreshIcon() }
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        MainActor.assumeIsolated {
            statusSubscription = SetupStatus.shared.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshIcon() }
        }
        refreshIcon()
    }

    /// 启动自测用：图标真的挂上菜单栏了
    var isShowing: Bool { statusItem.isVisible && statusItem.button?.image != nil }

    // MARK: 菜单

    /// 每次点开都按此刻的状态重排
    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            SetupStatus.shared.refresh()
            rebuild(menu, status: SetupStatus.shared)
        }
    }

    @MainActor
    private func rebuild(_ menu: NSMenu, status: SetupStatus) {
        menu.removeAllItems()
        menu.addItem(statusItemRow(status))
        if !status.allDone {
            menu.addItem(ClosureMenuItem("继续设置…") { OnboardingWindowController.show() })
        }
        // 会员：剩几个问题、到期、欠费，点开会员页
        if UsageModeStore.isMember {
            let line = MemberClient.shared.summary
            let item = ClosureMenuItem("会员…") { SettingsWindowController.show(page: .member) }
            item.attributedTitle = trailing("会员", "\(line.title) · \(line.detail)")
            menu.addItem(item)
        }
        // 新版本后台下好了：点一下重启装上（不点也行，退出时装）
        if let version = AppUpdater.shared.phase.readyVersion {
            menu.addItem(ClosureMenuItem("重启更新到 \(version)") { AppUpdater.shared.installAndRelaunch() })
        }
        menu.addItem(.separator())

        let typeAsk = ClosureMenuItem("打字问 AI…") { [weak self] in self?.delegate?.toggleTypeAsk() }
        if let modifier = TypeAskHotkey.current() { typeAsk.attributedTitle = trailing("打字问 AI…", "双击 \(modifier.symbol)") }
        typeAsk.isEnabled = status.askReady
        menu.addItem(typeAsk)
        menu.addItem(ClosureMenuItem("历史记录") { SettingsWindowController.show(page: .history) })
        let mic = NSMenuItem(title: "麦克风", action: nil, keyEquivalent: "")
        mic.attributedTitle = trailing("麦克风", MicrophoneManager.shared.selectedUID == MicrophoneManager.systemDefaultUID
                                       ? "跟随系统" : MicrophoneManager.shared.displayName())
        mic.submenu = microphoneMenu()
        menu.addItem(mic)
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("打开 Ask Free") { SettingsWindowController.show() })
        let settings = ClosureMenuItem("设置…") { SettingsWindowController.show(page: .hotkeys) }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = ClosureMenuItem("退出 Ask Free") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    /// 第一行：● 可以提问 / 按住 右 ⌥ 看着屏幕问；● 还不能提问 / 还差 2 项：填 Key、选提问键
    @MainActor
    private func statusItemRow(_ status: SetupStatus) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        let dotColor: NSColor = status.allDone ? .systemGreen : .systemOrange
        let title = status.allDone ? "可以提问" : "还不能提问"
        let detail = status.checklist.menuDetail(screenHotkeyTitle: SettingsStore.shared.hotkeys.screenTitle)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: dotColor, .font: NSFont.systemFont(ofSize: 10)]))
        text.append(NSAttributedString(string: title + "\n", attributes: [.foregroundColor: NSColor.labelColor,
                                                                           .font: NSFont.systemFont(ofSize: 13, weight: .semibold)]))
        text.append(NSAttributedString(string: "    " + detail, attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                                                                              .font: NSFont.systemFont(ofSize: 12)]))
        item.attributedTitle = text
        return item
    }

    /// 左边名字、右边灰字（菜单宽度不定，用右对齐制表位）
    private func trailing(_ title: String, _ value: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 230)]
        let text = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: style])
        text.append(NSAttributedString(string: "\t" + value, attributes: [.font: NSFont.menuFont(ofSize: 0),
                                                                           .foregroundColor: NSColor.secondaryLabelColor,
                                                                           .paragraphStyle: style]))
        return text
    }

    private func microphoneMenu() -> NSMenu {
        let mgr = MicrophoneManager.shared
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        // 选的麦克风拔掉了：勾会落在「跟随系统默认」上，先说一句为什么，插回来会自动切回去
        if mgr.isPreferredDeviceMissing {
            let note = NSMenuItem(title: "所选麦克风未连接，暂用系统默认", action: nil, keyEquivalent: "")
            note.isEnabled = false
            submenu.addItem(note)
        }
        submenu.addItem(ClosureMenuItem("跟随系统默认（\(mgr.systemDefaultDeviceName ?? "未知")）",
                                        checked: mgr.selectedUID == MicrophoneManager.systemDefaultUID) {
            mgr.select(uid: MicrophoneManager.systemDefaultUID)
        })
        submenu.addItem(.separator())
        for device in mgr.devices {
            submenu.addItem(ClosureMenuItem(device.isBuiltIn ? "\(device.name)（推荐）" : device.name,
                                            checked: mgr.selectedUID == device.uid) {
                mgr.select(uid: device.uid)
            })
        }
        return submenu
    }

    // MARK: 图标

    /// 没设完时图标右下角挂一个橙点
    private func refreshIcon() {
        guard let baseIcon = NSImage(named: "statusbar-icon") else {
            statusItem.button?.title = "Ask"
            return
        }
        let needsSetup = MainActor.assumeIsolated { !SetupStatus.shared.allDone }
        let icon: NSImage
        if needsSetup {
            var dotted: NSImage?
            statusItem.button?.effectiveAppearance.performAsCurrentDrawingAppearance {
                dotted = baseIcon.withDot(color: .systemOrange)
            }
            icon = dotted ?? baseIcon
            icon.isTemplate = false
        } else {
            icon = baseIcon
            icon.isTemplate = true
        }
        icon.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = icon
        statusItem.button?.title = ""
    }

    /// 走完引导：图标下面弹一句「Ask Free 住在菜单栏这里」，几秒后自己收起
    func showWhereIAm() {
        guard let button = statusItem.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarTip())
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        tipPopover = popover
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.tipPopover?.performClose(nil)
            self?.tipPopover = nil
        }
    }
}

private struct MenuBarTip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Ask Free 住在菜单栏这里").font(.system(size: 13, weight: .semibold))
            Text("点这个图标能打字问、看历史、打开设置。").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

private extension NSImage {
    /// 在图标右下角合成一个小圆点，用于状态栏角标
    func withDot(color: NSColor) -> NSImage? {
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        // 先把基础图标按模板着色为深色画上去
        let rect = NSRect(origin: .zero, size: size)
        NSColor.labelColor.set()
        rect.fill()
        draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)

        let dotDiameter = max(size.width * 0.32, 5)
        color.set()
        NSBezierPath(ovalIn: NSRect(x: size.width - dotDiameter, y: 0, width: dotDiameter, height: dotDiameter)).fill()
        return result
    }
}
