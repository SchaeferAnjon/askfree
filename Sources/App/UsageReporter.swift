// UsageReporter.swift
// Ask Free
//
// 每天匿名报到一次（「通用 → 隐私 → 匿名使用统计」，照 MeetCaption 的 usagePing.js）：用户同意了才报，
// 没问过、不同意都不发。规则和发什么在 AskFreeCore 的 UsagePing（有单测）。
// 启动后过 5 秒看一眼，之后每小时看一眼（开着跨过午夜第二天也报）；刚点了「同意」马上看一眼。
// 只有正式版报：开发版、启动自测不报；测试时给开发版设 ASKFREE_API 指到本机假服务器才报。

import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

@MainActor
final class UsageReporter {
    static let shared = UsageReporter()

    private var ping: UsagePing?
    private var timer: Timer?

    func start() {
        guard ping == nil,
              UsagePing.shouldRun(isDevBuild: AppIdentity.isDevBuild, isSelfTest: AppIdentity.isSelfTest),
              let api = UsagePing.apiBase() else { return }
        let version = Bundle.main.appVersionString
        ping = UsagePing(
            file: AppIdentity.configDirectory.appendingPathComponent("usage-ping.json"),
            api: api,
            enabled: { UsageConsent.load().allowsPing },
            // 还没有会员：都算自带 Key。界面只有中文
            info: { UsagePing.Info(version: version, plan: "own", lang: "zh") },
            log: { line in
                DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.debugLog(line) }
            })
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { UsageReporter.shared.tick() }
        }
        (NSApp.delegate as? AppDelegate)?.debugLog("Usage ping: on, api=\(api.host ?? "?")")
    }

    /// 点了「同意」：今天还没报过的现在就报，不等下一个小时
    func consentDidChange(_ consent: UsageConsent) {
        if consent.allowsPing { tick() }
    }

    private func tick() {
        guard let ping else { return }
        Task {
            let outcome = await ping.tick()
            if outcome == .sent { (NSApp.delegate as? AppDelegate)?.debugLog("Usage ping: sent") }
        }
    }
}
