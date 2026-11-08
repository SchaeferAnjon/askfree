// AnkiPage.swift
// Ask Free
//
// 设置里的「Anki」页：连上 Anki（三个软件同一块，DESIGN.md「往 Anki 里加卡」）和默认牌组。
// 三行每 2 秒自己查一次，没有「检查」按钮；下一步要做的那个按钮是这一屏唯一的实心按钮。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 这台 Mac 上 Anki 的三件事：装了没有、AnkiConnect 插件装了没有、开着没有
@MainActor
final class AnkiCheck: ObservableObject {
    @Published var ankiVersion: String?
    @Published var ankiURL: URL?
    @Published var addonInstalled = false
    @Published var connected = false
    @Published var running = false
    @Published var opening = false
    @Published var checkedOnce = false

    static var addonFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Anki2/addons21/\(AnkiConnect.addonCode)")
    }

    func check() async {
        let url = AnkiPrefs.ankiURL
        ankiURL = url
        ankiVersion = url.map { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
        running = AnkiPrefs.ankiIsRunning
        do {
            _ = try await AnkiConnect().version()
            connected = true
        } catch {
            connected = false
        }
        addonInstalled = connected || FileManager.default.fileExists(atPath: Self.addonFolder.path)
        if connected { opening = false }
        checkedOnce = true
    }
}

struct AnkiPage: View {
    @ObservedObject var notes: NotesModel
    @StateObject private var check = AnkiCheck()
    @State private var copied = false
    @State private var deck = AnkiPrefs.deckName

    private enum Step { case install, addon, open, done }

    private var next: Step {
        if check.ankiVersion == nil { return .install }
        if !check.addonInstalled { return .addon }
        if !check.connected { return .open }
        return .done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("笔记里挑的问题变成卡片，进 Anki 复习。手机上的 AnkiMobile、AnkiDroid 同步以后也有。下面三项每 2 秒自己查一次，不用点检查。")
                .font(.system(size: 13)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Stage(height: 150) { diagram }
            SettingsGroup(footer: check.connected ? "卡片会放进「\(notes.topDeck)」牌组。"
                          : "连上以后，卡片放进「\(notes.topDeck)」牌组。没连上时勾着的问题都留着，连上再送。") {
                ankiRow
                Hairline()
                addonRow
                Hairline()
                openRow
            }
            SettingsGroup(title: "牌组", footer: "卡片默认进这个牌组；建好以后在 Anki 里改名也行，这里跟着走。来源写进标签「来自::Ask_Free」。") {
                SettingsRow(title: "默认牌组") {
                    HStack(spacing: 8) {
                        TextField(AnkiCardBuilder.defaultDeck, text: $deck)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onSubmit(applyDeck)
                        Button("改", action: applyDeck)
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(deck.trimmingCharacters(in: .whitespaces) == AnkiPrefs.deckName)
                    }
                }
            }
        }
        .task {
            notes.refreshDecks()
            while !Task.isCancelled {
                await check.check()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onReceive(notes.$topDeck) { deck = $0 }
    }

    private func applyDeck() {
        notes.setDeck(deck)
        deck = AnkiPrefs.deckName
    }

    // MARK: 示意图：Ask Free — AnkiConnect — Anki，连上了线变绿

    private var diagram: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                node(Image(nsImage: NSApp.applicationIconImage), "Ask Free")
                wire
                HStack(spacing: 6) {
                    Circle().fill(check.connected ? Theme.ok : check.addonInstalled ? Theme.warn : Theme.text3).frame(width: 7, height: 7)
                    Text("AnkiConnect").font(.system(size: 12)).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Theme.elevated, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                .padding(.bottom, 20)
                wire
                node(check.ankiURL.map { Image(nsImage: NSWorkspace.shared.icon(forFile: $0.path)) } ?? Image(systemName: "rectangle.stack"), "Anki")
            }
            Group {
                if check.connected {
                    Text("连上了").foregroundStyle(Theme.ok)
                } else if check.checkedOnce {
                    Text("没连上 · " + (next == .install ? "还没装 Anki" : next == .addon ? "还差 AnkiConnect 插件" : "Anki 没开")).foregroundStyle(Theme.warn)
                } else {
                    Text("正在查…").foregroundStyle(Theme.text2)
                }
            }
            .font(.system(size: 12))
        }
    }

    private func node(_ icon: Image, _ name: String) -> some View {
        VStack(spacing: 6) {
            icon.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .frame(width: 44, height: 44)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border, lineWidth: 0.5))
            Text(name).font(.system(size: 12)).foregroundStyle(Theme.text2)
        }
        .frame(width: 110)
    }

    private var wire: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0.75))
            p.addLine(to: CGPoint(x: 56, y: 0.75))
        }
        .stroke(check.connected ? Theme.ok : Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: check.connected ? [] : [4, 3]))
        .frame(width: 56, height: 1.5)
        .padding(.bottom, 20)
    }

    // MARK: 三行

    private var ankiRow: some View {
        row(state: check.ankiVersion != nil ? .ok : .warn, title: "Anki 桌面版",
            detail: check.ankiVersion.map { $0.isEmpty ? "装好了" : "装好了 · \($0)" } ?? "这台 Mac 上没找到 Anki") {
            if check.ankiVersion == nil {
                action("下载 Anki", systemImage: "arrow.up.right", solid: next == .install) {
                    NSWorkspace.shared.open(URL(string: "https://apps.ankiweb.net")!)
                }
            }
        }
    }

    private var addonRow: some View {
        row(state: check.addonInstalled ? .ok : check.ankiVersion != nil ? .warn : .idle, title: "AnkiConnect 插件",
            detail: check.addonInstalled ? "装好了 · 编号 \(AnkiConnect.addonCode)" : "编号 \(AnkiConnect.addonCode)，Anki 靠它收卡",
            extra: check.addonInstalled || check.ankiVersion == nil ? nil : AnyView(steps)) {
            if !check.addonInstalled {
                action(copied ? "已复制" : "复制编号", systemImage: copied ? "checkmark" : "doc.on.doc", solid: next == .addon) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AnkiConnect.addonCode, forType: .string)
                    copied = true
                }
                .disabled(check.ankiVersion == nil)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepLine(1, Text("在 Anki 里点「工具 › 附加组件 › 获取附加组件」"))
            stepLine(2, Text("粘贴编号 ") + Text(AnkiConnect.addonCode).font(.system(size: 12, design: .monospaced)) + Text("，点「确定」"))
            stepLine(3, Text("装好以后重启 Anki，这一行会自己变绿"))
        }
        .padding(.top, 8)
    }

    private func stepLine(_ n: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.system(size: 11)).foregroundStyle(Theme.text2)
                .frame(width: 17, height: 17)
                .background(Theme.hover, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
            text.font(.system(size: 12.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var openRow: some View {
        let detail: String
        if check.connected {
            detail = "连上了"
        } else if check.opening {
            detail = "正在打开…"
        } else if check.running && check.addonInstalled {
            detail = "开着，但插件还没生效：装好插件以后要重启一次 Anki"
        } else {
            detail = "没开"
        }
        return row(state: check.connected ? .ok : check.ankiVersion != nil ? .warn : .idle, title: "Anki 开着", detail: detail) {
            if !check.connected {
                action("打开 Anki", systemImage: nil, solid: next == .open, busy: check.opening) {
                    guard let url = AnkiPrefs.ankiURL else { return }
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = false
                    NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
                    check.opening = true
                }
                .disabled(check.ankiVersion == nil)
            }
        }
    }

    // MARK: 零件

    private enum RowState { case ok, warn, idle }

    private func row<Actions: View>(state: RowState, title: String, detail: String, extra: AnyView? = nil,
                                    @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                switch state {
                case .ok:
                    Circle().fill(Theme.ok)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                case .warn:
                    Circle().stroke(Theme.warn, lineWidth: 1.5)
                    Text("!").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.warn)
                case .idle:
                    Circle().stroke(Theme.borderStrong, lineWidth: 1.5)
                }
            }
            .frame(width: 20, height: 20)
            .padding(.top, 1)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                if let extra { extra }
            }
            Spacer(minLength: 8)
            actions()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func action(_ title: String, systemImage: String?, solid: Bool, busy: Bool = false, run: @escaping () -> Void) -> some View {
        let label = HStack(spacing: 6) {
            if busy { ProgressView().controlSize(.mini) }
            Text(title)
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11)) }
        }
        if solid {
            Button(action: run) { label }.buttonStyle(PrimaryButtonStyle())
        } else {
            Button(action: run) { label }.buttonStyle(SecondaryButtonStyle(height: 30))
        }
    }
}
