// ModelsPage.swift
// Ask Free
//
// 「语音与模型」：顶上一条「你说的话 → 听成文字 → 回答 → 右上角」的链路，填好的那家打勾；
// 下面「听懂你说的话」「回答你的问题」两组单选，只展开选中的那家：Key、验证、去哪拿 Key、版本或模型。

import SwiftUI
#if canImport(AskFreeCore)
import AskFreeCore
#endif

struct ModelsPage: View {
    @StateObject private var settings = ModelSettings()
    @ObservedObject private var status = SetupStatus.shared
    @State private var autoHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Stage(height: 150) { chain }
            SettingsGroup(title: "① 听懂你说的话") {
                asrRow(.volcano, detail: "每个识别版本送 20 小时，最稳", recommended: true)
                if settings.showsBailianASR {
                    Hairline()
                    asrRow(.bailian, detail: "和回答用的通义千问共用一个 Key；送 10 小时，用完自动扣费", recommended: false)
                }
            }
            SettingsGroup(title: "② 回答你的问题") {
                askRow("deepseek", detail: "最快，约 1 秒出字；要新消息时自己联网", recommended: true)
                Hairline()
                askRow("qwen", detail: "自带联网搜索；每个模型送 100 万 Token", recommended: false)
                if settings.showsDoubao {
                    Hairline()
                    askRow("doubao", detail: "不能联网，建议换上面两家", recommended: false)
                }
            }
        }
        .onDisappear { settings.saveKeys() }
    }

    // MARK: 链路示意

    private var chain: some View {
        HStack(spacing: 0) {
            node(symbol: "mic", title: "你说的话", subtitle: nil, done: false)
            arrow
            node(symbol: "waveform", title: "听成文字", subtitle: settings.asr == .bailian ? "阿里百炼" : "火山引擎", done: status.asrReady && settings.asrKeyFilled)
            arrow
            node(symbol: "sparkles", title: "回答", subtitle: askShortName, done: status.askReady && settings.askKeyFilled)
            arrow
            node(symbol: "rectangle.inset.topright.filled", title: "显示在右上角", subtitle: nil, done: false)
        }
        .padding(.horizontal, 24)
    }

    private var askShortName: String {
        switch settings.ask {
        case "deepseek": return "DeepSeek"
        case "doubao": return "豆包"
        default: return "通义千问"
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.text3)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 26)
    }

    private func node(symbol: String, title: String, subtitle: String?, done: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    if done {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Theme.ok)
                            .background(Circle().fill(Theme.surface)).offset(x: 5, y: -5)
                    }
                }
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
            Text(subtitle ?? " ").font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
        .fixedSize()
    }

    // MARK: 听

    private func asrRow(_ choice: ModelSettings.ASRChoice, detail: String, recommended: Bool) -> some View {
        let on = settings.asr == choice
        return VStack(alignment: .leading, spacing: 0) {
            providerHeader(on: on, title: ModelSettings.asrName(choice), detail: detail, recommended: recommended) {
                settings.selectASR(choice)
            }
            if on {
                VStack(alignment: .leading, spacing: 12) {
                    KeyField(label: "API Key", key: settings.keyBinding(forASR: choice), test: settings.asrTest,
                             console: ModelSettings.asrConsole(choice), onTest: settings.testASR, onCommit: { settings.saveKeys() })
                    if choice == .volcano {
                        fieldRow("识别版本") {
                            MiniSegmented(options: [(CloudASRTranscriber.ASRVersion.turbo, "极速版"), (.standard, "标准版"), (.v2, "2.0")],
                                          selection: Binding(get: { settings.asrVersion }, set: { settings.selectASRVersion($0) }))
                            Text("各送 20 小时，用完换下一个").font(.system(size: 12)).foregroundStyle(Theme.text3)
                        }
                    } else {
                        fieldRow("模型") {
                            Text("qwen3-asr-flash，5 分钟以内的音频").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                    }
                }
                .padding(.leading, 70).padding(.trailing, 16).padding(.bottom, 16)
            }
        }
    }

    // MARK: 答

    private func askRow(_ provider: String, detail: String, recommended: Bool) -> some View {
        let on = settings.ask == provider
        return VStack(alignment: .leading, spacing: 0) {
            providerHeader(on: on, title: ModelSettings.askName(provider), detail: detail, recommended: recommended) {
                settings.selectAsk(provider)
            }
            if on {
                VStack(alignment: .leading, spacing: 12) {
                    if provider == "qwen" && settings.askSharesASRKey {
                        fieldRow("API Key") {
                            StatusText(text: "用上面那个 Key（同一个阿里 Key 通用）")
                            Spacer()
                            testButton
                        }
                        if case .failed(let message) = settings.askTest { StatusText(text: message, kind: .danger) }
                    } else {
                        KeyField(label: "API Key", key: settings.keyBinding(forAsk: provider), test: settings.askTest,
                                 console: ModelSettings.askConsole(provider), onTest: settings.testAsk, onCommit: { settings.saveKeys() })
                    }
                    modelPicker(provider)
                }
                .padding(.leading, 70).padding(.trailing, 16).padding(.bottom, 16)
            }
        }
    }

    private var testButton: some View {
        Button(settings.askTest == .testing ? "验证中…" : "验证", action: settings.testAsk)
            .buttonStyle(SecondaryButtonStyle(height: 24))
            .disabled(settings.askTest == .testing)
    }

    @ViewBuilder private func modelPicker(_ provider: String) -> some View {
        switch provider {
        case "deepseek":
            fieldRow("模型") {
                MiniSegmented(options: [(DeepSeekEndpoint.defaultModel, DeepSeekEndpoint.defaultModel), ("deepseek-v4-pro", "deepseek-v4-pro")],
                              selection: Binding(get: { settings.deepseekModel }, set: { settings.selectDeepseekModel($0) }))
                Text(settings.deepseekModel == DeepSeekEndpoint.defaultModel ? "快，看屏幕问也用它" : "质量更好，慢一些")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
        case "doubao":
            fieldRow("模型") {
                MiniSegmented(options: [("doubao-seed-2-0-pro-260215", "seed-2.0-pro"), ("doubao-seed-1-6-flash-250828", "seed-1.6-flash")],
                              selection: Binding(get: { settings.doubaoModel }, set: { settings.selectDoubaoModel($0) }))
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                fieldRow("模型") {
                    Picker("", selection: Binding(get: { settings.qwenModel }, set: { settings.selectQwenModel($0) })) {
                        ForEach(settings.qwenModelOptions, id: \.value) { Text($0.title).tag($0.value) }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                if let line = settings.qwenStatus {
                    Text(line.text).font(.system(size: 12)).foregroundStyle(line.warn ? Theme.danger : Theme.text2)
                        .padding(.leading, 76)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureLine(title: "自动是怎么换的", expanded: $autoHelp) {
                    Text("两种自动模式都会在某个模型免费额度用完时自动换下一个：质量优先从 3.7-plus 往下用；速度优先从 3.7-flash 开始，出字更快。建议在百炼控制台打开「免费额度用完即停」，额度用完 Ask Free 才知道该换。")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 76)
            }
        }
    }

    // MARK: 小件

    private func providerHeader(on: Bool, title: String, detail: String, recommended: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 12) {
                RadioDot(on: on)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                        if recommended { Tag(text: "推荐") }
                    }
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 64, alignment: .leading)
            content()
        }
    }
}

/// Key 输入框 + 验证按钮 + 结果 + 去哪拿 Key。设置页和欢迎引导共用
struct KeyField: View {
    let label: String
    @Binding var key: String
    let test: ModelSettings.TestState
    let console: (host: String, url: String)
    var testTitle = "验证"
    var labelOnTop = false
    var placeholder = "粘贴 API Key"
    let onTest: () -> Void
    let onCommit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if labelOnTop {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
            }
            HStack(spacing: 12) {
                if !labelOnTop {
                    Text(label).font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 64, alignment: .leading)
                }
                SecureField(placeholder, text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? Theme.ink : Theme.borderStrong, lineWidth: focused ? 1.5 : 0.5))
                    .focused($focused)
                    .onSubmit(onCommit)
                    .onChange(of: focused) { _, now in if !now { onCommit() } }
                Button(test == .testing ? "\(testTitle)中…" : testTitle, action: onTest)
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .disabled(test == .testing || key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(alignment: .top) {
                Group {
                    switch test {
                    case .ok: StatusText(text: "能用，已存好")
                    case .failed(let message): StatusText(text: message, kind: .danger)
                    case .testing: StatusText(text: "正在连…", kind: .neutral)
                    case .idle: Text(" ").font(.system(size: 12))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                LinkText(title: "去 \(console.host) 拿 Key", url: console.url)
            }
            .padding(.leading, labelOnTop ? 0 : 76)
        }
    }
}
