// SettingsPages.swift
// Ask Free
//
// 侧栏「设置」下面的六页：快捷键、回答方式、录音、权限、通用、关于（语音与模型在 ModelsPage.swift）。
// 每页先一块示意，再是分组卡片；开关是方角的，一屏最多一个黑色实心按钮。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

// MARK: - 快捷键

struct HotkeysPage: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoStage(height: 190, keyTitle: store.hotkeys.screen == nil ? nil : store.hotkeys.screenTitle)
            SettingsGroup(title: "三种问法") {
                hotkeyRow(.screen, icon: "rectangle.on.rectangle", title: AskHotkey.screen.title,
                          detail: "按住说话，松开就问。按下那一刻指针指着哪，AI 就重点看哪。")
                Hairline(inset: 46)
                hotkeyRow(.plain, icon: "mic", title: AskHotkey.plain.title,
                          detail: "不截屏，更快；屏幕上的东西不会发出去。")
                Hairline(inset: 46)
                hotkeyRow(.typeAsk, icon: "keyboard", title: TypeAskHotkey.title,
                          detail: "双击一颗键，截下此刻的屏幕，弹出输入框，回车发送。")
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "说话时还能这样")
                GestureHints()
                Text("Ask Free 不带默认键：每台键盘不一样，选一个你顺手的。轻点一下也能问：点一下开始说，再点一下结束。")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.leading, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hotkeyRow(_ kind: HotkeyButton.Kind, icon: String, title: String, detail: String) -> some View {
        let conflict: String? = {
            switch kind {
            case .screen: return store.hotkeys.screenConflict
            case .plain: return store.hotkeys.plainConflict
            case .typeAsk: return store.typeAsk.conflict
            }
        }()
        return SettingsRow(title: title, detail: conflict.map { "\($0)，现在不会响应" } ?? detail,
                           detailColor: conflict == nil ? Theme.text2 : Theme.warn, icon: icon) {
            HotkeyButton(kind: kind)
        }
    }
}

// MARK: - 回答方式

struct AnswerPage: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var screenshot = AskSettings.isScreenshotEnabled
    @State private var advanced = false
    @State private var visionModel = AskFreeConfig.shared.string(forKey: AskSettings.visionModelKey) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Stage(height: 190) { preview }
            SettingsGroup(title: "回答前") {
                toggleRow("让 AI 看屏幕", "提问时把指针附近那块屏幕一起发给 AI，也存进本机历史；关掉就只发你说的话。",
                          isOn: Binding(get: { screenshot }, set: { on in
                              screenshot = on
                              AskFreeConfig.shared.save(bool: on, forKey: AskSettings.screenshotEnabledKey)
                              SetupStatus.shared.refresh()
                          }))
                Hairline()
                toggleRow("联网的回答附上图", "要联网查的问题，回答下面附 3 张相关的图，点一张看原图。找图时只把一个搜索词发给 DuckDuckGo，不发截图和录音。",
                          isOn: Binding(get: { store.askImagesEnabled }, set: { store.setAskImagesEnabled($0) }))
                Hairline()
                toggleRow("先想一想再答", "看图推理、要计算的难题答得更准，每问多等 1 到 3 秒。联网查的那一问不受影响。",
                          isOn: Binding(get: { store.askThinkingEnabled }, set: { store.setAskThinkingEnabled($0) }))
                Hairline()
                SettingsRow(title: "想多久",
                            detail: store.askThinkingEnabled
                                ? "最多等它想 8 / 15 / 30 秒，到点还没答就先给一个快答案。"
                                : "打开「先想一想再答」后才用得上。") {
                    MiniSegmented(options: AskThinkingEffort.allCases.map { ($0, $0.displayName) },
                                  selection: Binding(get: { store.askThinkingEffort }, set: { store.setAskThinkingEffort($0) }),
                                  disabled: !store.askThinkingEnabled)
                }
            }
            DisclosureLine(title: "高级", expanded: $advanced) {
                SettingsGroup(footer: "看屏幕问时自动换成同一家能读图的模型；免费额度用完会降到同一家的下一个。官方换代时可以自己填新名字，只对填写时选的那一家生效。") {
                    SettingsRow(title: "读图模型", detail: "留空就用默认的") {
                        TextField("留空 = 默认", text: $visionModel)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 220)
                            .onSubmit(saveVisionModel)
                            .onDisappear(perform: saveVisionModel)
                    }
                }
            }
        }
    }

    private func saveVisionModel() {
        let config = AskFreeConfig.shared
        let value = visionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != (config.string(forKey: AskSettings.visionModelKey) ?? "") else { return }
        config.save(value: value, forKey: AskSettings.visionModelKey)
        // 记下填的时候用的是哪一家，换了服务商就不把这个模型名发给别家
        let provider = config.string(forKey: "ask_provider") ?? "qwen"
        config.save(value: ["qwen", "deepseek", "zhipu", "doubao"].contains(provider) ? provider : "",
                    forKey: AskSettings.visionModelProviderKey)
    }

    private func toggleRow(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(title: title, detail: detail) {
            Toggle(title, isOn: isOn).toggleStyle(.square)
        }
    }

    /// 回答面板的样子，跟着上面的开关变：看屏幕时带截图，附图时下面一排图
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "cursorarrow.rays").font(.system(size: 9))
                Text(store.askThinkingEnabled ? "Ask Free · 想了 2 秒" : "Ask Free").font(.system(size: 10))
            }
            .foregroundStyle(Color(white: 0.55))
            HStack(alignment: .top, spacing: 10) {
                if screenshot {
                    RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.93))
                        .frame(width: 70, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.15)).frame(width: 40, height: 14))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.marker, lineWidth: 1).frame(width: 48, height: 22))
                }
                Text("这个按钮的阴影是怎么做的？").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.1))
            }
            Text("一层投影：向下 4、模糊 12、黑色 8% 透明度。").font(.system(size: 12)).foregroundStyle(Color(white: 0.2))
            if store.askImagesEnabled {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [[Color(red: 0.72, green: 0.76, blue: 0.88), Color(red: 0.85, green: 0.74, blue: 0.62),
                                                           Color(red: 0.70, green: 0.84, blue: 0.74)][i], Color(white: 0.6)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 34)
                    }
                }
            }
        }
        .padding(13)
        .frame(width: 320, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
        .animation(.easeOut(duration: 0.2), value: screenshot)
        .animation(.easeOut(duration: 0.2), value: store.askImagesEnabled)
    }
}

// MARK: - 录音

struct RecordingPage: View {
    @State private var style = OverlayStyle.current
    @State private var buttons = OverlayControlsMode.current == .buttons
    @State private var micName = MicrophoneManager.shared.displayName()
    @State private var picker: MicrophonePickerSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Stage(height: 130) {
                OverlayPreview(mono: style == .mono).frame(width: 220, height: 64)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "录音时屏幕底部的浮窗")
                HStack(spacing: 10) {
                    styleCard(.colorful, title: "彩色")
                    styleCard(.mono, title: "墨黑")
                }
                SettingsGroup {
                    SettingsRow(title: "两边显示取消和完成", detail: "点 ✕ 不问了，点 ✓ 说完就问；关掉就是一整条声波。下次录音生效。") {
                        Toggle("两边显示取消和完成", isOn: Binding(get: { buttons }, set: { on in
                            buttons = on
                            UserDefaults.standard.set((on ? OverlayControlsMode.buttons : .classic).rawValue,
                                                      forKey: OverlayControlsMode.userDefaultsKey)
                        })).toggleStyle(.square)
                    }
                }
            }
            SettingsGroup(title: "麦克风") {
                SettingsRow(title: micName, detail: "没声音时换一个试试；换的窗口里对着它说话，格子会跳。", icon: "mic") {
                    Button("换一个", action: openPicker).buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .askFreeMicrophoneSelectionDidChange)) { _ in
            micName = MicrophoneManager.shared.displayName()
        }
        .onReceive(NotificationCenter.default.publisher(for: .askFreeMicrophoneListDidChange)) { _ in
            micName = MicrophoneManager.shared.displayName()
        }
    }

    private func styleCard(_ value: OverlayStyle, title: String) -> some View {
        ChoiceCard(selected: style == value) {
            style = value
            UserDefaults.standard.set(value.rawValue, forKey: OverlayStyle.userDefaultsKey)
        } content: {
            VStack(spacing: 8) {
                OverlayPreview(mono: value == .mono)
                    .frame(width: 160, height: 46)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
            }
        }
    }

    private func openPicker() {
        guard let window = SettingsWindowController.shared?.window else { return }
        let sheet = MicrophonePickerSheet(theme: VPTheme.automatic)
        picker = sheet
        sheet.present(over: window) {
            micName = MicrophoneManager.shared.displayName()
            picker = nil
        }
    }
}

/// 录音胶囊的静态样子（和真实浮窗同一份画法）
private struct OverlayPreview: NSViewRepresentable {
    let mono: Bool
    func makeNSView(context: Context) -> OverlayStylePreview { OverlayStylePreview(mono: mono) }
    func updateNSView(_ view: OverlayStylePreview, context: Context) {
        if view.mono != mono { view.mono = mono }
    }
}

// MARK: - 权限

/// 三项权限的行：做完写「已允许」，没做的给按钮。highlightNext 时下一项该做的按钮是黑的
struct PermissionRows: View {
    var compact = false
    var highlightNext = false
    @ObservedObject private var status = SetupStatus.shared

    private enum Kind: CaseIterable { case mic, accessibility, screen }

    var body: some View {
        VStack(spacing: compact ? 6 : 0) {
            ForEach(Array(Kind.allCases.enumerated()), id: \.offset) { i, kind in
                if !compact && i > 0 { Hairline() }
                row(kind)
            }
        }
    }

    private var next: Kind? { Kind.allCases.first { !done($0) } }

    private func done(_ kind: Kind) -> Bool {
        switch kind {
        case .mic: return status.micReady
        case .accessibility: return status.accessibility
        case .screen: return status.screenRecording
        }
    }

    @ViewBuilder private func row(_ kind: Kind) -> some View {
        let (title, detail, icon): (String, String, String) = {
            switch kind {
            case .mic: return ("麦克风", status.mic == .denied ? "拒绝过了：到系统设置里把 Ask Free 的开关打开。" : "录下你说的问题。系统会弹框问一次。", "mic")
            case .accessibility: return ("辅助功能", "按提问键时 Ask Free 才收得到；没开时按键没反应。", "hand.raised")
            case .screen:
                return ("屏幕录制", status.screenNeedsRelaunch
                        ? "已经允许了，重新打开 Ask Free 后才截得到屏幕。"
                        : "看屏幕问时截一张，存进本机历史；开完要重新打开 Ask Free。", "rectangle.dashed")
            }
        }()
        let content = HStack(spacing: 12) {
            if !compact {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(width: 18)
                    .accessibilityHidden(true)
            }
            if compact {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).frame(width: 64, alignment: .leading)
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if kind == .screen && status.screenNeedsRelaunch {
                Button("重新打开 Ask Free") { AppRelaunch.relaunch() }.buttonStyle(SecondaryButtonStyle())
            } else if done(kind) {
                StatusText(text: "已允许")
            } else {
                let title = kind == .mic && status.mic == .notDetermined ? "允许" : "打开系统设置"
                if highlightNext && next == kind {
                    Button(title) { request(kind) }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(title) { request(kind) }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        if compact {
            content.padding(.horizontal, 12).frame(height: 40)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.5))
        } else {
            content.padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 52)
        }
    }

    private func request(_ kind: Kind) {
        switch kind {
        case .mic: status.requestMicrophone()
        case .accessibility: status.requestAccessibility()
        case .screen: status.requestScreenRecording()
        }
    }
}

/// 系统设置示意：右边浮出 Ask Free 图标，往左拖进列表。「减少动态效果」打开时停在拖之前那一帧
struct DragToGrantIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4)
            let k = t < 0.8 ? 0 : min(1, (t - 0.8) / 1.4)
            let drag = k * k * (3 - 2 * k)
            let landed = t > 2.3
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("系统设置 › 隐私与安全性").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(white: 0.2))
                            .padding(.horizontal, 10).frame(height: 24)
                        Rectangle().fill(Color.black.opacity(0.06)).frame(height: 0.5)
                        listRow(color: Color(red: 0.95, green: 0.42, blue: 0.4), name: "Raycast", on: true)
                        listRow(color: Color(white: 0.25), name: "终端", on: true)
                        if landed { listRow(color: .white, name: "Ask Free", on: true, icon: true) }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 250, height: 104, alignment: .topLeading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color(white: 0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: 44, height: 44)
                        .opacity(landed ? 0 : 1)
                    AppIconView(size: 30)
                        .offset(x: -drag * 150, y: drag * 18)
                        .opacity(landed ? 0 : 1)
                }
                .frame(width: 60)
                .padding(.leading, 6)
                Text("把图标往左拖进列表").font(.system(size: 11.5)).foregroundStyle(Theme.text2).padding(.leading, 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("示意：系统设置打开后，把右边浮出的 Ask Free 图标往左拖进列表")
        .accessibilityAddTraits(.isImage)
    }

    private func listRow(color: Color, name: String, on: Bool, icon: Bool = false) -> some View {
        HStack(spacing: 7) {
            if icon { AppIconView(size: 14) } else { RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12) }
            Text(name).font(.system(size: 10.5)).foregroundStyle(Color(white: 0.2))
            Spacer()
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.12)).frame(width: 24, height: 13)
                .overlay(alignment: .trailing) { RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 10, height: 10).padding(1.5) }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
    }
}

struct PermissionsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Stage(height: 150) { DragToGrantIllustration() }
            SettingsGroup(footer: "辅助功能和屏幕录制：点「打开系统设置」后，系统设置右边会浮出 Ask Free 的图标，往左拖进列表就行。") {
                PermissionRows()
            }
        }
    }
}

// MARK: - 通用

struct GeneralPage: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var dock = DockIcon.isShown
    @State private var appearance = MainWindowAppearance.current
    @State private var hideFromShare = AskSettings.isHiddenFromScreenShare

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup {
                SettingsRow(title: "开机时自动启动", detail: "登录后在后台打开，不用每次自己开。") {
                    Toggle("开机时自动启动", isOn: Binding(get: { launchAtLogin }, set: { on in
                        // 以系统真实状态回填：注册失败时开关弹回去，不给人错觉
                        _ = LaunchAtLogin.setEnabled(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    })).toggleStyle(.square)
                }
                Hairline()
                SettingsRow(title: "在 Dock 里显示", detail: "关掉后只在菜单栏，点顶上的图标打开。") {
                    Toggle("在 Dock 里显示", isOn: Binding(get: { dock }, set: { on in
                        dock = on
                        DockIcon.setShown(on)
                        // 切激活策略时系统会把 App 挪到后台，把窗口拉回前面
                        DispatchQueue.main.async {
                            NSApp.activate(ignoringOtherApps: true)
                            SettingsWindowController.shared?.window?.makeKeyAndOrderFront(nil)
                        }
                    })).toggleStyle(.square)
                }
            }
            SettingsGroup(title: "隐私") {
                SettingsRow(title: "共享屏幕时隐藏回答面板",
                            detail: "开会共享屏幕、录屏或截图时，回答面板、打字框和录音浮窗不进画面，只有你自己看得见。") {
                    Toggle("共享屏幕时隐藏回答面板", isOn: Binding(get: { hideFromShare }, set: { on in
                        hideFromShare = on
                        ScreenShareHiding.setEnabled(on)
                    })).toggleStyle(.square)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "外观")
                HStack(spacing: 10) {
                    appearanceCard(.system, "跟随系统")
                    appearanceCard(.light, "浅色")
                    appearanceCard(.dark, "深色")
                }
                Text("主窗口和回答面板一起换。").font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.leading, 2)
            }
        }
    }

    private func appearanceCard(_ value: MainWindowAppearance, _ title: String) -> some View {
        ChoiceCard(selected: appearance == value) {
            appearance = value
            UserDefaults.standard.set(value.rawValue, forKey: MainWindowAppearance.userDefaultsKey)
            NotificationCenter.default.post(name: MainWindowAppearance.didChangeNotification, object: nil)
        } content: {
            VStack(spacing: 8) {
                thumbnail(value).frame(height: 62)
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
            }
        }
    }

    private func thumbnail(_ value: MainWindowAppearance) -> some View {
        let light = Color(white: 0.96), dark = Color(white: 0.13)
        return GeometryReader { geo in
            ZStack {
                switch value {
                case .system:
                    HStack(spacing: 0) { light; dark }
                case .light: light
                case .dark: dark
                }
                HStack(spacing: 0) {
                    (value == .dark ? Color(white: 0.2) : .white)
                    if value == .system { Color(white: 0.2) }
                }
                .frame(width: geo.size.width * 0.66, height: geo.size.height * 0.62)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 关于

struct AboutPage: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                AppIconView(size: 72)
                Text("Ask Free").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
                Text("按一个键说出问题，AI 看着你的屏幕回答。").font(.system(size: 13)).foregroundStyle(Theme.text2)
                HStack(spacing: 6) {
                    Tag(text: "版本 \(Bundle.main.appVersionString)")
                    Tag(text: "开源 · GPL-3.0")
                    Tag(text: "免费")
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            SettingsGroup {
                SettingsRow(title: "源码", detail: "在 GitHub 上，欢迎提问题和改进。") {
                    Button {
                        if let url = URL(string: AppLinks.sourceCodeURL) { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: 3) { Text("查看源码"); Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Hairline()
                SettingsRow(title: "你的数据", detail: "Key 在系统钥匙串里；问答、截图和找到的图只存在这台 Mac 上。") {
                    Button("在访达中打开") { NSWorkspace.shared.open(AppIdentity.configDirectory) }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Hairline()
                SettingsRow(title: "致谢", detail: "从 Typefree（kdsz001）的「问 AI」改出来，同样用 GPL-3.0。")
            }
        }
    }
}
