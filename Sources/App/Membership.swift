// Membership.swift
// Ask Free
//
// 会员（docs：meetcaption-server/docs/multi-product.md §4）：这台电脑的会员客户端只有一个（MemberClient.shared），
// 设备令牌在钥匙串（开发版在 dev_secrets.json）。开发版没设 ASKFREE_API 时不连后台：线上前 100 份免费名额不能被开发版占掉。
// 什么时候问后台：启动、回到 Ask Free、打开会员页（都节流），计量请求回 402 / 429 之后；其余时候看计量接口的返回头。

import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension MemberClient {
    @MainActor static let shared: MemberClient = {
        let client = MemberClient(base: MemberEndpoint.current, secrets: AppIdentity.defaultSecretStore(),
                                  fingerprint: { MemberFingerprint.current() }, version: Bundle.main.appVersionString)
        client.log = { line in (NSApp.delegate as? AppDelegate)?.debugLog(line) }
        // 浏览器里付完回到这里：主窗口跳到会员页，收费页上写「付款成功」
        client.onPaid = { _ in
            NotificationCenter.default.post(name: .askFreeMemberDidPay, object: nil)
            SettingsWindowController.show(page: .member)
        }
        return client
    }()
}

extension Notification.Name {
    /// 付款成功、已经是会员了（收费页换成成功的样子）
    static let askFreeMemberDidPay = Notification.Name("AskFreeMemberDidPay")
    /// 换了用法（会员 / 自带 Key）
    static let askFreeUsageModeDidChange = Notification.Name("AskFreeUsageModeDidChange")
}

/// 用法的读写：换了要通知 SetupStatus、菜单栏、回答面板
enum UsageModeStore {
    static var current: UsageMode { UsageMode.current() }
    static var isMember: Bool { current == .member }

    /// refresh：换成会员时顺手问一次后台（没注册的这时领试用）。欢迎引导里不问：等用户点「领取免费试用」
    @MainActor static func set(_ mode: UsageMode, refresh: Bool = true) {
        UsageMode.save(mode)
        NotificationCenter.default.post(name: .askFreeUsageModeDidChange, object: nil)
        NotificationCenter.default.post(name: .askFreeModelSettingsDidChange, object: nil)
        if mode == .member, refresh { Task { await MemberClient.shared.refresh(maxAge: 30) } }
    }
}

extension AppDelegate {
    /// 会员模式下按下提问键那一刻：上次问后台时已经知道用不了（试用用完、名额发完、到期、欠费、今天的用完了），
    /// 不录音，直接在右上角说清楚怎么办（订阅 / 换卡），顺手再问一次后台（别处刚付过钱就能马上恢复）。回 true = 拦下了
    @MainActor
    func blockedByMembership() -> Bool {
        guard UsageModeStore.isMember else { return false }
        let member = MemberClient.shared
        guard let s = member.status, !s.canUse, let reason = s.reason else { return false }
        if reason == "daily-limit", let reset = s.today?.resetAt, Date().timeIntervalSince1970 * 1000 >= reset {
            Task { await member.refresh() }
            return false
        }
        let message = reason == "daily-limit" ? "今天的 \(s.today?.limit ?? 200) 个问题用完了，北京时间早上 8 点重置" : MemberSummary.line(s).detail
        debugLog("Member: blocked before asking reason=\(reason)")
        showMemberNotice(MemberAPIError(status: reason == "daily-limit" ? 429 : 402, code: reason, message: message,
                                        resetAt: s.today?.resetAt))
        Task { await member.refresh() }
        return true
    }

    /// 还没问出问题就被后台拦下（识别那一步、按键时已知用不了）：右上角只放一张报错卡，没有可以重问的问题
    func showMemberNotice(_ error: MemberAPIError) {
        askRound += 1
        answerPanel.startThread(question: "")
        answerPanel.fail(AskFailure(error: error).withoutRetry)
    }

    /// 报错卡上的「订阅会员」「续订」：打开主窗口的会员页，收费页直接弹出来
    @MainActor
    func openMembership(showPricing: Bool = true) {
        SettingsWindowController.show(page: .member)
        if showPricing { SettingsWindowController.shared?.model.showsPricing = true }
    }

    /// 「管理订阅」：问后台要门户网址，拿到就用浏览器开
    @MainActor
    func openMemberPortal() {
        Task { @MainActor in
            do {
                let url = try await MemberClient.shared.portal()
                AppLinks.safeOpen(url)
            } catch let e as MemberAPIError {
                debugLog("Member: portal failed \(e.code)")
                openMembership(showPricing: false)
                overlayWindow.showHint(e.message)
            } catch {}
        }
    }
}
