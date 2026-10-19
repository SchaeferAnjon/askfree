import Cocoa
import Combine
import AudioToolbox
import AVFoundation
import ApplicationServices
#if canImport(AskFreeCore)
import AskFreeCore
#endif

protocol SettingsWindowDelegate: AnyObject {
    func openAccessibilitySettings()
    func openMicrophoneSettings()
    /// 复用 App 的调试日志（同一个文件、同一套轮转），设置页的耗时诊断也写进去。
    func debugLog(_ message: String)
}

// MARK: - Window controller

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    enum Page: CaseIterable {
        case home
        case model
        case settings
        case about

        var title: String {
            switch self {
            case .home: return "首页"
            case .model: return "模型"
            case .settings: return "设置"
            case .about: return "关于"
            }
        }

        var symbolName: String {
            switch self {
            case .home: return "house"
            case .model: return "cpu"
            case .settings: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    static var shared: SettingsWindowController?

    weak var settingsDelegate: SettingsWindowDelegate?
    let config = AskFreeConfig.shared
    var selectedPage: Page = .home
    private var sidebarRows: [Page: SidebarRow] = [:]
    private let sidebarContainer = NSView()
    private let contentHost = NSView()
    var bigASRAPIKeyField: NSSecureTextField?
    var bailianKeyField: NSSecureTextField?
    var asrVersionControl: VPSegmentedControl?
    var asrProviderControl: VPSegmentedControl?
    var asrKeyContainer: NSStackView?
    var asrGetKeyButton: NSButton?
    var dashscopeAPIKeyField: NSSecureTextField?
    var arkAPIKeyField: NSSecureTextField?
    var deepseekAPIKeyField: NSSecureTextField?
    var askProviderControl: VPSegmentedControl?
    var askKeyContainer: NSStackView?
    var askGetKeyButton: NSButton?
    var asrTestResultLabel: NSTextField?
    var askTestResultLabel: NSTextField?
    var healthExpandedOverride: Bool?       // nil=按状态默认（全绿折叠/有问题展开）
    var lastHealthExpanded = false          // 健康卡上次渲染时是否展开，点摘要行时取反它
    var asrTestButton: VPButton?
    var askTestButton: VPButton?
    var launchAtLoginCheckbox: VPToggle?
    weak var micPermissionSubLabel: NSTextField?
    weak var accessibilityPermissionSubLabel: NSTextField?
    weak var screenPermissionSubLabel: NSTextField?
    /// 上次切回 App 时看到的权限和统计，用来判断这次要不要刷新页面
    private var lastExternalState: ExternalState?

    // Page cache (lazy build, isHidden swap)
    private var cachedScrolls: [Page: NSScrollView] = [:]
    var activeMicrophonePicker: MicrophonePickerSheet?

    let theme = VPTheme.automatic
    // 原是写死的浅灰：浅色值保持原样，只给深色配对应颜色
    static let dropdownBorder = VPTheme.adaptive(light: NSColor.black.withAlphaComponent(0.16),
                                                         dark: NSColor.white.withAlphaComponent(0.16))

    static func show(delegate: SettingsWindowDelegate, initialPage: Page? = nil) {
        let controller: SettingsWindowController
        if let existing = shared {
            existing.settingsDelegate = delegate
            existing.reload()
            controller = existing
        } else {
            controller = SettingsWindowController(delegate: delegate)
            shared = controller
        }
        if let page = initialPage { controller.selectPage(page) }
        controller.clampWindowToMinSize()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(delegate: SettingsWindowDelegate) {
        self.settingsDelegate = delegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask Free"  // 仅供系统辅助功能/窗口菜单，标题栏不显示（侧栏已有带 logo 的名字，避免重复）
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 1040, height: 600)   // 1040 以下统计大数字会被挤，锁住下限
        window.isReleasedWhenClosed = false
        window.contentView = AppearanceObservingView()  // 自定义根视图，用于捕获日/夜模式切换
        super.init(window: window)
        window.delegate = self
        applyMainWindowAppearance()   // 先定外观再建页面，颜色第一次就按对的深浅上
        if !window.setFrameAutosaveName("AskFreeMainWindow") {
            window.center()
        }
        clampWindowToMinSize()
        // macOS 26 上自定义 contentView 与窗口之间的宽度跟随（autoresizing 桥接）会丢失，
        // 布局引擎转而把 contentView 连同窗口压到内容的最小宽度（首页恰好 629，窗口随之变窄）。
        // 显式把 contentView 宽度钉回窗口内容区，窗口尺寸恢复由用户/frame 恢复控制。
        if let cv = window.contentView, let guide = window.contentLayoutGuide as? NSLayoutGuide {
            cv.widthAnchor.constraint(equalTo: guide.widthAnchor).isActive = true
        }
        setupShell()
        rebuildSidebar()
        selectPage(.home)
        lastExternalState = ExternalState.current()
        // 系统切换外观只刷新颜色，保留输入框、滚动位置和展开状态。
        (window.contentView as? AppearanceObservingView)?.onAppearanceChange = { [weak self] in
            self?.applyTheme()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(microphoneSelectionDidChange),
            name: .askFreeMicrophoneSelectionDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(microphoneSelectionDidChange),
            name: .askFreeMicrophoneListDidChange,
            object: nil
        )
        // 用户去系统设置开权限再切回来时，健康卡/权限行的状态要跟着变
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(permissionsMayHaveChanged),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(permissionsMayHaveChanged),
            name: .askFreeAccessibilityGranted,
            object: nil
        )
        // 「设置 → 外观」切换，或系统深浅切换（含「自动」模式天黑天亮）：重新套外观
        MainWindowAppearance.observeSystemChanges()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceSettingDidChange),
            name: MainWindowAppearance.didChangeNotification,
            object: nil
        )
    }

    // MARK: - 外观（只管主窗口）

    /// 按「设置 → 外观」给主窗口设外观。只设这一个窗口（它弹出的子窗口、菜单会自动跟随），
    /// App 其余部分仍锁浅色。外观变化会触发 AppearanceObservingView → applyTheme 刷新全部颜色。
    private func applyMainWindowAppearance() {
        guard let window else { return }
        let appearance = MainWindowAppearance.resolve()
        MainWindowAppearance.applied = appearance
        guard window.appearance?.name != appearance.name else { return }
        window.appearance = appearance
        applyTheme()
    }

    @objc private func appearanceSettingDidChange() {
        applyMainWindowAppearance()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyMainWindowAppearance()   // 兜底：万一漏了切换通知，用户回到窗口时补上
    }

    @objc private func permissionsMayHaveChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshForExternalChanges()
        }
    }

    /// 切回 App 时首页和设置页要看的外部状态：三项权限。和上次画页面时一样就什么都不做
    private struct ExternalState: Equatable {
        var micStatus: AVAuthorizationStatus
        var accessibility: Bool
        var screenRecording: Bool

        static func current() -> ExternalState {
            ExternalState(micStatus: AVCaptureDevice.authorizationStatus(for: .audio),
                          accessibility: AXIsProcessTrusted(),
                          screenRecording: ScreenSnapshotCapturer.hasPermission)
        }
    }

    /// 权限变了：设置页权限卡就地改文字，侧栏底部麦克风状态重画，首页健康卡重建。
    private func refreshForExternalChanges() {
        let now = ExternalState.current()
        let before = lastExternalState
        lastExternalState = now
        guard let before, before != now else { return }
        if before.micStatus != now.micStatus { rebuildSidebar() }
        updatePermissionsCardInPlace()
        invalidate(.home)
    }

    @objc private func microphoneSelectionDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.invalidate(.settings, .home)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.shared = nil
    }

    /// 窗口可能被首次布局/frame 恢复等程序化路径压到 minSize 以下（minSize 只挡手动拖拽），统一补回下限
    func clampWindowToMinSize() {
        guard let window else { return }
        if window.frame.width < window.minSize.width || window.frame.height < window.minSize.height {
            var frame = window.frame
            frame.size.width = max(frame.size.width, window.minSize.width)
            frame.size.height = max(frame.size.height, window.minSize.height)
            window.setFrame(frame, display: true)
        }
    }


    // MARK: - Shell

    private func setupShell() {
        guard let cv = window?.contentView else { return }
        cv.wantsLayer = true
        cv.layer?.setAppearanceBackground(theme.bg)

        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.wantsLayer = true
        cv.addSubview(sidebarContainer)

        let divider = NSBox()
        divider.boxType = .custom
        divider.fillColor = theme.sep
        divider.borderWidth = 0
        divider.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(divider)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.wantsLayer = true
        cv.addSubview(contentHost)

        NSLayoutConstraint.activate([
            sidebarContainer.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sidebarContainer.topAnchor.constraint(equalTo: cv.topAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            sidebarContainer.widthAnchor.constraint(equalToConstant: 178),
            divider.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            divider.topAnchor.constraint(equalTo: cv.topAnchor),
            divider.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            contentHost.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: cv.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        applyTheme()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        applyTheme()
    }

    private func applyTheme() {
        guard let cv = window?.contentView else { return }
        cv.layer?.setAppearanceBackground(theme.bg)
        sidebarContainer.layer?.setAppearanceBackground(theme.sidebarBg)
        contentHost.layer?.setAppearanceBackground(theme.bg)
        window?.backgroundColor = theme.bg
        (cv as? AppearanceObservingView)?.refreshAppearance()
    }

    // MARK: - Sidebar

    func rebuildSidebar() {
        sidebarContainer.subviews.forEach { $0.removeFromSuperview() }
        sidebarContainer.layer?.setAppearanceBackground(theme.sidebarBg)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(stack)

        // Brand
        let brand = makeBrandHeader()
        stack.addArrangedSubview(brand)
        brand.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(14, after: brand)

        let groups: [(String?, [(Page, String?)])] = [
            ("工作台", [(.home, nil)]),
            ("配置", [(.model, nil), (.settings, nil)]),
            (nil, [(.about, nil)]),
        ]

        sidebarRows.removeAll()
        for (gtitle, items) in groups {
            if let gt = gtitle {
                stack.addArrangedSubview(makeGroupTitle(gt))
                stack.arrangedSubviews.last!.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            for (page, count) in items {
                let row = SidebarRow(page: page, count: count)
                row.apply(theme: theme)
                row.isSelected = (page == selectedPage)
                row.onClick = { [weak self] in self?.selectPage($0) }
                sidebarRows[page] = row
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }

        // spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(spacer)
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true

        // bottom status
        let bottom = makeSidebarStatus()
        stack.addArrangedSubview(bottom)
        bottom.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: sidebarContainer.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor, constant: -10),
        ])
    }

    private func makeBrandHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let logo = makeBrandMark(box: 28, corner: 8, boxColor: theme.accent, inkColor: theme.onAccent)

        let title = NSTextField(labelWithString: "Ask Free")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = theme.text
        title.translatesAutoresizingMaskIntoConstraints = false

        let version = NSTextField(labelWithString: Bundle.main.appVersionString)
        version.font = .systemFont(ofSize: 11, weight: .medium)
        version.textColor = theme.text3
        version.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(logo)
        header.addSubview(title)
        header.addSubview(version)

        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            logo.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 9),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            version.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 7),
            version.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            version.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -8),
            header.heightAnchor.constraint(equalToConstant: 42),
        ])
        return header
    }

    private func makeGroupTitle(_ text: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let lbl = NSTextField(labelWithString: text)
        lbl.font = .systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = theme.text3
        lbl.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            lbl.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor, constant: -12),
            lbl.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 10),
            lbl.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -4),
        ])
        return wrap
    }

    private func makeSidebarStatus() -> NSView {
        let bottom = NSView()
        bottom.translatesAutoresizingMaskIntoConstraints = false

        let line = NSBox()
        line.boxType = .custom
        line.fillColor = theme.sep
        line.borderWidth = 0
        line.translatesAutoresizingMaskIntoConstraints = false

        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.setAppearanceBackground((micOK ? theme.ok : theme.text3))
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: micOK ? "麦克风就绪" : "未授权麦克风")
        label.font = .systemFont(ofSize: 11)
        label.textColor = theme.text3
        label.translatesAutoresizingMaskIntoConstraints = false

        bottom.addSubview(line)
        bottom.addSubview(dot)
        bottom.addSubview(label)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 12),
            line.trailingAnchor.constraint(equalTo: bottom.trailingAnchor, constant: -12),
            line.topAnchor.constraint(equalTo: bottom.topAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            dot.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: bottom.centerYAnchor, constant: 6),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 38),
        ])
        return bottom
    }

    // MARK: - Page switching

    func selectPage(_ page: Page) {
        selectedPage = page
        for (k, row) in sidebarRows {
            row.isSelected = (k == page)
        }

        // Lazy build on first entry
        if cachedScrolls[page] == nil {
            let scroll = buildScroll(for: page)
            cachedScrolls[page] = scroll
            contentHost.addSubview(scroll)
            scroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: contentHost.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            ])
        }

        // Toggle visibility instead of destroy/rebuild
        for (k, scroll) in cachedScrolls {
            scroll.isHidden = (k != page)
        }
    }

    private func buildScroll(for page: Page) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = false // 隐藏主页面滚动条，仍可用滚轮和触控板滚动。
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        // 窗口是透明全尺寸标题栏，NSScrollView 会自动再加一段标题栏高度的顶部留白（约 38pt），
        // 叠上下面的 40 就成了近 80pt 的空档，页面看着头重脚轻。关掉自动留白，顶部只留和侧栏 logo 对齐的一段。
        scroll.automaticallyAdjustsContentInsets = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)

        switch page {
        case .home: buildHome(into: stack)
        case .model: buildModel(into: stack)
        case .settings: buildSettings(into: stack)
        case .about: buildAbout(into: stack)
        }

        for v in stack.arrangedSubviews {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        scroll.documentView = doc

        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 56),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -56),
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 36),   // 与侧栏品牌头（32）大致齐平
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -48),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 880),
        ])

        return scroll
    }

    /// Drop the cached view for the given pages so they rebuild on next entry.
    /// If the currently-visible page is invalidated, rebuild it immediately.
    func invalidate(_ pages: Page...) {
        // 当前页重建后回到原来的滚动位置，否则在页面中间改个设置（或切回 App）就被弹回顶部
        var savedOrigin: NSPoint?
        for p in pages {
            if let scroll = cachedScrolls.removeValue(forKey: p) {
                if p == selectedPage { savedOrigin = scroll.contentView.bounds.origin }
                scroll.removeFromSuperview()
            }
        }
        if pages.contains(selectedPage) {
            selectPage(selectedPage)
            if let origin = savedOrigin, origin.y > 0,
               let scroll = cachedScrolls[selectedPage] {
                contentHost.layoutSubtreeIfNeeded()
                let docHeight = scroll.documentView?.frame.height ?? 0
                let maxY = max(0, docHeight - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(origin.y, maxY)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }

    /// Wipe all caches (e.g. on theme change) and rebuild the visible page.
    private func reload() {
        for (_, scroll) in cachedScrolls {
            scroll.removeFromSuperview()
        }
        cachedScrolls.removeAll()
        contentHost.layer?.setAppearanceBackground(theme.bg)
        selectPage(selectedPage)
    }

    /// 快捷键菜单此刻在给哪一套选
    var hotkeyMenuTarget: AskHotkey = .screen
    /// 展开了说明的卡片
    var expandedCards = Set<String>()

    /// 问答模型分段当前显示的服务商顺序（豆包默认隐藏，见 makeAskModelCard）
    var askSegProviders: [String] = ["qwen", "deepseek", "none"]

    /// 各「模型」分段建行时的预设（configKey → presets），点分段时按它存，不在这里另写一份
    var askModelPresets: [String: [String]] = [:]
}
