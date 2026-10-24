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

enum MainPage: String, CaseIterable, Identifiable {
    case start, history, hotkeys, models, answer, recording, permissions, general, about
    var id: String { rawValue }

    static let settings: [MainPage] = [.hotkeys, .models, .answer, .recording, .permissions, .general, .about]

    var title: String {
        switch self {
        case .start: return "开始"
        case .history: return "历史"
        case .hotkeys: return "快捷键"
        case .models: return "语音与模型"
        case .answer: return "回答方式"
        case .recording: return "录音"
        case .permissions: return "权限"
        case .general: return "通用"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .start: return "flag"
        case .history: return "clock"
        case .hotkeys: return "keyboard"
        case .models: return "waveform"
        case .answer: return "text.bubble"
        case .recording: return "mic"
        case .permissions: return "lock"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }

    /// 启动参数 -openPage 和菜单栏用的名字
    init?(argument: String) {
        switch argument.lowercased() {
        case "home", "start": self = .start
        case "model", "models": self = .models
        case "settings", "general": self = .general
        default:
            guard let page = MainPage(rawValue: argument.lowercased()) else { return nil }
            self = page
        }
    }
}

@MainActor
final class MainWindowModel: ObservableObject {
    @Published var page: MainPage = .start
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
        if !window.setFrameAutosaveName("AskFreeMainWindow2") { window.center() }
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
    @State private var historyCount = AskHistoryStore.shared.threads().count

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
    }

    private var startTitle: String { status.allDone ? "首页" : "开始" }

    // MARK: 侧栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 40)   // 让过红绿灯
            sidebarRow(.start, title: startTitle, symbol: status.allDone ? "house" : "flag")
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
    }

    private func sidebarRow(_ page: MainPage, title: String? = nil, symbol: String? = nil, trailing: String? = nil) -> some View {
        let selected = model.page == page
        return Button { model.page = page } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func needsAttention(_ page: MainPage) -> Bool {
        switch page {
        case .start: return !status.allDone
        case .hotkeys: return !status.screenHotkeySet
        case .models: return !status.keysReady
        case .permissions: return !status.permissionsReady
        default: return false
        }
    }

    /// 还差几步 / 一切就绪：和「开始」三步、菜单栏第一行说同一件事
    private var statusCard: some View {
        Button { model.page = .start } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle().fill(status.allDone ? Theme.ok : Theme.warn).frame(width: 7, height: 7)
                    Text(status.allDone ? "一切就绪" : "还差 \(status.missing.count) 步")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
                }
                Text(status.allDone ? status.providerSummary : status.missing.map(\.shortTitle).joined(separator: "、"))
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
            HistoryView()
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
