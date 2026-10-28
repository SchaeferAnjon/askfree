// HistoryView.swift
// Ask Free
//
// 历史两栏：左边搜索框、按问法筛、按天分组的列表（上下键换一条、右键复制删除）；
// 右边是整段问答，顺序固定：发给 AI 的截图、回答、找到的图、追问。只存在这台 Mac 上。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension Notification.Name {
    /// 历史里多了一轮问答（答完一题、补图时发）
    static let askFreeHistoryDidChange = Notification.Name("AskFreeHistoryDidChange")
}

/// 从首页「最近问过」点进来时要选中的话题
@MainActor
enum HistorySelection {
    static var pending: String?
}

/// 一个话题是怎么问的（看第一轮）；旧记录没记问法，有截图算看屏幕问，没有算只提问
enum HistoryKind {
    case screen, plain, type

    static func of(_ thread: AskHistoryThread) -> HistoryKind {
        switch thread.turns[0].via {
        case "type": return .type
        case "plain": return .plain
        case "screen": return .screen
        default: return thread.turns[0].hasScreenshot ? .screen : .plain
        }
    }

    var symbol: String {
        switch self {
        case .screen: return "rectangle.on.rectangle"
        case .plain: return "mic"
        case .type: return "keyboard"
        }
    }

    var title: String {
        switch self {
        case .screen: return "看屏幕问"
        case .plain: return "只提问"
        case .type: return "打字问"
        }
    }
}

enum HistoryFormat {
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func time(_ date: Date) -> String { time.string(from: date) }

    /// 今天 14:32 / 昨天 22:14 / 10月20日 21:16
    static func shortTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天 " + time(date) }
        if calendar.isDateInYesterday(date) { return "昨天 " + time(date) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }

    /// 今天 / 昨天 / 10月19日 周日 / 2025年10月19日
    static func day(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year) ? "M月d日 EEE" : "yyyy年M月d日"
        return f.string(from: day)
    }

    /// 回答的第一句，去掉 Markdown 记号
    static func preview(_ answer: String) -> String {
        AnswerPanel.plainText(fromMarkdown: answer)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "`", with: "")
    }

    static func copyText(_ thread: AskHistoryThread) -> String {
        thread.turns.map { "问：\($0.question)\n\n\(AnswerPanel.plainText(fromMarkdown: $0.answer))" }
            .joined(separator: "\n\n")
    }
}

struct HistoryView: View {
    enum Filter: String, CaseIterable {
        case all = "全部", screen = "看屏幕", plain = "只提问", type = "打字", web = "联网"
    }

    /// 打开时把键盘焦点给列表（上下键换一条）；从侧栏用 ↑↓ 走过来时为 false，焦点留在侧栏
    var focusListOnAppear = true

    @State private var threads: [AskHistoryThread] = AskHistoryStore.shared.threads()
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var selectedID: String?
    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool

    private var visible: [AskHistoryThread] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return threads.filter { thread in
            guard q.isEmpty || thread.matches(q) else { return false }
            switch filter {
            case .all: return true
            case .screen: return HistoryKind.of(thread) == .screen
            case .plain: return HistoryKind.of(thread) == .plain
            case .type: return HistoryKind.of(thread) == .type
            case .web: return thread.turns.contains { $0.searched == true || !$0.images.isEmpty }
            }
        }
    }

    private var days: [(day: Date, threads: [AskHistoryThread])] {
        var out: [(day: Date, threads: [AskHistoryThread])] = []
        for thread in visible {
            let day = Calendar.current.startOfDay(for: thread.updatedAt)
            if out.last?.day == day { out[out.count - 1].threads.append(thread) } else { out.append((day, [thread])) }
        }
        return out
    }

    private var selected: AskHistoryThread? {
        visible.first { $0.id == selectedID } ?? visible.first
    }

    var body: some View {
        HStack(spacing: 0) {
            listColumn
                .frame(width: 330)
            Rectangle().fill(Theme.border).frame(width: 0.5)
            Group {
                if let selected {
                    HistoryDetail(thread: selected, onDelete: { delete(selected.id) })
                        .id(selected.id)
                } else {
                    emptyDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if let pending = HistorySelection.pending { selectedID = pending; HistorySelection.pending = nil }
            if focusListOnAppear { listFocused = true }
        }
        // ⌘F：光标进搜索框
        .background {
            Button("搜索历史") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .askFreeHistoryDidChange)) { _ in
            threads = AskHistoryStore.shared.threads()
        }
    }

    // MARK: 左栏

    private var listColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.text3)
                    TextField("搜问题和回答", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                        .accessibilityLabel("搜索历史")
                        .help("搜问题和回答（⌘F）")
                        // 搜索框里按 ↓ 回到列表，接着用上下键换一条
                        .onKeyPress(.downArrow) { listFocused = true; return .handled }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.text3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 0.5))
                HStack(spacing: 2) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Button { filter = f } label: {
                            Text(f.rawValue).font(.system(size: 12, weight: filter == f ? .medium : .regular))
                                .foregroundStyle(filter == f ? Theme.text : Theme.text2)
                                .padding(.horizontal, 9).frame(height: 24)
                                .background(filter == f ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == f ? .isSelected : [])
                    }
                }
            }
            .padding(14)
            Hairline()
            if visible.isEmpty {
                emptyList
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                            ForEach(days, id: \.day) { group in
                                HStack(spacing: 6) {
                                    Text(HistoryFormat.day(group.day)).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
                                    Text("\(group.threads.count)").font(.system(size: 12)).foregroundStyle(Theme.text3)
                                }
                                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
                                ForEach(group.threads) { thread in
                                    row(thread).id(thread.id)
                                }
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($listFocused)
                    .onKeyPress(.downArrow) { move(1, proxy); return .handled }
                    .onKeyPress(.upArrow) { move(-1, proxy); return .handled }
                }
            }
        }
        .background(Theme.bg)
    }

    private func row(_ thread: AskHistoryThread) -> some View {
        let isSelected = thread.id == selected?.id
        let first = thread.turns[0]
        return Button { selectedID = thread.id; listFocused = true } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: HistoryKind.of(thread).symbol).font(.system(size: 11)).foregroundStyle(Theme.text3)
                    .frame(width: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    highlighted(first.question, size: 13, weight: .medium, color: Theme.text)
                    highlighted(HistoryFormat.preview(first.answer), size: 12, weight: .regular, color: Theme.text2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(HistoryFormat.time(thread.startedAt)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
                    if thread.turns.count > 1 {
                        Text("\(thread.turns.count) 轮").font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("复制问答") { copy(thread) }
            Divider()
            Button("删除这一条…") { delete(thread.id) }
        }
    }

    /// 搜索词命中的地方加粗
    private func highlighted(_ text: String, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        var attr = AttributedString(text)
        attr.font = .system(size: size, weight: weight)
        attr.foregroundColor = color
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            var searchStart = attr.startIndex
            while searchStart < attr.endIndex, let range = attr[searchStart...].range(of: q, options: .caseInsensitive) {
                attr[range].font = .system(size: size, weight: .bold)
                attr[range].backgroundColor = Theme.warn.opacity(0.22)
                searchStart = range.upperBound
            }
        }
        return Text(attr).lineLimit(1)
    }

    private var emptyList: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "clock" : "magnifyingglass").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.text3)
            Text(query.isEmpty && filter == .all ? "还没有记录" : "没有找到").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            Text(query.isEmpty && filter == .all ? "按住提问键问一个问题，答完就会出现在这里。" : "换个词，或者点「全部」。")
                .font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble").font(.system(size: 32, weight: .light)).foregroundStyle(Theme.text3)
            Text("问过的问题会在这里").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            Text("连同发给 AI 的截图、回答和找到的图，只存在这台 Mac 上。").font(.system(size: 12)).foregroundStyle(Theme.text2)
        }
    }

    // MARK: 动作

    private func move(_ delta: Int, _ proxy: ScrollViewProxy) {
        let list = visible
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selected?.id } ?? 0
        let next = list[max(0, min(list.count - 1, index + delta))]
        selectedID = next.id
        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(next.id) }
    }

    private func copy(_ thread: AskHistoryThread) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(HistoryFormat.copyText(thread), forType: .string)
    }

    private func delete(_ id: String) {
        let alert = NSAlert()
        alert.messageText = "删除这一条问答？"
        alert.informativeText = "问题、回答、截图和找到的图都会从这台 Mac 上删掉，不能恢复。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let list = visible
        let index = list.firstIndex { $0.id == id }
        do {
            try AskHistoryStore.shared.deleteThread(id)
        } catch {
            NSAlert(error: error).runModal()
        }
        threads = AskHistoryStore.shared.threads()
        NotificationCenter.default.post(name: .askFreeHistoryDidChange, object: nil)   // 侧栏和页头的条数
        // 删掉后选中下面那一条
        if let index {
            let remaining = visible
            selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
    }
}

// MARK: - 右栏：整段问答

struct HistoryDetail: View {
    let thread: AskHistoryThread
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer()
                iconButton("doc.on.doc", help: "复制问答") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(HistoryFormat.copyText(thread), forType: .string)
                }
                iconButton("trash", help: "删除这一条", action: onDelete)
                Menu {
                    Button("在访达中显示历史文件夹") {
                        NSWorkspace.shared.activateFileViewerSelecting([AskHistoryStore.shared.fileURL])
                    }
                    Divider()
                    Button("清空全部历史…", role: .destructive) { clearAll() }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(Theme.text2)
                        .frame(width: 28, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多")
                .accessibilityLabel("更多")
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(thread.turns[0].question).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Image(systemName: HistoryKind.of(thread).symbol).font(.system(size: 10))
                            Text(meta)
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.text3)
                    }
                    ForEach(thread.turns.indices, id: \.self) { i in
                        turn(thread.turns[i], index: i)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.bg)
    }

    private var meta: String {
        var parts = [HistoryKind.of(thread).title, HistoryFormat.shortTime(thread.startedAt)]
        if thread.turns.count > 1 { parts.append("\(thread.turns.count) 轮") }
        if thread.turns.contains(where: { $0.searched == true }) { parts.append("联网查过") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func turn(_ turn: AskHistoryTurn, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if index > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left").font(.system(size: 10))
                        Text("追问 · \(HistoryFormat.time(turn.at))")
                    }
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                    Text(turn.question).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                }
                .padding(.top, 10)
            }
            if turn.hasScreenshot { screenshots(turn) }
            HistoryAnswerText(markdown: turn.answer)
            if !turn.images.isEmpty { images(turn) }
        }
    }

    private func screenshots(_ turn: AskHistoryTurn) -> some View {
        let urls = AskHistoryStore.shared.screenshotURLs(turnID: turn.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                LocalThumb(url: urls.closeUp, maxWidth: 360, height: 150)
                LocalThumb(url: urls.overview, maxWidth: 220, height: 150)
            }
            Text("发给 AI 的画面，红框是你指着的地方。点开看大图").font(.system(size: 11.5)).foregroundStyle(Theme.text3)
        }
    }

    private func images(_ turn: AskHistoryTurn) -> some View {
        HStack(spacing: 8) {
            ForEach(turn.images.indices, id: \.self) { i in
                let image = turn.images[i]
                let local = AskHistoryStore.shared.imageThumbURL(turnID: turn.id, index: i)
                Button {
                    AppLinks.safeOpen(image.full)
                } label: {
                    Group {
                        if let nsImage = NSImage(contentsOf: local) {
                            Image(nsImage: nsImage).resizable().scaledToFill()
                        } else {
                            AsyncImage(url: URL(string: image.thumb)) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() } else { Theme.surface }
                            }
                        }
                    }
                    .frame(width: 120, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help(image.title.isEmpty ? image.pageURL : image.title)
                .accessibilityLabel(image.title.isEmpty ? "找到的第 \(i + 1) 张图" : "第 \(i + 1) 张图：\(image.title)")
                .accessibilityHint("用浏览器打开原图")
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.text2)
                .frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func clearAll() {
        let alert = NSAlert()
        alert.messageText = "清空全部历史？"
        alert.informativeText = "所有问过的问题、回答和截图都会删掉，不能恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try AskHistoryStore.shared.deleteAll()
        } catch {
            NSAlert(error: error).runModal()
        }
        NotificationCenter.default.post(name: .askFreeHistoryDidChange, object: nil)
    }
}

/// 本机的一张截图：按比例缩到格子里，点开用「预览」看原图
private struct LocalThumb: View {
    let url: URL
    let maxWidth: CGFloat
    let height: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Theme.surface.frame(width: 160)
                }
            }
            .frame(maxWidth: maxWidth, maxHeight: height, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("点开看原图")
        .onAppear { image = NSImage(contentsOf: url) }
    }
}

/// 回答正文：和回答面板同一套轻量 Markdown（小标题、条目、**加粗**、`代码`），能选中复制
struct HistoryAnswerText: View {
    let markdown: String
    var size: CGFloat = 13.5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let text):
                    inline(text).font(.system(size: size, weight: .semibold)).padding(.top, 2)
                case .bullet(let marker, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker).font(.system(size: size)).foregroundStyle(Theme.text2).frame(minWidth: 12, alignment: .trailing)
                        inline(text).font(.system(size: size))
                    }
                case .paragraph(let text):
                    inline(text).font(.system(size: size))
                }
            }
        }
        .foregroundStyle(Theme.text)
        .lineSpacing(3)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.openURL, .safe)
    }

    private enum Line { case heading(String), bullet(String, String), paragraph(String) }

    private var lines: [Line] {
        markdown.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if line.hasPrefix("#") { return .heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)) }
            if let r = line.range(of: #"^(?:[-•·*]|\d+[.、)）])\s+"#, options: .regularExpression) {
                let marker = line[r].trimmingCharacters(in: .whitespaces)
                let shown = marker.first?.isNumber == true ? marker.trimmingCharacters(in: CharacterSet(charactersIn: ".、)）")) + "." : "•"
                return .bullet(shown, String(line[r.upperBound...]))
            }
            return .paragraph(line)
        }
    }

    private func inline(_ s: String) -> Text {
        if let parsed = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(parsed)
        }
        return Text(s)
    }
}
