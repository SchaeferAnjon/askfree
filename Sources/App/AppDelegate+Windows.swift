import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension AppDelegate: NSMenuDelegate {
    /// 建立标准主菜单（App 菜单 + 编辑菜单）。
    /// 关键作用：编辑菜单里「剪切/拷贝/粘贴/全选/撤销」带标准快捷键，
    /// macOS 正是靠这些菜单项把 Cmd+X/C/V/A/Z 分发给当前输入框。
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App 菜单（关于 / 设置 / 隐藏 / 退出）
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(ClosureMenuItem("关于 Ask Free") { MainActor.assumeIsolated { SettingsWindowController.show(page: .about) } })
        appMenu.addItem(.separator())
        let settings = ClosureMenuItem("设置…") { MainActor.assumeIsolated { SettingsWindowController.showSettings() } }
        settings.keyEquivalent = ","
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Ask Free", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Ask Free", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 编辑菜单（让 Cmd+X/C/V/A/Z 生效）
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // 显示菜单：⌘1 到 ⌘9 对应侧栏从上到下九页
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "显示")
        viewMenu.delegate = self
        viewItem.submenu = viewMenu
        for page in MainPage.allCases {
            let item = ClosureMenuItem(page.title) { MainActor.assumeIsolated { SettingsWindowController.show(page: page) } }
            item.keyEquivalent = page.menuKeyEquivalent
            item.representedObject = page.rawValue
            viewMenu.addItem(item)
        }

        // 窗口菜单：⌘W 只关窗口，App 照常留在菜单栏（关掉最后一个窗口不退出）
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// 「显示」菜单打开前：第一项跟侧栏一样，三步做完叫「首页」
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "显示" else { return }
        let allDone = MainActor.assumeIsolated { SetupStatus.shared.allDone }
        menu.items.first { $0.representedObject as? String == MainPage.start.rawValue }?.title = MainPage.start.title(setupDone: allDone)
    }

    func showSettingsCenter() {
        MainActor.assumeIsolated { SettingsWindowController.show() }
    }

    /// 打开主窗口并直接跳到「语音与模型」（没填 Key 时用）
    func showModelSettings() {
        MainActor.assumeIsolated { SettingsWindowController.show(page: .models) }
    }
}
