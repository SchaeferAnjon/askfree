// MainWindow.swift
// Ask Free
//
// 主窗口（design/main-window 方向 A「单窗侧栏」）：一个窗口、一列侧栏。
// 「开始」（三步做完变「首页」）、「历史」，下面七页设置；侧栏底部状态卡说还差几步。
// 窗口是 AppKit 的，里面全是 SwiftUI；深浅由「通用 → 外观」单独控制（MainWindowAppearance）。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

@MainActor
final class MainWindowModel: ObservableObject {
    /// 换页一律清掉 arrivedByArrowKey；只有侧栏 ↑↓ 在换完之后把它设回 true
    @Published var page: MainPage = .start { didSet { arrivedByArrowKey = false } }
    /// 这一页是在侧栏里按 ↑↓ 走到的：焦点该留在侧栏（「历史」不抢去给列表）
    var arrivedByArrowKey = false
    /// 主窗口上问一次匿名使用统计（UsageConsentSheet）
    @Published var asksUsageConsent = false
}

// MARK: - 窗口

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static var shared: SettingsWindowController?
    let model = MainWindowModel()

    static func show(page: MainPage? = nil) {
        let controller = shared ?? SettingsWindowController()
        shared = controller
        if let page { controller.model.page = page }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.askUsageConsentIfNeeded()
    }

    /// 匿名使用统计还没回答过：主窗口打开后问一次（老用户更新后第一次打开、引导里没答那一步的人）。
    /// 欢迎引导开着时不问，引导关掉后再问（OnboardingWindowController.windowWillClose）
    func askUsageConsentIfNeeded() {
        guard UsageConsentPrompt.isAllowed, SettingsStore.shared.usageConsent.needsAsking, !model.asksUsageConsent else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.window?.isVisible == true, OnboardingWindowController.shared == nil,
                  SettingsStore.shared.usageConsent.needsAsking else { return }
            self.model.asksUsageConsent = true
        }
    }

    /// 「设置… ⌘,」：已经在某一页设置上就留在那页，不然到第一页设置「快捷键」
    static func showSettings() {
        let current = shared?.model.page
        show(page: current.map { MainPage.settings.contains($0) } == true ? current : .hotkeys)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask Free"   // 只给辅助功能和窗口菜单用，标题栏不显示
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 860, height: 580)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let host = NSHostingView(rootView: MainWindowView(model: model))
        host.sizingOptions = [.minSize]
        window.contentView = host
        // 先居中，有记下的位置再用记下的（setFrameAutosaveName 只要名字设上就返回 true，不能拿来判断有没有记录）
        window.center()
        window.setFrameAutosaveName("AskFreeMainWindow2")
        applyAppearance()
        MainWindowAppearance.observeSystemChanges()
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceSettingDidChange),
                                               name: MainWindowAppearance.didChangeNotification, object: nil)
        SetupStatus.shared.beginWatching()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 按「通用 → 外观」给主窗口设外观；它弹出的菜单、提示框跟着窗口走，App 其余部分仍是浅色
    private func applyAppearance() {
        guard let window else { return }
        let appearance = MainWindowAppearance.resolve()
        MainWindowAppearance.applied = appearance
        if window.appearance?.name != appearance.name { window.appearance = appearance }
    }

    @objc private func appearanceSettingDidChange() { applyAppearance() }

    func windowDidBecomeKey(_ notification: Notification) { applyAppearance() }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        SetupStatus.shared.endWatching()
        Self.shared = nil
    }
}

// MARK: - 根视图

struct MainWindowView: View {
    static let sidebarWidth: CGFloat = 216
    @ObservedObject var model: MainWindowModel
    @ObservedObject private var status = SetupStatus.shared
    @ObservedObject private var store = SettingsStore.shared
    @State private var historyCount = AskHistoryStore.shared.threads().count
    /// 侧栏有键盘焦点时 ↑↓ 换页（点一下侧栏、或 Tab 进来）；历史列表、输入框有焦点时 ↑↓ 归它们
    @FocusState private var sidebarFocused: Bool
    /// 按过 ↑↓ 才画焦点框；用鼠标点的人看不到这圈
    @State private var keyboardNavigating = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.border).frame(width: 0.5)
            VStack(spacing: 0) {
                header
                Hairline()
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
        }
        .frame(minWidth: 860, minHeight: 580)
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .askFreeHistoryDidChange)) { _ in
            historyCount = AskHistoryStore.shared.threads().count
        }
        .sheet(isPresented: $model.asksUsageConsent) {
            UsageConsentSheet { agree in
                store.setUsageConsent(agree: agree)
                model.asksUsageConsent = false
            }
        }
        // 别处答过了（比如引导里），不用再问
        .onChange(of: store.usageConsent) { _, now in if !now.needsAsking { model.asksUsageConsent = false } }
    }

    private var startTitle: String { MainPage.start.title(setupDone: status.allDone) }

    // MARK: 侧栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 40)   // 让过红绿灯
            sidebarRow(.start, title: startTitle, symbol: MainPage.start.symbol(setupDone: status.allDone))
            sidebarRow(.history, trailing: historyCount > 0 ? "\(historyCount)" : nil)
            Text("设置").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3)
                .padding(.leading, 10).padding(.top, 14).padding(.bottom, 4)
            ForEach(MainPage.settings) { sidebarRow($0) }
            Spacer(minLength: 12)
            statusCard
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($sidebarFocused)
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.downArrow) { step(1); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("侧栏")
        .onAppear { if model.page != .history { sidebarFocused = true } }
    }

    /// 侧栏 ↑↓：按侧栏顺序换到上一页 / 下一页，到头不绕回
    private func step(_ delta: Int) {
        keyboardNavigating = true
        model.page = model.page.stepped(by: delta)
        model.arrivedByArrowKey = true
    }

    private func sidebarRow(_ page: MainPage, title: String? = nil, symbol: String? = nil, trailing: String? = nil) -> some View {
        let selected = model.page == page
        return Button { model.page = page; sidebarFocused = true; keyboardNavigating = false } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol ?? page.symbol).font(.system(size: 13))
                    .foregroundStyle(selected ? Theme.text : Theme.text2)
                    .frame(width: 18)
                Text(title ?? page.title).font(.system(size: 13)).foregroundStyle(Theme.text)
                Spacer()
                if needsAttention(page) {
                    Circle().fill(Theme.warn).frame(width: 6, height: 6)
                } else if let trailing {
                    Text(trailing).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(selected ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
            // 侧栏有键盘焦点时，选中那行加一圈墨黑焦点框：看得出 ↑↓ 现在换的是页
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.ink.opacity(selected && sidebarFocused && keyboardNavigating ? 0.5 : 0), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title ?? page.title)
        .accessibilityValue(needsAttention(page) ? "还没设置好" : (trailing.map { "\($0) 条" } ?? ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func needsAttention(_ page: MainPage) -> Bool { status.checklist.needsAttention(page) }

    /// 还差几步 / 一切就绪：和「开始」三步、菜单栏第一行说同一件事
    private var statusCard: some View {
        Button { model.page = .start } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle().fill(status.allDone ? Theme.ok : Theme.warn).frame(width: 7, height: 7)
                    Text(status.checklist.statusTitle)
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
                }
                Text(status.allDone ? status.providerSummary : status.checklist.missingSummary)
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 页头和内容

    private var header: some View {
        HStack {
            Text(model.page == .start ? startTitle : model.page.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            if model.page == .history {
                Text("\(historyCount) 条，只存在这台 Mac 上").font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
    }

    @ViewBuilder private var content: some View {
        switch model.page {
        case .history:
            // 用侧栏 ↑↓ 走到「历史」时焦点留在侧栏，不然下一下 ↓ 换的是历史里的那一条
            HistoryView(focusListOnAppear: !model.arrivedByArrowKey)
        default:
            ScrollView {
                pageContent
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
            }
            .id(model.page)
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch model.page {
        case .start: StartPage(model: model)
        case .history: EmptyView()
        case .hotkeys: HotkeysPage()
        case .models: ModelsPage()
        case .answer: AnswerPage()
        case .recording: RecordingPage()
        case .permissions: PermissionsPage()
        case .general: GeneralPage()
        case .about: AboutPage()
        }
    }
}
