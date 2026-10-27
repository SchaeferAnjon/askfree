// StartPage.swift
// Ask Free
//
// 「开始」：还没配好时是三步（先授权、再填 Key、再选提问键），当前那步是全页唯一的黑按钮，做完打勾。
// 三步都做完就变「首页」：示意、三种问法（各带键）、说话时的四个手势、最近问过的三条。

import SwiftUI
#if canImport(AskFreeCore)
import AskFreeCore
#endif

struct StartPage: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject private var status = SetupStatus.shared
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoStage(keyTitle: store.hotkeys.screen == nil ? nil : store.hotkeys.screenTitle)
            if status.allDone { home } else { start }
        }
    }

    // MARK: 开始：三步

    private var start: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("开始用 Ask Free").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
                Text("做完下面三步，以后看到不懂的东西，按一个键就能问。").font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            VStack(spacing: 0) {
                step(1, item: .permissions, title: "允许三项权限",
                     detail: "麦克风点一下允许；另外两项打开系统设置，把 Ask Free 的图标拖进列表。") {
                    EmptyView()
                } below: {
                    PermissionRows(compact: true, highlightNext: current == .permissions)
                }
                Hairline()
                step(2, item: .keys, title: "填两个 Key",
                     detail: "一个把你说的话听成文字，一个回答问题。推荐火山引擎加 DeepSeek，都有免费额度。") {
                    if status.keysReady {
                        StatusText(text: "已填好")
                    } else if current == .keys {
                        Button("去填写") { model.page = .models }.buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("去填写") { model.page = .models }.buttonStyle(SecondaryButtonStyle())
                    }
                } below: { EmptyView() }
                Hairline()
                step(3, item: .hotkey, title: "选一个提问键",
                     detail: "每台键盘不一样，Ask Free 不替你定。按住它说话，松开就问。") {
                    HotkeyButton(kind: .screen)
                } below: { EmptyView() }
            }
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// 先授权、再填 Key、再选键：第一件没做完的就是当前这步
    private var current: SetupStatus.Item? { status.checklist.current }

    private func step<Trailing: View, Below: View>(_ n: Int, item: SetupStatus.Item, title: String, detail: String,
                                                  @ViewBuilder trailing: () -> Trailing,
                                                  @ViewBuilder below: () -> Below) -> some View {
        let done = status.isDone(item)
        let isCurrent = current == item
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    if done {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.ok)
                    } else if isCurrent {
                        Circle().fill(Theme.ink)
                        Text("\(n)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.onInk)
                    } else {
                        Circle().stroke(Theme.borderStrong, lineWidth: 1)
                        Text("\(n)").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                }
                .frame(width: 22, height: 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(done ? "第 \(n) 步，已完成" : "第 \(n) 步")
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(done ? Theme.text2 : Theme.text)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                trailing()
            }
            below().padding(.leading, 36)
        }
        .padding(16)
        .background(isCurrent ? Theme.hover : .clear)
    }

    // MARK: 首页

    private var home: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "三种问法")
                HStack(alignment: .top, spacing: 10) {
                    askCard(icon: "rectangle.on.rectangle", title: "看屏幕问 AI",
                            detail: "按住说话，松开就问。指针指着哪，AI 就重点看哪。", kind: .screen)
                    askCard(icon: "mic", title: "只提问",
                            detail: "不截屏，更快；屏幕上的东西不会发出去。", kind: .plain)
                    askCard(icon: "keyboard", title: "打字问 AI",
                            detail: "双击一颗键，弹出输入框，回车发送。", kind: .typeAsk)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "说话时还能这样")
                GestureHints()
            }
            RecentHistory(model: model)
        }
    }

    private func askCard(icon: String, title: String, detail: String, kind: HotkeyButton.Kind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.text2)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            }
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HotkeyButton(kind: kind)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
    }
}

/// 回答还在时再按一次 → 追问；开头说「新话题」→ 另起一个话题 …
struct GestureHints: View {
    private let hints: [(String, String)] = [
        ("回答还在时再按一次", "追问"), ("开头说「新话题」", "另起一个话题"),
        ("开头说「搜一下」", "直接联网查"), ("说话时按 Esc", "取消这一问"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { col in
                        let hint = hints[row * 2 + col]
                        HStack(spacing: 8) {
                            Text(hint.0).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 8).frame(height: 24)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 0.5))
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.text3)
                            Text(hint.1).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
    }
}

/// 首页「最近问过」三条，点一条去历史里看
struct RecentHistory: View {
    @ObservedObject var model: MainWindowModel
    @State private var threads: [AskHistoryThread] = Array(AskHistoryStore.shared.threads().prefix(3))

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "最近问过")
                Spacer()
                if !threads.isEmpty {
                    Button("全部历史") { model.page = .history }.buttonStyle(PlainTextButtonStyle(color: Theme.text))
                }
            }
            SettingsGroup {
                if threads.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "clock").font(.system(size: 14)).foregroundStyle(Theme.text3)
                        Text("还没问过。按住提问键问一个问题，答完就会出现在这里。")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                        Spacer()
                    }
                    .padding(16)
                } else {
                    ForEach(threads.indices, id: \.self) { i in
                        if i > 0 { Hairline() }
                        Button {
                            HistorySelection.pending = threads[i].id
                            model.page = .history
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: HistoryKind.of(threads[i]).symbol).font(.system(size: 12)).foregroundStyle(Theme.text3)
                                    .frame(width: 16)
                                Text(threads[i].turns[0].question).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Spacer(minLength: 12)
                                Text(HistoryFormat.shortTime(threads[i].updatedAt)).font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(Theme.text3)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .askFreeHistoryDidChange)) { _ in
            threads = Array(AskHistoryStore.shared.threads().prefix(3))
        }
    }
}
