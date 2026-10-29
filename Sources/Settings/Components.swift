// Components.swift
// Ask Free
//
// 主窗口和欢迎引导共用的小部件，和 GetNewWord 的设置页同一套：
// 白底分组卡片、设置行、示意图舞台、方角开关、墨黑主按钮、描边次按钮、键帽、小分段、可选卡片。

import SwiftUI
import AppKit

/// 组名 + 白底卡片；行之间由调用方放 Hairline()
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2).padding(.leading, 2)
            }
            VStack(spacing: 0) { content }
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.leading, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 一行：左图标、标题和一句说明、右边控件。最低 48 高
struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var detailColor: Color = Theme.text2
    var icon: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(width: 18)
                    .accessibilityHidden(true)   // 只是装饰，旁白读名字就够了
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 12)).foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(title: String, detail: String? = nil, icon: String? = nil) {
        self.init(title: title, detail: detail, icon: icon) { EmptyView() }
    }
}

/// 发丝线
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View { Rectangle().fill(Theme.border).frame(height: 0.5).padding(.leading, inset) }
}

/// 小节名：12 / 500 次要色
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2).padding(.leading, 2)
    }
}

/// 示意图的底：surface 色、10 圆角，高度固定，里面动起来也不让布局跳
struct Stage<Content: View>: View {
    var height: CGFloat = 200
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// 方角开关（轨道 5、滑块 3），开着是墨黑。
/// 只画轨道：名字写在设置行左边，Toggle 的 label 只给旁白读（「让 AI 看屏幕，开关，开」）
struct SquareToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isOn ? Theme.ink : Theme.borderStrong)
                    .frame(width: 32, height: 18)
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn ? Theme.onInk : .white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                    .padding(2)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 旁白看到的是一个真开关：名字、开 / 关、「开关」角色都对，按 VO-空格就能切
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

extension ToggleStyle where Self == SquareToggleStyle {
    static var square: SquareToggleStyle { SquareToggleStyle() }
}

/// 实心主按钮：浅色黑底白字，深色白底黑字；一屏只放一个
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Theme.ink.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.3), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}

/// 描边次按钮
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 26
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(configuration.isPressed ? Theme.selected : Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 0.5))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// 只有文字的按钮（上一步、先跳过、高级）
struct PlainTextButtonStyle: ButtonStyle {
    var color: Color = Theme.text2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.6 : 1))
            .contentShape(Rectangle())
    }
}

/// 键帽（⌥、右 Command）
struct KeyCap: View {
    let key: String
    var height: CGFloat = 24
    var body: some View {
        Text(key)
            .font(.system(size: height * 0.5, weight: .medium))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minWidth: height, minHeight: height)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.borderStrong, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 0, y: 1)
    }
}

/// 小标签：推荐 / 必选 / 版本号
struct Tag: View {
    let text: String
    var filled = false
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(filled ? Theme.onInk : Theme.text2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(filled ? Theme.ink : Theme.selected, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// 可选卡片（服务商、浮窗颜色、外观）：选中墨黑 2 粗边
struct ChoiceCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.ink : Theme.borderStrong, lineWidth: selected ? 2 : 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 单选圆点。只是样子：选没选中由外面那张卡片（ChoiceCard）告诉旁白
struct RadioDot: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().stroke(on ? Theme.ink : Theme.borderStrong, lineWidth: on ? 5 : 1).frame(width: 15, height: 15)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

/// 小分段（识别版本、模型、想多久）：浅灰轨道上一块白
struct MiniSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var disabled = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? Theme.text : Theme.text2)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(on ? Theme.elevated : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Theme.border : .clear, lineWidth: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .padding(2)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.5))
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
    }
}

/// 「✓ 已允许」这类状态：只给点和小字上色
struct StatusText: View {
    enum Kind { case ok, warn, danger, neutral }
    let text: String
    var kind: Kind = .ok
    var body: some View {
        HStack(spacing: 4) {
            Group {
                switch kind {
                case .ok: Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                case .warn: Circle().frame(width: 6, height: 6)
                case .danger: Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                case .neutral: EmptyView()
                }
            }
            .accessibilityHidden(true)   // 旁白读字就够，勾和叉不另读成「Selected」
            Text(text).font(.system(size: 12))
        }
        .foregroundStyle(color)
    }
    private var color: Color {
        switch kind {
        case .ok: return Theme.ok
        case .warn: return Theme.warn
        case .danger: return Theme.danger
        case .neutral: return Theme.text3
        }
    }
}

extension OpenURLAction {
    /// 回答里模型写出的 Markdown 链接：只放行 https / mailto（AppLinks.safeOpen），别的点了不开
    static let safe = OpenURLAction { url in AppLinks.safeOpen(url) ? .handled : .discarded }
    /// 回答正文里的链接（面板、历史页）：比 safe 更严，只放行 https，mailto 也不开
    static let answerLink = OpenURLAction { url in
        guard url.scheme?.lowercased() == "https" else { return .discarded }
        return AppLinks.safeOpen(url) ? .handled : .discarded
    }
}

/// 点开就去网页的链接（去 xxx 拿 Key ↗）
struct LinkText: View {
    let title: String
    let url: String
    var body: some View {
        Button {
            AppLinks.safeOpen(url)
        } label: {
            HStack(spacing: 2) {
                Text(title).underline(true, color: Theme.borderStrong)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 「› 高级」折叠行
struct DisclosureLine<Content: View>: View {
    let title: String
    @Binding var expanded: Bool
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title).font(.system(size: 12.5))
                }
                .foregroundStyle(Theme.text2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded { content }
        }
    }
}

/// Ask Free 的图标（指针加问号），从 App 图标取
struct AppIconView: View {
    var size: CGFloat = 40
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
