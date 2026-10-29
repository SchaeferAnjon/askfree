// Onboarding.swift
// Ask Free
//
// 欢迎引导（design/onboarding 方向 A「侧栏步骤」）：一个窗口，左边步骤清单，右边一屏一件事。
// 欢迎 → 授权 → 用法（会员 / 自带 Key）→ [自带 Key：语音识别 → 问答模型] → 提问键 → 匿名统计（同意 / 不用了）→ 试问一次。
// 选会员（默认）不用填 Key，少两步。和 GetNewWord 的欢迎页同一副骨架。
// 进度和主窗口「开始」三步读同一份（SetupStatus）：在哪做完，另一边一起打勾。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static var shared: OnboardingWindowController?

    /// 第一次打开、或菜单里点「继续设置…」：停在上次没做完的那一步
    static func show() {
        let controller = shared ?? OnboardingWindowController()
        shared = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 「通用 → 再走一遍引导」：从欢迎页重新开始。引导已经开着就先关掉，新开的一份从第一步起
    static func restart() {
        shared?.close()
        OnboardingProgress.step = 0
        show()
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 Ask Free"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let host = NSHostingView(rootView: OnboardingView(onFinish: { [weak self] in self?.finish() }))
        host.sizingOptions = []
        window.contentView = host
        window.center()
        window.appearance = MainWindowAppearance.resolve()
        SetupStatus.shared.beginWatching()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func finish() {
        OnboardingProgress.isCompleted = true
        close()
        (NSApp.delegate as? AppDelegate)?.statusBar.showWhereIAm()
    }

    func windowWillClose(_ notification: Notification) {
        // 中途关掉也算看过：之后启动不再自动弹，菜单栏图标挂橙点，菜单里「继续设置…」回来
        OnboardingProgress.isCompleted = true
        PermissionDragHelper.shared.hide()
        SetupStatus.shared.endWatching()
        Self.shared = nil
        // 没答匿名使用统计那一步就关了引导、主窗口又开着：在主窗口上问
        SettingsWindowController.shared?.askUsageConsentIfNeeded()
    }
}

/// 引导的每一步。选会员时没有「语音识别」「问答模型」两步（不用填 Key）
enum OnboardingStep: String {
    case welcome, permissions, usage, asr, ask, hotkey, consent, tryAsk

    var title: String {
        switch self {
        case .welcome: return "欢迎"
        case .permissions: return "授权"
        case .usage: return "用法"
        case .asr: return "语音识别"
        case .ask: return "问答模型"
        case .hotkey: return "提问键"
        case .consent: return "匿名统计"
        case .tryAsk: return "试问一次"
        }
    }

    var note: String {
        switch self {
        case .welcome: return "看一眼怎么用"
        case .permissions: return "麦克风、辅助功能、屏幕录制"
        case .usage: return "会员或自带 Key"
        case .asr, .ask: return "填一个 Key"
        case .hotkey: return "自己选一个"
        case .consent: return "同意或不用了"
        case .tryAsk: return "确认都通了"
        }
    }

    /// 「用法」那一步之前的几步两种用法一样，所以存的下标在换用法时不会跳
    static func all(_ mode: UsageMode) -> [OnboardingStep] {
        mode == .member ? [.welcome, .permissions, .usage, .hotkey, .consent, .tryAsk]
            : [.welcome, .permissions, .usage, .asr, .ask, .hotkey, .consent, .tryAsk]
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @StateObject private var models = ModelSettings()
    @ObservedObject private var status = SetupStatus.shared
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var member = MemberClient.shared
    @State private var mode = UsageMode.current()
    @State private var step = min(OnboardingProgress.step, Self.lastStep)
    @State private var moreASR = false
    @State private var moreAsk = false
    @State private var moreKeys = false

    private var steps: [OnboardingStep] { OnboardingStep.all(mode) }
    private var current: OnboardingStep { steps[min(step, steps.count - 1)] }
    /// 最后一步（试问一次）的下标，跟着现在的用法
    static var lastStep: Int { OnboardingStep.all(UsageMode.current()).count - 1 }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.border).frame(width: 0.5)
            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        switch current {
                        case .welcome: welcome
                        case .permissions: permissions
                        case .usage: usageStep
                        case .asr: asrStep
                        case .ask: askStep
                        case .hotkey: hotkeyStep
                        case .consent: consentStep
                        case .tryAsk: TryAskStep()
                        }
                    }
                    .frame(maxWidth: 600, alignment: .leading)
                    .padding(.horizontal, 44)
                    .padding(.top, 44)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
                Hairline()
                footer.frame(height: 60).padding(.horizontal, 28)
            }
            .background(Theme.bg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear(perform: prepare)
        .onChange(of: step) { _, now in OnboardingProgress.step = now }
    }

    /// 还没填过回答的 Key：推荐的 DeepSeek 先选好
    private func prepare() {
        if !status.askReady && models.ask != "deepseek" { models.selectAsk("deepseek") }
    }

    // MARK: 侧栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppIconView(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask Free").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("第一次设置").font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 22)
            VStack(spacing: 2) {
                ForEach(steps.indices, id: \.self) { stepRow($0) }
            }
            Spacer()
            Button("跳过，之后点菜单栏图标继续") { OnboardingWindowController.shared?.close() }
                .buttonStyle(PlainTextButtonStyle(color: Theme.text3))
                .font(.system(size: 11.5))
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 48)
        .padding(.bottom, 18)
        .frame(width: 236)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }

    /// 每步按真实状态打勾
    private func isDone(_ i: Int) -> Bool {
        switch steps[i] {
        case .welcome: return step > 0
        case .permissions: return status.permissionsReady
        case .usage: return UsageMode.isChosen() && (mode == .own || member.status != nil)
        // 选中那家框里有 Key、没测出错就算填好（回来看时 Key 早就填过）；能不能「继续」仍要这一步测通
        case .asr: return status.asrReady && models.asrKeyFilled && [.idle, .ok].contains(models.asrTest)
        case .ask: return status.askReady && models.askKeyFilled && [.idle, .ok].contains(models.askTest)
        case .hotkey: return status.screenHotkeySet
        case .consent: return !store.usageConsent.needsAsking
        case .tryAsk: return false
        }
    }

    private func stepRow(_ i: Int) -> some View {
        let current = i == step
        let done = isDone(i) && !current
        return Button { go(i) } label: {
            HStack(spacing: 10) {
                ZStack {
                    if done {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.ok)
                    } else {
                        Circle().stroke(current ? Theme.text : Theme.borderStrong, lineWidth: 1.2)
                        Text("\(i + 1)").font(.system(size: 11, weight: current ? .semibold : .regular))
                            .foregroundStyle(current ? Theme.text : Theme.text2)
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)   // 勾的图标旁白会读成「已选中」；做没做完写在 accessibilityValue 里
                VStack(alignment: .leading, spacing: 1) {
                    Text(steps[i].title).font(.system(size: 13, weight: current ? .medium : .regular))
                        .foregroundStyle(current ? Theme.text : Theme.text2)
                    Text(steps[i].note).font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background {
                if current {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.elevated)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第 \(i + 1) 步，\(steps[i].title)，\(steps[i].note)")
        .accessibilityValue(done ? "已完成" : "")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    // MARK: 底栏

    private var footer: some View {
        HStack(spacing: 18) {
            Text(footerHint).font(.system(size: 12)).foregroundStyle(Theme.text3)
            Spacer()
            if step > 0 {
                Button("上一步") { go(step - 1) }.buttonStyle(PlainTextButtonStyle())
            }
            if step > 0 && ![.consent, .tryAsk].contains(current) && !canContinue {
                Button("先跳过") { go(step + 1) }.buttonStyle(PlainTextButtonStyle())
            }
            if current == .consent {
                // 两个一样的按钮代替「继续」：不替用户选，回车也不选
                UsageConsentButtons(current: store.usageConsent) { agree in
                    store.setUsageConsent(agree: agree)
                    go(step + 1)
                }
            } else {
                Button(nextTitle) { next() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!canContinue)
            }
        }
    }

    private var footerHint: String {
        switch current {
        case .permissions: return status.permissionsReady ? "三项都好了" : "还差 \(status.missingPermissions) 项"
        case .usage: return canContinue ? "" : (member.isRefreshing ? "正在连接会员服务器…" : "连上会员服务器就能继续")
        case .asr, .ask: return canContinue ? "" : "测试连接通过后就能继续"
        case .hotkey: return canContinue ? "" : "选好提问键就能继续"
        case .consent:
            switch store.usageConsent {
            case .yes: return "已选：\(UsageConsentCopy.agree)"
            case .no: return "已选：\(UsageConsentCopy.decline)"
            case .unasked: return ""
            }
        case .tryAsk: return "试不试都行，之后随时能问"
        default: return ""
        }
    }

    private var canContinue: Bool {
        switch current {
        case .permissions: return status.permissionsReady
        // 会员：先点「领取免费试用」注册这台电脑，领到（或名额发完、照实说了）再继续；自带 Key 下一步去填
        case .usage: return !member.isRefreshing
        case .asr: return models.asrTest == .ok
        case .ask: return models.askTest == .ok
        case .hotkey: return status.screenHotkeySet
        default: return true
        }
    }

    private var nextTitle: String {
        switch current {
        case .welcome: return "开始设置"
        case .usage where mode == .member && member.status == nil: return "领取免费试用"
        case .tryAsk: return "完成"
        default: return "继续"
        }
    }

    private func go(_ target: Int) {
        if [.asr, .ask].contains(current) { models.saveKeys() }
        // 走过「用法」这一步就算选了（默认的会员也记下来）
        if current == .usage, !UsageMode.isChosen() || UsageMode.current() != mode { UsageModeStore.set(mode, refresh: false) }
        PermissionDragHelper.shared.hide()
        withAnimation(.easeOut(duration: 0.2)) { step = max(0, min(steps.count - 1, target)) }
    }

    private func next() {
        if current == .tryAsk { onFinish(); return }
        // 会员还没注册：这一下是「领取免费试用」，领完留在这一步，把结果（领到几个、名额发完了）照实说
        if current == .usage, mode == .member, member.status == nil { join(); return }
        go(step + 1)
    }

    private func join() {
        UsageModeStore.set(.member, refresh: false)
        Task { await member.refresh() }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 1 欢迎

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            DemoStage(height: 190, showsKeyHint: false)
            header("按一个键说出问题，AI 看着屏幕回答",
                   "按下那一刻鼠标指在哪，AI 就重点看哪。接下来 \(steps.count - 1) 步，大约 \(mode == .member ? 2 : 3) 分钟。")
            HStack(alignment: .top, spacing: 10) {
                introCard("hand.raised", "授权三项", "麦克风点「允许」；另外两项把图标拖进系统设置。")
                introCard("sparkles", "选用法", "会员不用填 Key，前 100 位新用户免费问 30 个；也能用自己的 Key。")
                introCard("keyboard", "选键，试一次", "提问键由你选，然后真的问一句。")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(Theme.text3).accessibilityHidden(true)
                Text("自带 Key 时，语音和截图直接发给你选的服务商；用会员时经我们的服务器转给火山引擎和 DeepSeek，服务器不存这些内容。")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func introCard(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.text2).accessibilityHidden(true)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            }
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
    }

    // MARK: 2 授权

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("给 Ask Free 三项授权", "都在系统设置里完成，Ask Free 拿不到你的密码。按顺序点下面的按钮就行。")
            Stage(height: 132) { DragToGrantIllustration() }
            SettingsGroup { PermissionRows(highlightNext: true) }
            if status.screenRecording == false && status.accessibility && status.micReady {
                Text("屏幕录制拖进列表后，系统会请你退出并重新打开 Ask Free；重开后会回到这一步。")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
        }
    }

    // MARK: 3 用法

    private var usageStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("怎么用：会员，还是自带 Key",
                   "会员不用申请任何 Key，装好就能问；自带 Key 永久免费，费用直接付给服务商。以后在主窗口「会员」页随时能换。")
            UsageModeCards(mode: mode) { picked in
                mode = picked
                UsageModeStore.set(picked, refresh: false)
            }
            if mode == .member {
                VStack(alignment: .leading, spacing: 10) {
                    if let s = member.status {
                        let line = MemberSummary.line(s)
                        StatusText(text: MemberSummary.registration(member.registration, status: s) ?? "\(line.title) · \(line.detail)",
                                   kind: s.canUse ? .ok : .warn)
                        if !s.canUse {
                            Text("可以在主窗口「会员」页订阅，或者在上面改选「自带 Key」。")
                                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                    } else if member.isRefreshing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在领免费试用…").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                    } else if let e = member.error {
                        StatusText(text: e.message, kind: .danger)
                    }
                    Text(MemberCopy.deviceNote + MemberCopy.countingReason)
                        .font(.system(size: 12)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 4 语音识别

    private var asrStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("语音识别：把你说的话变成文字", "用你自己的 Key，声音直接发给服务商。")
            HStack(spacing: 10) {
                providerCard(selected: models.asr == .volcano, title: "火山引擎（豆包）", recommended: true,
                             detail: "识别最快最稳。每个识别版本送 20 小时免费额度，半年有效。") { models.selectASR(.volcano) }
                if models.showsBailianASR {
                    providerCard(selected: models.asr == .bailian, title: "阿里百炼", recommended: false,
                                 detail: "和千问问答共用一个 Key。送 10 小时，用完自动扣费。") { models.selectASR(.bailian) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            KeyField(label: "\(models.asr == .bailian ? "百炼" : "火山引擎") API Key", key: models.keyBinding(forASR: models.asr),
                     test: models.asrTest, console: ModelSettings.asrConsole(models.asr), testTitle: "测试连接", labelOnTop: true,
                     placeholder: "粘贴 \(models.asr == .bailian ? "百炼" : "火山引擎") 的 API Key",
                     onTest: models.testASR, onCommit: { models.saveKeys() })
            Text(models.asr == .bailian
                 ? "还没有 Key？打开百炼控制台，在「API-KEY」里新建一个，复制过来。"
                 : "还没有 Key？打开火山引擎语音控制台，新建一个应用，复制它的「API Key」。")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
            if models.asr == .volcano {
                DisclosureLine(title: "更多选项", expanded: $moreASR) {
                    HStack(spacing: 12) {
                        Text("识别版本").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        MiniSegmented(options: [(CloudASRTranscriber.ASRVersion.turbo, "极速版"), (.standard, "标准版"), (.v2, "2.0")],
                                      selection: Binding(get: { models.asrVersion }, set: { models.selectASRVersion($0) }))
                        Text("默认极速版就好").font(.system(size: 12)).foregroundStyle(Theme.text3)
                    }
                }
            }
        }
        .onAppear { autoTest(asr: true) }
    }

    // MARK: 4 问答模型

    private var askStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("问答模型：看着屏幕回答你", "回答你的问题。看屏幕问时，截图也直接发给它。")
            HStack(spacing: 10) {
                providerCard(selected: models.ask == "deepseek", title: "DeepSeek", recommended: true,
                             detail: "出字最快；要新消息时它自己联网查。") { models.selectAsk("deepseek") }
                providerCard(selected: models.ask == "qwen", title: "阿里百炼（千问）", recommended: false,
                             detail: "自带联网搜索；每个模型送 100 万 Token。") { models.selectAsk("qwen") }
            }
            .fixedSize(horizontal: false, vertical: true)
            if models.askSharesASRKey {
                HStack {
                    StatusText(text: "用上一步的百炼 Key，不用再填")
                    Spacer()
                    Button(models.askTest == .testing ? "测试中…" : "测试连接", action: models.testAsk)
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                }
                if case .failed(let message) = models.askTest { StatusText(text: message, kind: .danger) }
                if models.askTest == .ok { StatusText(text: "连接成功") }
            } else {
                KeyField(label: "\(models.ask == "qwen" ? "百炼" : "DeepSeek") API Key", key: models.keyBinding(forAsk: models.ask),
                         test: models.askTest, console: ModelSettings.askConsole(models.ask), testTitle: "测试连接", labelOnTop: true,
                         placeholder: "粘贴 \(models.ask == "qwen" ? "百炼" : "DeepSeek") 的 API Key",
                         onTest: models.testAsk, onCommit: { models.saveKeys() })
            }
            DisclosureLine(title: "更多选项", expanded: $moreAsk) {
                HStack(spacing: 12) {
                    Text("模型").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    if models.ask == "deepseek" {
                        MiniSegmented(options: [(DeepSeekEndpoint.defaultModel, DeepSeekEndpoint.defaultModel), ("deepseek-v4-pro", "deepseek-v4-pro")],
                                      selection: Binding(get: { models.deepseekModel }, set: { models.selectDeepseekModel($0) }))
                    } else {
                        Picker("", selection: Binding(get: { models.qwenModel }, set: { models.selectQwenModel($0) })) {
                            ForEach(models.qwenModelOptions, id: \.value) { Text($0.title).tag($0.value) }
                        }
                        .labelsHidden().frame(width: 220)
                    }
                    Text("默认的就是推荐的").font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
            }
        }
        .onAppear { autoTest(asr: false) }
    }

    /// 回来看这一步时 Key 已经填过：自己测一次，通了就能直接继续
    private func autoTest(asr: Bool) {
        if asr {
            if models.asrTest == .idle && models.asrKeyFilled { models.testASR() }
        } else {
            if models.askTest == .idle && models.askKeyFilled { models.testAsk() }
        }
    }

    private func providerCard(selected: Bool, title: String, recommended: Bool, detail: String, action: @escaping () -> Void) -> some View {
        ChoiceCard(selected: selected, action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    if recommended { Tag(text: "推荐", filled: true) }
                    Spacer()
                    RadioDot(on: selected)
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 5 提问键

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("选一个提问键", "Ask Free 不替你定键：每台键盘不一样。挑一个顺手、平时很少单独按的键。")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    Text("看屏幕问 AI").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    Tag(text: "必选")
                }
                Text("长按：按住说，松开就问。轻点：点一下开始说，再点一下结束。").font(.system(size: 12)).foregroundStyle(Theme.text2)
                HStack(spacing: 8) {
                    keyTile(.rightOption, cap: "右 ⌥", name: "右 Option")
                    keyTile(.rightCommand, cap: "右 ⌘", name: "右 Command")
                    keyTile(.fn, cap: "fn 🌐", name: "fn")
                    keyTile(.control, cap: "⌃ Control", name: "Control")
                    Button { HotkeyChooser.recordCustom(for: .screen) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "keyboard").font(.system(size: 14)).foregroundStyle(Theme.text2).frame(height: 24)
                            Text(customTitle ?? "按一下录一个键").font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).frame(height: 70)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(customTitle != nil ? Theme.ink : Theme.borderStrong,
                                                                         lineWidth: customTitle != nil ? 2 : 0.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(customTitle != nil ? .isSelected : [])
                }
                Text(hotkeyStatus).font(.system(size: 12)).foregroundStyle(store.hotkeys.screen == nil ? Theme.text3 : Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
            DisclosureLine(title: "再加两种问法（可选，之后在设置里也能加）", expanded: $moreKeys) {
                SettingsGroup {
                    SettingsRow(title: AskHotkey.plain.title, detail: "不截屏，更快", icon: "mic") { HotkeyButton(kind: .plain) }
                    Hairline(inset: 46)
                    SettingsRow(title: TypeAskHotkey.title, detail: "双击一颗键，打字问", icon: "keyboard") { HotkeyButton(kind: .typeAsk) }
                }
            }
        }
    }

    // MARK: 6 匿名统计

    /// 正文和主窗口的询问共用（UsageConsentBody）；两个按钮在底栏
    private var consentStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(UsageConsentCopy.title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            UsageConsentBody()
                .padding(16)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
        }
    }

    private var customTitle: String? {
        if case .custom(let custom)? = store.hotkeys.screen { return custom.displayName }
        return nil
    }

    private var hotkeyStatus: String {
        guard store.hotkeys.screen != nil else { return "还没选。选好后这里会说它好不好按、会不会和别的冲突。" }
        if case .modifier(.fn)? = store.hotkeys.screen {
            return "选了 fn：记得到「系统设置 → 键盘」把「按下 🌐 键时」改成「无操作」，不然每按一次会切输入法。"
        }
        return "好了：按住 \(store.hotkeys.screenTitle) 说话，松开就问。"
    }

    private func keyTile(_ modifier: RecordingHotkeyModifier, cap: String, name: String) -> some View {
        var selected = false
        if case .modifier(let m)? = store.hotkeys.screen { selected = m == modifier }
        return Button { HotkeyChooser.choose(modifier, for: .screen) } label: {
            VStack(spacing: 8) {
                KeyCap(key: cap, height: 24)
                Text(name).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 70)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.ink : Theme.borderStrong, lineWidth: selected ? 2 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 7 试问一次

/// 真的问一句：指着左边的图按提问键（或按住屏幕上的按钮）说话，回答出在右上角，下面三项打勾
struct TryAskStep: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var heard = false
    @State private var captured = false
    @State private var answered = false
    @State private var holding = false
    @State private var chartFrame: CGRect = .zero
    private let startedAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("试问一次").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
                Text("真的问一句，确认麦克风、截屏和 AI 都通了。回答会出现在屏幕右上角。")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            HStack(alignment: .top, spacing: 24) {
                chart
                    .background(GeometryReader { geo in
                        Color.clear.onAppear { chartFrame = geo.frame(in: .global) }
                            .onChange(of: geo.frame(in: .global)) { _, f in chartFrame = f }
                    })
                VStack(alignment: .leading, spacing: 12) {
                    instruction(1) { Text("把鼠标指到左边这张图上。") }
                    instruction(2) {
                        HStack(spacing: 4) {
                            Text("按住")
                            KeyCap(key: store.hotkeys.screen == nil ? "提问键" : store.hotkeys.screenTitle, height: 20)
                            Text("说：「哪个季度涨得最多？」")
                        }
                    }
                    instruction(3) { Text("说完松开。") }
                    HStack(spacing: 10) {
                        holdButton
                        Text("键盘按不了时用它").font(.system(size: 12)).foregroundStyle(Theme.text3)
                    }
                    .padding(.top, 4)
                }
            }
            Hairline()
            HStack(spacing: 20) {
                check("听到你说话", heard)
                check("截到你指的地方", captured)
                check("AI 回答了", answered)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .askFreeHistoryDidChange)) { _ in readLatest() }
    }

    private var chart: some View {
        let values: [(String, Double)] = [("一", 3.2), ("二", 4.1), ("三", 5.6), ("四", 5.2)]
        return VStack(alignment: .leading, spacing: 8) {
            Text("各季度营收（亿元）").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.15))
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(values, id: \.0) { q, v in
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", v)).font(.system(size: 10)).foregroundStyle(Color(white: 0.4))
                        RoundedRectangle(cornerRadius: 2).fill(q == "三" ? Color(white: 0.1) : Color(white: 0.6))
                            .frame(width: 40, height: CGFloat(v) * 17)
                        Text(q).font(.system(size: 10)).foregroundStyle(Color(white: 0.5))
                    }
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func instruction<Content: View>(_ n: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
                .frame(width: 20, height: 20).background(Theme.selected, in: Circle())
            content().font(.system(size: 13)).foregroundStyle(Theme.text)
        }
    }

    /// 按住说话、松开就问；截图的位置是左边那张图的中间
    private var holdButton: some View {
        HStack(spacing: 6) {
            Image(systemName: holding ? "waveform" : "mic").font(.system(size: 12))
            Text(holding ? "在听…松开就问" : "按住这里也能问").font(.system(size: 12.5, weight: .medium))
        }
        .foregroundStyle(holding ? Theme.onInk : Theme.text)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(holding ? Theme.ink : Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 0.5))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !holding else { return }
                holding = true
                guard let app = NSApp.delegate as? AppDelegate,
                      app.beginAskAtCursor(at: chartPointOnScreen(), trigger: "onboarding", captureScreen: true) else {
                    holding = false
                    return
                }
            }
            .onEnded { _ in
                guard holding else { return }
                holding = false
                (NSApp.delegate as? AppDelegate)?.stopRecordingAndAsk()
            })
    }

    /// 图中间在屏幕上的位置（Quartz 坐标，原点在主屏左上角）
    private func chartPointOnScreen() -> CGPoint {
        guard let window = OnboardingWindowController.shared?.window, let screen = NSScreen.screens.first else {
            return CGEvent(source: nil)?.location ?? .zero
        }
        let x = window.frame.minX + chartFrame.midX
        let cocoaY = window.frame.maxY - chartFrame.midY
        return CGPoint(x: x, y: screen.frame.maxY - cocoaY)
    }

    private func check(_ title: String, _ done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 13))
                .foregroundStyle(done ? Theme.ok : Theme.borderStrong)
            Text(title).font(.system(size: 12.5)).foregroundStyle(done ? Theme.text : Theme.text3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(done ? "通了" : "还没有")
    }

    /// 这一步打开后答完的第一题：问题有字就是听到了，存了截图就是截到了，回答有字就是答了
    private func readLatest() {
        guard let turn = AskHistoryStore.shared.threads().first?.turns.last, turn.at >= startedAt else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            heard = !turn.question.isEmpty
            captured = turn.hasScreenshot
            answered = !turn.answer.isEmpty
        }
    }
}
