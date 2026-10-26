// ModelSettings.swift
// Ask Free
//
// 两个 Key 的读写和测试连接：「语音与模型」页和欢迎引导第 3、4 步共用一份。
// 值仍存在 AskFreeConfig（Key 进钥匙串，开发版进 dev_secrets.json），键名和以前一样。

import SwiftUI
#if canImport(AskFreeCore)
import AskFreeCore
#endif

@MainActor
final class ModelSettings: ObservableObject {
    enum TestState: Equatable {
        case idle, testing, ok
        case failed(String)
    }

    enum ASRChoice: String { case volcano, bailian }

    private let config = AskFreeConfig.shared

    @Published var asr: ASRChoice
    @Published var asrVersion: CloudASRTranscriber.ASRVersion
    @Published var ask: String
    @Published var volcKey: String
    @Published var dashscopeKey: String
    @Published var deepseekKey: String
    @Published var arkKey: String
    @Published var qwenModel: String
    @Published var deepseekModel: String
    @Published var doubaoModel: String
    @Published var asrTest: TestState = .idle
    @Published var askTest: TestState = .idle

    /// 9-15 Ray：识别只留火山，百炼藏起来；已经在用百炼的老用户照样看得到、好切回来
    let showsBailianASR: Bool
    /// 豆包回答不能联网，默认藏着；手改配置选了豆包时才显示
    let showsDoubao: Bool

    init() {
        let version = CloudASRTranscriber().currentVersion()
        asr = version.provider == .bailian ? .bailian : .volcano
        asrVersion = version.provider == .bailian ? .turbo : version
        let provider = config.string(forKey: "ask_provider") ?? "qwen"
        ask = provider
        volcKey = config.string(forKey: "bigasr_api_key") ?? ""
        dashscopeKey = config.string(forKey: "dashscope_api_key") ?? ""
        deepseekKey = config.string(forKey: DeepSeekEndpoint.secretKey) ?? ""
        arkKey = config.string(forKey: "ark_api_key") ?? ""
        qwenModel = (config.string(forKey: "qwen_ask_model")).flatMap { $0.isEmpty ? nil : $0 } ?? QwenModelRouter.autoValue
        deepseekModel = (config.string(forKey: DeepSeekEndpoint.modelConfigKey)).flatMap { $0.isEmpty ? nil : $0 } ?? DeepSeekEndpoint.defaultModel
        doubaoModel = (config.string(forKey: "doubao_ask_model")).flatMap { $0.isEmpty ? nil : $0 } ?? "doubao-seed-2-0-pro-260215"
        showsBailianASR = version.provider == .bailian
        showsDoubao = provider == "doubao"
    }

    // MARK: 选

    func selectASR(_ choice: ASRChoice) {
        guard choice != asr else { return }
        asr = choice
        config.save(values: ["bigasr_version": choice == .bailian ? "bailian" : asrVersion.rawValue])
        asrTest = .idle
        changed()
    }

    func selectASRVersion(_ version: CloudASRTranscriber.ASRVersion) {
        asrVersion = version
        config.save(values: ["bigasr_version": version.rawValue])
        asrTest = .idle
        changed()
    }

    func selectAsk(_ provider: String) {
        guard provider != ask else { return }
        ask = provider
        config.save(value: provider, forKey: "ask_provider")
        askTest = .idle
        changed()
    }

    func selectQwenModel(_ value: String) {
        qwenModel = value
        config.save(value: value, forKey: "qwen_ask_model")
        askTest = .idle
    }

    func selectDeepseekModel(_ value: String) {
        deepseekModel = value
        config.save(value: value, forKey: DeepSeekEndpoint.modelConfigKey)
        askTest = .idle
    }

    func selectDoubaoModel(_ value: String) {
        doubaoModel = value
        config.save(value: value, forKey: "doubao_ask_model")
        askTest = .idle
    }

    /// 两边都选阿里时，回答那家直接用识别填的 DashScope Key
    var askSharesASRKey: Bool { ask == "qwen" && asr == .bailian }

    // MARK: Key

    /// 把四个框里的 Key 存下来（空串 = 删掉）。框失焦、回车、测试前都调
    @discardableResult
    func saveKeys() -> Bool {
        var ok = true
        for (value, key) in [(volcKey, "bigasr_api_key"), (dashscopeKey, "dashscope_api_key"),
                             (deepseekKey, DeepSeekEndpoint.secretKey), (arkKey, "ark_api_key")] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != (config.string(forKey: key) ?? "") else { continue }
            ok = config.saveSecret(trimmed, forKey: key) && ok
        }
        changed()
        return ok
    }

    /// 选中的那家框里有没有 Key。SetupStatus 的 askReady 会退到别家有 Key 的，链路打勾和自动测试只看选中的这家
    var asrKeyFilled: Bool { !keyBinding(forASR: asr).wrappedValue.isEmpty }
    var askKeyFilled: Bool { !keyBinding(forAsk: ask).wrappedValue.isEmpty }

    func keyBinding(forASR choice: ASRChoice) -> Binding<String> {
        choice == .bailian ? binding(\.dashscopeKey) : binding(\.volcKey)
    }

    func keyBinding(forAsk provider: String) -> Binding<String> {
        switch provider {
        case "deepseek": return binding(\.deepseekKey)
        case "doubao": return binding(\.arkKey)
        default: return binding(\.dashscopeKey)
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<ModelSettings, String>) -> Binding<String> {
        Binding(get: { self[keyPath: keyPath] }, set: { [weak self] value in
            guard let self, self[keyPath: keyPath] != value else { return }
            self[keyPath: keyPath] = value
            // 改了 Key，上次的测试结果就不作数了
            if keyPath == \ModelSettings.volcKey || (keyPath == \ModelSettings.dashscopeKey && self.asr == .bailian) { self.asrTest = .idle }
            if keyPath != \ModelSettings.volcKey { self.askTest = .idle }
        })
    }

    // MARK: 测试连接

    /// 识别：发 0.3 秒静音。服务端明确说「没听到声音」才算通（鉴权、开通、网络都没问题）
    func testASR() {
        guard saveKeys() else { asrTest = .failed("Key 没存进钥匙串，请再试一次"); return }
        asrTest = .testing
        let silence = [Float](repeating: 0, count: 4800)
        CloudASRTranscriber().transcribe(samples: silence, sampleRate: 16000) { result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .success:
                        self.asrTest = .ok
                    case .failure(let error):
                        if case CloudASRTranscriber.TranscriptionError.noSpeech? = error as? CloudASRTranscriber.TranscriptionError {
                            self.asrTest = .ok
                        } else {
                            self.asrTest = .failed(Self.shortError(error))
                        }
                    }
                }
            }
        }
    }

    func testAsk() {
        guard saveKeys() else { askTest = .failed("Key 没存进钥匙串，请再试一次"); return }
        askTest = .testing
        AskAI().answer(question: "只回复 OK 两个字母") { result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .success: self.askTest = .ok
                    case .failure(let error): self.askTest = .failed(Self.shortError(error))
                    }
                }
            }
        }
    }

    private func changed() {
        NotificationCenter.default.post(name: .askFreeModelSettingsDidChange, object: nil)
    }

    static func shortError(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return message.count > 60 ? String(message.prefix(60)) + "…" : message
    }

    // MARK: 说明文字

    static func asrName(_ choice: ASRChoice) -> String { choice == .bailian ? "阿里百炼" : "火山引擎（豆包）" }

    static func askName(_ provider: String) -> String {
        switch provider {
        case "deepseek": return "DeepSeek"
        case "doubao": return "火山引擎（豆包）"
        default: return "阿里百炼（千问）"
        }
    }

    static func asrConsole(_ choice: ASRChoice) -> (host: String, url: String) {
        choice == .bailian ? ("bailian.console.aliyun.com", "https://bailian.console.aliyun.com/")
            : ("console.volcengine.com", "https://console.volcengine.com/speech/app")
    }

    static func askConsole(_ provider: String) -> (host: String, url: String) {
        switch provider {
        case "deepseek": return ("platform.deepseek.com", DeepSeekEndpoint.consoleURL)
        case "doubao": return ("console.volcengine.com", "https://console.volcengine.com/ark")
        default: return ("bailian.console.aliyun.com", "https://bailian.console.aliyun.com/")
        }
    }

    /// 千问模型下拉：自动两档在前；9-15 Ray 隐藏的三档正选着时照样列出
    var qwenModelOptions: [(value: String, title: String)] {
        let all: [(String, String)] = [
            (QwenModelRouter.autoValue, "自动 · 质量优先"),
            (QwenModelRouter.autoSpeedValue, "自动 · 速度优先"),
            ("qwen3.8-max", "qwen3.8-max · 质量最好"),
            ("qwen3.7-max", "qwen3.7-max · 质量好"),
            ("qwen3.7-flash", "qwen3.7-flash · 快"),
            ("qwen3.7-plus", "qwen3.7-plus · 均衡"),
            ("qwen3.6-flash", "qwen3.6-flash · 最快"),
        ]
        let hidden: Set<String> = ["qwen3.8-max", "qwen3.7-max", "qwen3.6-flash"]
        var options = all.filter { !hidden.contains($0.0) || $0.0 == qwenModel }.map { (value: $0.0, title: $0.1) }
        if !options.contains(where: { $0.value == qwenModel }) { options.append((qwenModel, "自定义：\(qwenModel)")) }
        return options.map { option in
            let exhausted = !QwenModelRouter.isAuto(option.value) && QwenModelRouter.isExhausted(option.value)
            return (option.value, exhausted ? option.title + "（当前不可用）" : option.title)
        }
    }

    /// 自动模式下现在在用哪个；手选的那个额度用完时说清楚
    var qwenStatus: (text: String, warn: Bool)? {
        if QwenModelRouter.isAuto(qwenModel) {
            guard let inUse = QwenModelRouter.candidates(for: qwenModel).first else { return nil }
            let skipped = QwenModelRouter.qualityChain.filter { QwenModelRouter.isExhausted($0) }.count
            return ("现在在用 \(inUse)" + (skipped > 0 ? "，已跳过 \(skipped) 个不可用的" : ""), false)
        }
        guard QwenModelRouter.isExhausted(qwenModel) else { return nil }
        return ("这个模型现在用不了（免费额度用完，或这个 Key 没开通它），改用「自动 · 质量优先」会自动换到能用的。", true)
    }
}
