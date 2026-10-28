// UsageConsentViews.swift
// Ask Free
//
// 匿名使用统计的询问（照 MeetCaption 的 shared/consent.js 和 control/consent.js）：欢迎引导里那一步和主窗口的询问共用这段正文。
// 「同意」「不用了」一样大、一样的样式，都不预先选中（回车不替用户选）；点了记成 yes / no，以后不再问。
// 主窗口的询问：老用户更新后第一次打开主窗口时问一次，引导里没答那一步的人也问；不能按 Esc 关掉，没点就退出的下次打开还问。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 原因、每天发什么、不发什么、以后在哪改
struct UsageConsentBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UsageConsentCopy.reason).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 6) {
                Text(UsageConsentCopy.intro)
                ForEach(UsageConsentCopy.items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.text3).accessibilityHidden(true)
                        Text(item)
                    }
                }
            }
            Text(UsageConsentCopy.never)
            Text(UsageConsentCopy.later).foregroundStyle(Theme.text2)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// 两个一样大、一样显眼的按钮，哪个都不是默认按钮
struct UsageConsentButtons: View {
    var current: UsageConsent = .unasked
    let answer: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            button(UsageConsentCopy.agree, agree: true)
            button(UsageConsentCopy.decline, agree: false)
        }
    }

    private func button(_ title: String, agree: Bool) -> some View {
        Button { answer(agree) } label: { Text(title).frame(width: 84) }
            .buttonStyle(SecondaryButtonStyle(height: 30))
            .accessibilityValue(current == (agree ? .yes : .no) ? "已选" : "")
    }
}

/// 主窗口上的询问
struct UsageConsentSheet: View {
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                AppIconView(size: 40)
                Text(UsageConsentCopy.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            }
            UsageConsentBody()
            HStack {
                Spacer()
                UsageConsentButtons(answer: answer)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.bg)
        .interactiveDismissDisabled()
    }
}

/// 什么时候能弹主窗口的询问：启动自测、画页面截图、演示模式（拍 README 截图）都不弹
enum UsageConsentPrompt {
    static var isAllowed: Bool {
        !AppIdentity.isSelfTest && DevLaunchOptions.snapshotPagesDirectory == nil && !DevLaunchOptions.isDemo
    }
}
