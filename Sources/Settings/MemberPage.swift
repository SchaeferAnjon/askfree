// MemberPage.swift
// Ask Free
//
// 「会员」页和收费页（照会议字幕的收费页方向 A：三栏 + 授权码 + 常见问题，盖在主窗口上，Esc 关）。
// 两种用法二选一：会员（不用填 Key，前 100 位新用户各 30 个问题，之后订阅，每天 200 个）/ 自带 Key（永久免费）。
// 会员的状态都从 MemberClient.shared 来；打开这一页时跟后台对一次（30 秒内问过就不问）。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 结账页、门户页用浏览器打开。开发版设了 ASKFREE_LINK_LOG 就只把网址写进那个文件、不开浏览器（本机测假付款用，不打扰正在用的浏览器）
enum MemberLinks {
    @discardableResult
    static func open(_ url: URL) -> Bool {
        if AppIdentity.isDevBuild, let path = ProcessInfo.processInfo.environment["ASKFREE_LINK_LOG"], !path.isEmpty {
            let line = url.absoluteString + "\n"
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: URL(fileURLWithPath: path))
            }
            (NSApp.delegate as? AppDelegate)?.debugLog("Member: link logged instead of opened (\(url.host ?? "?"))")
            return true
        }
        return AppLinks.safeOpen(url)
    }
}

/// 计数的地方写明原因（用户偏好「统计写明原因」）
enum MemberCopy {
    static let countingReason = "我们会给前 100 位用户免费额度，所以需要统计有多少人在用。统计是匿名的。"
    static let deviceNote = "领试用时只发这台电脑的一个匿名编号（由硬件编号算出来，看不出是谁）。"
    static let privacy = "会员模式下，你的语音和截图经我们的服务器转给火山引擎（识别）和 DeepSeek（回答）；服务器不存这些内容，只记每个问题用了多少。"
}

// MARK: - 用法二选一（会员页和欢迎引导共用）

struct UsageModeCards: View {
    let mode: UsageMode
    let select: (UsageMode) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            card(.member, title: "会员", tags: [("推荐", true), ("免配置", false)],
                 lines: ["不用申请、不用填任何 Key，装好就能问", "前 100 位新用户免费问 30 个问题",
                         "之后每月 ¥9.9 或每年 ¥99，每天 200 个问题"])
            card(.own, title: "自带 Key", tags: [("永久免费", false)],
                 lines: ["用你自己的火山引擎和 DeepSeek Key", "语音和截图直接发给服务商，不经过我们",
                         "两家都有免费额度，用完按量付给服务商"])
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ value: UsageMode, title: String, tags: [(String, Bool)], lines: [String]) -> some View {
        ChoiceCard(selected: mode == value, action: { select(value) }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    ForEach(tags, id: \.0) { Tag(text: $0.0, filled: $0.1) }
                    Spacer()
                    RadioDot(on: mode == value)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.text3)
                            Text(line).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityLabel("\(title)：\(lines.joined(separator: "，"))")
    }
}

/// 一条提示：图标、一句粗体、一句说明、右边可选一个按钮
struct Callout<Trailing: View>: View {
    var icon: String
    var title: String
    var detail: String? = nil
    var warn = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(warn ? Theme.warn : Theme.text2)
                .frame(width: 18).padding(.top, 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(12)
        .background(warn ? Theme.warn.opacity(0.10) : Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(warn ? Theme.warn.opacity(0.35) : Theme.border, lineWidth: 0.5))
    }
}

extension Callout where Trailing == EmptyView {
    init(icon: String, title: String, detail: String? = nil, warn: Bool = false) {
        self.init(icon: icon, title: title, detail: detail, warn: warn) { EmptyView() }
    }
}

// MARK: - 会员页

struct MemberPage: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject private var member = MemberClient.shared
    @State private var mode = UsageMode.current()
    @State private var actionError: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "用法")
                UsageModeCards(mode: mode) { picked in
                    mode = picked
                    UsageModeStore.set(picked)
                }
            }
            if mode == .member { memberStatus } else { ownNote }
            LicenseCodeGroup()
            if mode == .member {
                VStack(alignment: .leading, spacing: 6) {
                    Text(MemberCopy.privacy)
                    Text(MemberCopy.deviceNote + MemberCopy.countingReason)
                }
                .font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.leading, 2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            mode = UsageMode.current()
            if mode == .member { Task { await member.refresh(maxAge: 30) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .askFreeUsageModeDidChange)) { _ in mode = UsageMode.current() }
    }

    // MARK: 会员的状态

    @ViewBuilder private var memberStatus: some View {
        let s = member.status
        VStack(alignment: .leading, spacing: 12) {
            if let s, s.expiring, let until = s.memberUntil {
                Callout(icon: "calendar", title: "会员 \(MemberFormat.day(until)) 到期，不会自动续费",
                        detail: "续买一段，接着现在的到期日往后排，中间不断档。", warn: true) {
                    Button("续买") { model.showsPricing = true }.buttonStyle(SecondaryButtonStyle(height: 28))
                }
            }
            if s?.reason == "payment-failed" || s?.subscription?.status == "past_due" {
                Callout(icon: "creditcard", title: "续费没扣成", detail: "打开「管理订阅」换一张卡；换好就恢复，不用重新订阅。", warn: true) {
                    Button("管理订阅") { openPortal() }.buttonStyle(SecondaryButtonStyle(height: 28))
                }
            }
            SettingsGroup(title: "会员") {
                SettingsRow(title: headline(s), detail: detailLine(s), icon: s?.isMember == true ? "sparkles" : "gift") {
                    if member.isRefreshing { ProgressView().controlSize(.small) }
                }
                if let today = s?.today {
                    Hairline(inset: 46)
                    SettingsRow(title: "今天还能问 \(today.left) 个", detail: "每天 \(today.limit) 个问题，\(MemberFormat.resetLine(today.resetAt))重置。",
                                icon: "calendar")
                }
                Hairline()
                HStack(spacing: 10) {
                    Button(primaryTitle(s)) { model.showsPricing = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(s == nil && member.error == nil)
                    if s?.subscription != nil {
                        Button("管理订阅") { openPortal() }
                            .buttonStyle(SecondaryButtonStyle(height: 30))
                            .disabled(busy)
                    }
                    Spacer()
                    Button("刷新") { Task { await member.refresh() } }
                        .buttonStyle(PlainTextButtonStyle())
                        .disabled(member.isRefreshing)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            if let error = member.error, s == nil || error.code != "network" {
                StatusText(text: error.message, kind: .danger)
            }
            if let actionError { StatusText(text: actionError, kind: .danger) }
        }
    }

    /// 第一行：会员写在用哪种（剩几个在下一行），其余写剩几个 / 为什么用不了
    private func headline(_ s: MemberStatus?) -> String {
        if let s, s.isMember {
            if s.autoRenew { return "会员 · 自动续费中" }
            if let until = s.memberUntil { return "会员 · 用到 \(MemberFormat.day(until))" }
            return "会员"
        }
        let line = MemberSummary.line(s, error: member.error)
        return "\(line.title) · \(line.detail)"
    }

    private func detailLine(_ s: MemberStatus?) -> String {
        guard let s else { return member.error == nil ? "第一次打开会员会领一次试用，不用注册、不用登录。" : "连上以后这里显示剩几个问题。" }
        if let sub = s.subscription, s.isMember, sub.status != "canceled" {
            let price = sub.amount.map { MemberFormat.money($0, currency: sub.currency ?? "cny") } ?? ""
            let cycle = sub.plan == "year" ? "年付" : "月付"
            if sub.cancelAtPeriodEnd == true, let until = sub.accessUntil ?? s.memberUntil {
                return "\(cycle) \(price)，已取消自动续费，用到 \(MemberFormat.day(until))。"
            }
            if let end = sub.periodEnd { return "\(cycle) \(price)，自动续费，下次扣款 \(MemberFormat.day(end))。随时能在「管理订阅」里取消。" }
            return "\(cycle) \(price)，自动续费。"
        }
        if s.isMember, let pass = s.pass, let until = s.memberUntil {
            let what = pass.plan == "year" ? "1 年" : "1 个月"
            return "一次买 \(what)，用到 \(MemberFormat.day(until))，不会自动续费。"
        }
        if s.isMember, let until = s.memberUntil { return "用到 \(MemberFormat.day(until))。" }
        switch s.reason {
        case "trial-closed": return "前 100 位新用户的免费名额已经发完了。订阅以后每天能问 200 个，或者改用自带 Key。"
        case "sub-ended": return "续订或再买一段就能接着问；没用完的试用次数也还在。"
        case "trial-used-up": return "免费的 \(s.trial.total) 个问题用完了。订阅以后每天能问 200 个，或者改用自带 Key。"
        default: return "前 100 位新用户各 \(s.trial.total) 个问题，不过期。已经用了 \(s.trial.used) 个。"
        }
    }

    private func primaryTitle(_ s: MemberStatus?) -> String {
        guard let s else { return "看看会员方案" }
        if s.isMember { return s.autoRenew ? "会员方案" : "续买" }
        return s.reason == "sub-ended" ? "续订" : "订阅会员"
    }

    private func openPortal() {
        busy = true
        actionError = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                MemberLinks.open(try await member.portal())
            } catch let e as MemberAPIError {
                actionError = e.message
            } catch {}
        }
    }

    // MARK: 自带 Key

    private var ownNote: some View {
        Callout(icon: "key", title: "正在用自带 Key，永久免费",
                detail: "语音识别和回答用你在「语音与模型」里填的 Key，直接发给服务商，不经过我们，也不算次数。") {
            Button("去语音与模型") { model.page = .models }.buttonStyle(SecondaryButtonStyle(height: 28))
        }
    }
}

/// 授权码：这台电脑的码（复制）、用在几台上、输别的码、解绑。会员页和收费页共用
struct LicenseCodeGroup: View {
    var compact = false
    @ObservedObject private var member = MemberClient.shared
    @State private var code = ""
    @State private var message: (text: String, ok: Bool)?
    @State private var working = false
    @State private var confirmUnbind = false

    var body: some View {
        if compact { field } else {
            SettingsGroup(title: "授权码", footer: "在别的电脑上买过，或者在官网买的：输入授权码，这台电脑就用那张会员。一个授权码最多用在 2 台 Mac 上。") {
                if let s = member.status, let mine = s.code {
                    SettingsRow(title: mine, detail: "这台电脑的授权码，用在 \(s.devices) 台电脑上，最多 \(s.maxDevices) 台。", icon: "number") {
                        HStack(spacing: 8) {
                            Button("复制") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(mine, forType: .string)
                                message = ("授权码已复制", true)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            if !s.trialOnly {
                                Button("解绑这台电脑") { confirmUnbind = true }.buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    Hairline()
                }
                field.padding(.horizontal, 16).padding(.vertical, 12)
            }
            .confirmationDialog("解绑这台电脑？", isPresented: $confirmUnbind) {
                Button("解绑") { unbind() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这台电脑不再用这个授权码，退回它自己的试用次数。授权码在别的电脑上照常用，以后输码还能再绑回来。")
            }
        }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("AF-XXXX-XXXX-XXXX", text: $code)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 0.5))
                    .onSubmit(activate)
                    .accessibilityLabel("授权码")
                Button(working ? "激活中…" : "激活", action: activate)
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .disabled(working || code.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message { StatusText(text: message.text, kind: message.ok ? .ok : .danger) }
        }
    }

    private func activate() {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !working else { return }
        working = true
        message = nil
        Task { @MainActor in
            defer { working = false }
            do {
                try await member.activate(code: text)
                code = ""
                if UsageMode.current() != .member { UsageModeStore.set(.member) }
                let line = MemberSummary.line(member.status)
                message = ("已激活：\(line.title) · \(line.detail)", true)
            } catch let e as MemberAPIError {
                message = (e.message, false)
            } catch {}
        }
    }

    private func unbind() {
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                try await member.unbind()
                message = ("已解绑，这台电脑退回自己的试用", true)
            } catch let e as MemberAPIError {
                message = (e.message, false)
            } catch {}
        }
    }
}

// MARK: - 收费页

struct PricingSheet: View {
    let close: () -> Void
    let openModels: () -> Void
    @ObservedObject private var member = MemberClient.shared
    @AppStorage("memberCurrency") private var currency = "cny"
    @AppStorage("memberPlan") private var plan = "year"
    @State private var error: MemberAPIError?
    @State private var opening: String?
    @State private var justPaid = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    HStack(alignment: .top, spacing: 12) {
                        trialColumn
                        memberColumn
                        ownColumn
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已经买过了？输入授权码").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text2)
                        LicenseCodeGroup(compact: true).frame(maxWidth: 420)
                    }
                    faq
                }
                .padding(28)
            }
        }
        .frame(width: 860, height: 660)
        .background(Theme.bg)
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
                    .frame(width: 26, height: 26).background(Theme.selected, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("关闭")
            .padding(14)
        }
        // 自带 Key 又没注册过的只是来看看价格：不去注册（不占免费名额），价格按默认的写
        .onAppear { if UsageMode.current() == .member || member.hasDevice { Task { await member.refresh(maxAge: 30) } } }
        .onReceive(NotificationCenter.default.publisher(for: .askFreeMemberDidPay)) { _ in justPaid = true }
    }

    private var status: MemberStatus? { member.status }

    // MARK: 抬头

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            AppIconView(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ask Free · 按一个键，AI 看着屏幕回答").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Tag(text: "开源", filled: true)
                    Text("软件开源、永久免费；会员买的是不用配置的语音识别、问答和联网搜索。")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                }
            }
            Spacer()
            MiniSegmented(options: [("cny", "人民币"), ("usd", "美元")], selection: $currency)
                .padding(.trailing, 36)
        }
    }

    // MARK: 三栏

    private var trialColumn: some View {
        let trial = status?.trial
        let state: String = {
            guard let status else { return "选会员后自动领取" }
            if status.isMember { return "已是会员" }
            if trial?.granted == false { return "名额已发完" }
            return (trial?.left ?? 0) > 0 ? "试用中 · 剩 \(trial?.left ?? 0) 个" : "试用已用完"
        }()
        return column(name: "免费试用", tags: [("前 100 位新用户", false)], price: "免费", unit: "· \(trial?.total ?? 30) 个问题",
                      sub: "装好就能问，不用填任何 Key", featured: false,
                      items: ["语音识别、问答、联网都能用", "不用注册、不用登录", "不过期，用完再选会员或自带 Key"]) {
            Text(state).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Theme.selected, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var memberColumn: some View {
        let amount = status?.prices?.amount(plan: plan, currency: currency)
        let price = amount.map { MemberFormat.money($0, currency: currency) } ?? (currency == "usd" ? (plan == "year" ? "$19.9" : "$1.99") : (plan == "year" ? "¥99" : "¥9.9"))
        return column(name: "会员", tags: [("推荐", true), ("免配置", false)], price: price, unit: plan == "year" ? "· 每年" : "· 每月",
                      sub: "自动续费，随时取消，用到当期结束", featured: true,
                      items: ["每天 200 个问题，北京时间早上 8 点重置", "语音识别、问答、联网搜索全包",
                              "一个授权码最多 2 台 Mac", currency == "usd" ? "银行卡、Apple Pay 自动续费" : "刷卡自动续费；也能微信一次买，不自动续费"]) {
            VStack(alignment: .leading, spacing: 10) {
                MiniSegmented(options: [("month", "月付"), ("year", "年付")], selection: $plan)
                memberAction(price: price)
                if currency == "cny", let pass = status?.passPrices, !(status?.autoRenew ?? false) {
                    passRow(pass)
                }
                if let error {
                    Text(error.message).font(.system(size: 12)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
                    if ["already-subscribed", "payment-failed"].contains(error.code), status?.subscription != nil {
                        Button("打开「管理订阅」") { portal() }.buttonStyle(PlainTextButtonStyle(color: Theme.text))
                    }
                }
            }
        }
    }

    @ViewBuilder private func memberAction(price: String) -> some View {
        if justPaid {
            StatusText(text: "付款成功，已经是会员了").frame(height: 32)
        } else if let pending = member.pendingCheckout {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("在浏览器里付款，付完这里自动变成会员").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                HStack(spacing: 12) {
                    Text(pending.mode == "pass" ? "一次买 \(pending.plan == "year" ? "1 年" : "1 个月")" : (pending.plan == "year" ? "年付" : "月付"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text3)
                    Button("不等了") { member.cancelCheckout() }.buttonStyle(PlainTextButtonStyle())
                }
            }
            .frame(minHeight: 32)
        } else if status?.autoRenew == true {
            Button("已是会员 · 管理订阅") { portal() }
                .buttonStyle(SecondaryButtonStyle(height: 32)).frame(maxWidth: .infinity)
        } else if status != nil && status?.prices == nil {
            Text("购买还没开通，稍后再试").font(.system(size: 12)).foregroundStyle(Theme.text3).frame(height: 32)
        } else {
            Button { buy(plan: plan, mode: "sub") } label: {
                HStack(spacing: 6) {
                    if opening == "sub" { ProgressView().controlSize(.mini) }
                    Text(status?.isMember == true ? "开自动续费 · \(price)" : "订阅 · \(price) / \(plan == "year" ? "年" : "月")")
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(opening != nil)
        }
    }

    /// 人民币：微信一次买 1 个月 / 1 年，不自动续费（Stripe 的订阅不收微信）
    private func passRow(_ pass: MemberStatus.Prices) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(status?.isMember == true ? "续买一段（微信等，不自动续费）：" : "不想自动续费？微信一次买：")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
            HStack(spacing: 8) {
                ForEach([("month", "1 个月"), ("year", "1 年")], id: \.0) { p, title in
                    if let amount = pass.amount(plan: p, currency: "cny") {
                        Button {
                            buy(plan: p, mode: "pass")
                        } label: {
                            HStack(spacing: 4) {
                                if opening == "pass-\(p)" { ProgressView().controlSize(.mini) }
                                Text("\(title) \(MemberFormat.money(amount, currency: "cny"))")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                        .disabled(opening != nil || member.pendingCheckout != nil)
                    }
                }
            }
        }
    }

    private var ownColumn: some View {
        let using = UsageMode.current() == .own
        return column(name: "自带 Key", tags: [("永久免费", false)], price: "免费", unit: "· 不限次数",
                      sub: "用你自己的 Key，费用直接付给服务商", featured: false,
                      items: ["语音和截图直接发给服务商，不经过我们", "火山引擎每个识别版本送 20 小时", "DeepSeek、千问都有免费额度"]) {
            Button {
                UsageModeStore.set(.own)
                close()
                openModels()
            } label: {
                HStack(spacing: 6) {
                    Text(using ? "正在用 · 去填 Key" : "改用自带 Key")
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(height: 32))
        }
    }

    private func column<Action: View>(name: String, tags: [(String, Bool)], price: String, unit: String, sub: String, featured: Bool,
                                      items: [String], @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                ForEach(tags, id: \.0) { Tag(text: $0.0, filled: $0.1) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(price).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.text)
                Text(unit).font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            Text(sub).font(.system(size: 12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            action()
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(item).font(.system(size: 12.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(featured ? Theme.ink : Theme.border, lineWidth: featured ? 2 : 0.5))
    }

    // MARK: 常见问题

    private var faq: some View {
        let items = [
            ("一个问题怎么算？", "按一次键问一句就是一个问题：识别、回答、联网查、点「重试」都算在这一个里面。没听到你说话、没答成的不算。追问是新的一个。"),
            ("每天 200 个用完了会怎样？", "当天不能再问，北京时间早上 8 点重置。改成自带 Key 照样能用，不限次数。"),
            ("怎么取消？", "「会员」页点「管理订阅」，在 Stripe 的页面里取消，用到这一期结束，不再扣钱。微信一次买的到期就停，不会自动扣款。"),
            ("我的问题会被存吗？", "会员的语音和截图经我们的服务器转给火山引擎和 DeepSeek，服务器不存这些内容，只记每个问题用了多少。历史只存在你的 Mac 上。"),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("常见问题").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: 14) {
                ForEach(items, id: \.0) { q, a in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(q).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                        Text(a).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: 动作

    private func buy(plan: String, mode: String) {
        error = nil
        opening = mode == "pass" ? "pass-\(plan)" : "sub"
        Task { @MainActor in
            defer { opening = nil }
            do {
                if UsageMode.current() != .member { UsageModeStore.set(.member) }
                let url = try await member.checkout(plan: plan, currency: mode == "pass" ? "cny" : currency, mode: mode)
                MemberLinks.open(url)
            } catch let e as MemberAPIError {
                error = e
            } catch {}
        }
    }

    private func portal() {
        error = nil
        Task { @MainActor in
            do {
                MemberLinks.open(try await member.portal())
            } catch let e as MemberAPIError {
                error = e
            } catch {}
        }
    }
}
