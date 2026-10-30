// NotesView.swift
// Ask Free
//
// 「历史」页里看的每日图文笔记（design/daily-notes/redesign，方向 A，加 export.md 的「用浏览器打开」「导出 PDF」）：
// 页头（返回、换一天、重新整理、用浏览器打开、导出 PDF）、能收成细条的目录、这一天的小结和每个问题一节、
// 底部的 Anki 栏、右下的提示条。颜色和尺寸都用 Theme，浅色深色都跟着窗口走。

import SwiftUI
import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif
#if canImport(AnswerRender)
import AnswerRender
#endif

// MARK: - 页头

struct NotesHeaderView: View {
    @ObservedObject var model: NotesModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsCount: true)
            row(showsCount: false)   // 最窄的窗口先藏「8 个问题」，按钮的字都留着
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
    }

    private func row(showsCount: Bool) -> some View {
        HStack(spacing: 8) {
            Button { model.close() } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                    Text("历史").font(.system(size: 13))
                }
                .foregroundStyle(Theme.text2)
                .padding(.leading, 4).padding(.trailing, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotesHoverStyle(radius: 6))
            .padding(.leading, -6)
            .accessibilityLabel("回到历史列表")
            .help("回到历史列表")

            dayButton

            Spacer(minLength: 8)
            if showsCount {
                Text(countText).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
                    .lineLimit(1).fixedSize()
                    .padding(.trailing, 4)
            }
            HStack(spacing: 2) {
                headerButton("重新整理", symbol: "arrow.clockwise", busy: false, enabled: model.phase != .generating,
                             disabledHint: "整理完才能用", help: "照现在的历史重新整理这一天") { model.regenerate() }
                headerButton("用浏览器打开", symbol: "arrow.up.right.square", busy: model.busyExport == .browser,
                             enabled: model.exportAvailability == .ready && model.busyExport == nil, disabledHint: exportHint,
                             help: "在默认浏览器里打开这一天的笔记") { model.openInBrowser() }
                headerButton("导出 PDF", symbol: "arrow.down.doc", busy: model.busyExport == .pdf,
                             enabled: model.exportAvailability == .ready && model.busyExport == nil, disabledHint: exportHint,
                             help: "把这一天的笔记存成 PDF") { model.exportPDF(window: SettingsWindowController.shared?.window) }
            }
        }
    }

    private var countText: String {
        guard let day = model.day else { return "" }
        let total = day.threads.count
        if case .stopped = model.phase { return "\(total) 个问题，整理好 \(model.finished.count) 个" }
        if model.phase == .generating { return "\(total) 个问题" }
        if let status = model.status, status.done < status.total { return "\(total) 个问题，整理好 \(model.finished.count) 个" }
        return "\(total) 个问题"
    }

    private var exportHint: String {
        model.exportAvailability == .generating ? "整理完才能用" : "这一天还没有整理好的笔记"
    }

    private func headerButton(_ title: String, symbol: String, busy: Bool, enabled: Bool, disabledHint: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).scaleEffect(0.55).frame(width: 14, height: 14)
                } else {
                    Image(systemName: symbol).font(.system(size: 13)).frame(width: 14, height: 14)
                }
                Text(title).font(.system(size: 13))
            }
            .foregroundStyle(enabled || busy ? Theme.text2 : Theme.text3)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotesHoverStyle(radius: 6))
        .disabled(!enabled)
        .help(enabled ? help : disabledHint)
        .accessibilityLabel(title)
        .accessibilityHint(enabled ? help : disabledHint)
    }

    private var dayButton: some View {
        Button { model.pickerOpen.toggle() } label: {
            HStack(spacing: 6) {
                Text(model.day.map { NotesFormat.dayTitle($0.date) } ?? "").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                if model.day.map({ Calendar.current.isDateInToday($0.date) }) == true {
                    Text("今天").font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text3)
            }
            .padding(.leading, 8).padding(.trailing, 6)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotesHoverStyle(radius: 6, active: model.pickerOpen))
        .accessibilityLabel("换一天，现在是 \(model.day.map { NotesFormat.dayTitle($0.date) } ?? "")")
    }
}

/// 页头和目录里的无边框按钮：指上去换灰底
struct NotesHoverStyle: ButtonStyle {
    var radius: CGFloat = 6
    var active = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background((hovering || active || configuration.isPressed) ? Theme.hover : Color.clear, in: RoundedRectangle(cornerRadius: radius))
            .onHover { hovering = $0 }
    }
}

enum NotesFormat {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f
    }()

    static func dayTitle(_ date: Date) -> String { dayFormatter.string(from: date) }
}

// MARK: - 月历（换一天）

/// 换一天的月历：浮在页头下面的卡片（卡片底、12 圆角、弹层阴影），由主窗口盖在页面上
struct NotesCalendarView: View {
    @ObservedObject var model: NotesModel
    @State private var month: Date

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2   // 周一排第一列
        return c
    }()

    init(model: NotesModel) {
        self.model = model
        let start = model.day?.date ?? Date()
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: start)?.start ?? start)
    }

    private var counts: [String: Int] { Dictionary(uniqueKeysWithValues: model.days.map { ($0.key, $0.threads.count) }) }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: month)
    }

    /// 前后还有没有问过问题的月份
    private var hasEarlier: Bool { model.days.contains { $0.date < month } }
    private var hasLater: Bool { model.days.contains { $0.date >= (calendar.date(byAdding: .month, value: 1, to: month) ?? month) } }

    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let lead = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(monthTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Spacer()
                monthButton("chevron.left", label: "上个月", enabled: hasEarlier) { shift(-1) }
                monthButton("chevron.right", label: "下个月", enabled: hasLater) { shift(1) }
            }
            .padding(.horizontal, 4).padding(.bottom, 8)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                    Text($0).font(.system(size: 12)).foregroundStyle(Theme.text3).frame(height: 22)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 40) }
                }
            }
            Hairline().padding(.top, 8)
            Text("数字是那天问了几个问题；没整理过的那天点了就开始整理。")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.top, 8)
        }
        .padding(12)
        .frame(width: 300)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderStrong, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("选日子")
        .onExitCommand { model.pickerOpen = false }
    }

    private func shift(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) { month = next }
    }

    private func monthButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(enabled ? Theme.text2 : Theme.text3.opacity(0.5))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(NotesHoverStyle(radius: 6))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func dayCell(_ date: Date) -> some View {
        let key = HistoryDay.key(for: date)
        let count = counts[key]
        let isCurrent = key == model.openDay
        let isToday = calendar.isDateInToday(date)
        return Button {
            model.open(day: key)
        } label: {
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: date))").font(.system(size: 13, weight: isCurrent ? .medium : .regular).monospacedDigit())
                    .foregroundStyle(count == nil ? Theme.text3 : Theme.text)
                if let count {
                    Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.text2)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(isCurrent ? Theme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isToday ? Theme.borderStrong : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(NotesHoverStyle(radius: 6))
        .disabled(count == nil)
        .accessibilityLabel(count.map { "\(NotesFormat.dayTitle(date))，问了 \($0) 个问题" } ?? NotesFormat.dayTitle(date))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

// MARK: - 笔记页（目录 + 正文 + Anki 栏）

struct NotesBodyView: View {
    @ObservedObject var model: NotesModel
    @State private var current = "ov"
    @State private var offsets: [String: CGRect] = [:]
    @State private var viewportHeight: CGFloat = 600
    @State private var columnWidth: CGFloat = 640
    @State private var zoomed: NotesEntry?
    @State private var scroller = ScrollerBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            VStack(spacing: 0) {
                if let outdated = model.outdated { outdatedBanner(outdated) }
                HStack(spacing: 0) {
                    NotesTOCView(model: model, current: current) { id in jump(to: id) } toggle: {
                        let keep = current
                        let before = offsets[keep]?.minY
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { model.tocCollapsed.toggle() }
                        // 当前那一节停在原来的高度，不跳（目录宽度一变，正文宽度跟着变，各节的高度也变）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            if let before, let after = offsets[keep]?.minY { scroller.scroll(by: after - before) }
                        }
                    }
                    .frame(width: model.tocCollapsed ? 44 : 200)
                    Rectangle().fill(Theme.border).frame(width: 0.5)
                    scrollColumn
                }
                Hairline()
                NotesAnkiBar(model: model)
            }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    NotesToastView(toast: toast) { model.dismissToast(toast.id) }
                        .padding(.bottom, 64)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.toast)
            .overlay { if let zoomed { lightbox(zoomed) } }
            .background(Theme.bg)
        }
        .onChange(of: model.openDay) { _, _ in current = "ov"; offsets = [:] }
    }

    private func jump(to id: String) {
        // 一下跳过去，不滚动画（长页面里动画滚过去反而看不清停在哪）
        if let frame = offsets[id] { scroller.scroll(by: frame.minY) }
        current = id
    }

    // MARK: 滚动列

    private var scrollColumn: some View {
        GeometryReader { outer in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    top.id("ov").trackSection("ov")
                    ForEach(model.entries) { entry in
                        NotesSectionView(model: model, entry: entry, columnWidth: columnWidth, zoom: { zoomed = $0 })
                            .id(entry.id)
                            .trackSection(entry.id)
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 40)
                .frame(maxWidth: .infinity)
                .background(GeometryReader { geo in
                    Color.clear.onAppear { columnWidth = geo.size.width - 48 }
                        .onChange(of: geo.size.width) { _, w in columnWidth = w - 48 }
                })
                .background(ScrollerFinder(box: scroller))
            }
            .coordinateSpace(name: "notes-scroll")
            .onPreferenceChange(SectionFramesKey.self) { frames in
                offsets = frames
                updateCurrent()
            }
            .onAppear { viewportHeight = outer.size.height }
            .onChange(of: outer.size.height) { _, h in viewportHeight = h; updateCurrent() }
        }
    }

    private func updateCurrent() {
        let order = ["ov"] + model.entries.map(\.id)
        var cur = "ov"
        for id in order {
            if let frame = offsets[id], frame.minY <= 140 { cur = id }
        }
        // 滚到底了：最后一节算当前（它的头永远到不了 140）
        if let last = order.last, last != "ov", let frame = offsets[last], frame.maxY <= viewportHeight + 40, frame.minY < viewportHeight - 80 { cur = last }
        if cur != current { current = cur }
    }

    // MARK: 顶上：小结 / 整理进度

    @ViewBuilder private var top: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.phase {
            case .generating:
                NotesProgressCard(model: model)
            case .stopped:
                NotesProgressCard(model: model)
            case .failed(let failure):
                NotesFailureCard(model: model, failure: failure)
            case .idle:
                summary
            }
        }
    }

    @ViewBuilder private var summary: some View {
        if let notes = model.notes, let day = model.day {
            VStack(alignment: .leading, spacing: 0) {
                Text(statLine(day)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3).padding(.bottom, 8)
                if !notes.summary.isEmpty {
                    AnswerBody(markdown: notes.summary, streaming: false, style: .history).equatable()
                        .environment(\.openURL, .answerLink)
                }
                if !notes.keep.isEmpty {
                    Text("记住这几条").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3).padding(.top, 14).padding(.bottom, 6)
                    AnswerBody(markdown: notes.keep.map { "- " + $0 }.joined(separator: "\n"), streaming: false, style: .history).equatable()
                        .environment(\.openURL, .answerLink)
                }
            }
        }
    }

    private func statLine(_ day: HistoryDay) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let times = day.threads.map { formatter.string(from: HistoryDay.moment(of: $0, on: day.date)) }
        return "\(day.threads.count) 个问题" + (times.count > 1 ? " · \(times.first!) 到 \(times.last!)" : "")
    }

    // MARK: 整理之后又问了新的

    private func outdatedBanner(_ info: (new: Int, followedUp: Int)) -> some View {
        let text: String
        if info.new > 0 {
            text = "这一天又问了 \(info.new) 个问题，笔记里还没有" + (info.followedUp > 0 ? "，另有 \(info.followedUp) 个又追问了" : "")
        } else {
            text = "有 \(info.followedUp) 个问题整理之后又追问了，笔记里还是以前的"
        }
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Theme.warn).frame(width: 7, height: 7)
                Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Button("重新整理") { model.regenerate() }
                    .buttonStyle(NotesSmallButtonStyle())
            }
            .padding(.horizontal, 24)
            .frame(height: 40)
            .background(Theme.surface)
            Hairline()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 放大截图

    private func lightbox(_ entry: NotesEntry) -> some View {
        ZStack {
            Color.black.opacity(0.55).onTapGesture { zoomed = nil }
            NotesLightboxImage(turnID: entry.thread.turns[0].id)
                .padding(40)
            VStack {
                HStack {
                    Spacer()
                    Button { zoomed = nil } label: {
                        Text("关闭").font(.system(size: 12)).foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭大图")
                }
                Spacer()
            }
            .padding(14)
        }
        .onExitCommand { zoomed = nil }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: 滚动位置：每一节报自己的位置，目录跟着标出当前这一节

/// 笔记正文外面那个 NSScrollView：目录点一下直接把它滚到那一节（不走 SwiftUI 的 scrollTo，它在窗口被挡住时不动）
final class ScrollerBox {
    weak var view: NSScrollView?

    /// 往下滚 dy（负数往上）；滚不出头尾
    func scroll(by dy: CGFloat) {
        guard let view, let document = view.documentView else { return }
        let clip = view.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        let y = min(max(0, clip.bounds.origin.y + dy), maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        view.reflectScrolledClipView(clip)
    }
}

private struct ScrollerFinder: NSViewRepresentable {
    let box: ScrollerBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { box.view = view.enclosingScrollView }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if box.view == nil { DispatchQueue.main.async { box.view = view.enclosingScrollView } }
    }
}

struct SectionFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension View {
    func trackSection(_ id: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: SectionFramesKey.self, value: [id: geo.frame(in: .named("notes-scroll"))])
        })
    }
}

// MARK: - 目录

private struct NotesTOCView: View {
    @ObservedObject var model: NotesModel
    let current: String
    let jump: (String) -> Void
    let toggle: () -> Void

    var body: some View {
        let collapsed = model.tocCollapsed
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if !collapsed { Text("目录").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3).padding(.leading, 8) }
                if !collapsed { Spacer(minLength: 0) }
                Button(action: toggle) {
                    Image(systemName: "sidebar.left").font(.system(size: 13)).foregroundStyle(Theme.text2)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(NotesHoverStyle(radius: 6))
                .help(collapsed ? "展开目录" : "收起目录")
                .accessibilityLabel(collapsed ? "展开目录" : "收起目录")
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .frame(height: 40)
            .padding(.horizontal, collapsed ? 0 : 8)
            ScrollView {
                VStack(alignment: .leading, spacing: collapsed ? 4 : 0) {
                    item(id: "ov", number: nil, title: "这一天", entry: nil)
                    ForEach(model.entries) { entry in
                        item(id: entry.id, number: entry.number, title: entry.item?.title ?? clipped(entry.thread.turns[0].question), entry: entry)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
        }
        .background(Theme.bg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("目录")
    }

    private func clipped(_ q: String) -> String { q.count > 20 ? String(q.prefix(20)) + "…" : q }

    private func item(id: String, number: Int?, title: String, entry: NotesEntry?) -> some View {
        let collapsed = model.tocCollapsed
        let on = current == id
        let waiting = entry != nil && entry?.item == nil
        let working = waiting && model.currentNumber == number
        let picked = entry.map { model.picks.contains($0.thread.id) } ?? false
        return Button { jump(id) } label: {
            HStack(alignment: .top, spacing: 8) {
                Group {
                    if let number {
                        Text("\(number)").font(.system(size: 12).monospacedDigit())
                    } else {
                        Image(systemName: "list.bullet").font(.system(size: 12))
                    }
                }
                .foregroundStyle(on ? Theme.text : Theme.text3)
                .frame(width: collapsed ? nil : 14, alignment: collapsed ? .center : .trailing)
                .padding(.top, collapsed ? 0 : 0)
                if !collapsed {
                    Text(title).font(.system(size: 12.5)).foregroundStyle(waiting ? Theme.text3 : (on ? Theme.text : Theme.text2))
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if working {
                        ProgressView().controlSize(.small).scaleEffect(0.5).frame(width: 12, height: 12).padding(.top, 2)
                    } else if picked {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text2).padding(.top, 3)
                    }
                }
            }
            .padding(.horizontal, collapsed ? 0 : 8).padding(.vertical, collapsed ? 0 : 6)
            .frame(width: collapsed ? 28 : nil, height: collapsed ? 28 : nil)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .background(on ? Theme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topTrailing) {
                if collapsed && picked { Circle().fill(Theme.text2).frame(width: 5, height: 5).padding(3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NotesHoverStyle(radius: 6))
        .help(collapsed ? title : "")
        .accessibilityLabel(number.map { "第 \($0) 个：\(title)" } ?? title)
        .accessibilityValue(picked ? "已选" : (waiting ? "还没整理" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - 一个问题一节

private struct NotesSectionView: View {
    @ObservedObject var model: NotesModel
    let entry: NotesEntry
    let columnWidth: CGFloat
    let zoom: (NotesEntry) -> Void

    private var picked: Bool { model.picks.contains(entry.thread.id) }
    private var hasShot: Bool { entry.thread.turns[0].hasScreenshot }
    private var kind: String {
        switch entry.thread.turns[0].via {
        case "type": return "打字问"
        case "plain": return "只提问"
        case "screen": return "看屏幕问"
        default: return hasShot ? "看屏幕问" : "只提问"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Theme.border).frame(height: 0.5).padding(.top, 24)
            head
            content.padding(.leading, 26)
        }
        .padding(.top, 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(entry.number) 个问题：\(entry.thread.turns[0].question)")
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { model.togglePick(entry) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(picked ? Theme.ink : Theme.elevated)
                    RoundedRectangle(cornerRadius: 4).stroke(picked ? Theme.ink : Theme.borderStrong, lineWidth: 1)
                    if picked { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.onInk) }
                }
                .frame(width: 16, height: 16)
                .opacity(entry.item == nil ? 0.4 : 1)
                .padding(.top, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entry.item == nil || model.phase == .generating)
            .help("选这个问题导入 Anki")
            .accessibilityLabel("选第 \(entry.number) 个问题导入 Anki")
            .accessibilityValue(picked ? "已选" : "没选")
            .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 3) {
                (Text("\(entry.number)  ").foregroundStyle(Theme.text3).fontWeight(.medium)
                    + Text(entry.thread.turns[0].question).foregroundStyle(Theme.text))
                    .font(.system(size: 15, weight: .semibold))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("\(entry.time) · \(kind)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
                    if model.isInAnki(entry) {
                        Text("已在 Anki").font(.system(size: 12)).foregroundStyle(Theme.text2)
                            .padding(.horizontal, 6).frame(height: 18)
                            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 5))
                    }
                    Spacer(minLength: 8)
                    Button { model.showInHistory(entry) } label: {
                        HStack(spacing: 2) {
                            Text("在历史里看").font(.system(size: 12))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 6).frame(height: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NotesHoverStyle(radius: 5))
                    .accessibilityLabel("在历史里看第 \(entry.number) 个问题")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let item = entry.item {
            let width = max(0, columnWidth - 26)
            if hasShot && width >= 520 {
                let shotWidth = (width - 20) * 1.15 / 2.15
                HStack(alignment: .top, spacing: 20) {
                    NotesShotView(turnID: entry.thread.turns[0].id, width: shotWidth) { zoom(entry) }
                    points(item).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if hasShot { NotesShotView(turnID: entry.thread.turns[0].id, width: min(width, 520)) { zoom(entry) } }
                    points(item)
                }
            }
        } else {
            skeleton
        }
    }

    private func points(_ item: DayNoteItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("回答的要点").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3)
            AnswerBody(markdown: item.points, streaming: false, style: .history).equatable()
                .environment(\.openURL, .answerLink)
        }
    }

    /// 还没轮到的问题：灰条占位，整理好换成内容
    private var skeleton: some View {
        let width = max(0, columnWidth - 26)
        return HStack(alignment: .top, spacing: 20) {
            if hasShot && width >= 520 {
                RoundedRectangle(cornerRadius: 8).fill(Theme.hover).aspectRatio(16 / 10, contentMode: .fit)
                    .frame(width: (width - 20) * 1.15 / 2.15)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach([0.4, 1.0, 0.86, 0.7], id: \.self) { fraction in
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 5).fill(Theme.hover).frame(width: geo.size.width * fraction, height: 10)
                    }
                    .frame(height: 10)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }
}

// MARK: 截图

/// 本机一张截图：版面先按图的比例留好位置，再在后台解码缩小的图，不在主线程上读大图
private struct NotesShotView: View {
    let turnID: String
    let width: CGFloat
    let zoom: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false

    private var url: URL { AskHistoryStore.shared.screenshotURLs(turnID: turnID).closeUp }
    private var ratio: CGFloat { NotesImage.aspectRatio(of: url) ?? 16.0 / 10 }
    private var height: CGFloat { min(width / ratio, 360) }

    var body: some View {
        Button(action: zoom) {
            ZStack(alignment: .bottomTrailing) {
                Theme.surface
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                }
                if hovering {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10))
                        Text("放大").font(.system(size: 12))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
                }
            }
            .frame(width: min(width, height * ratio), height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("放大看。红框是提问时指着的地方")
        .accessibilityLabel("发给 AI 的截图，红框是提问时指着的地方")
        .accessibilityHint("放大")
        .task(id: turnID) { image = await NotesImage.thumbnail(url: url, maxPixel: 1400) }
    }
}

private struct NotesLightboxImage: View {
    let turnID: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            } else {
                ProgressView()
            }
        }
        .accessibilityLabel("截图大图")
        .task(id: turnID) { image = await NotesImage.thumbnail(url: AskHistoryStore.shared.screenshotURLs(turnID: turnID).closeUp, maxPixel: 2400) }
    }
}

enum NotesImage {
    /// 只读文件头里的宽高，不解码：版面一开始就按这个比例留位置
    static func aspectRatio(of url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? CGFloat, let h = properties[kCGImagePropertyPixelHeight] as? CGFloat, h > 0 else { return nil }
        return w / h
    }

    /// 后台解码成不超过 maxPixel 的图
    static func thumbnail(url: URL, maxPixel: Int) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: maxPixel]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
}

// MARK: - 整理进度 / 报错

private struct NotesProgressCard: View {
    @ObservedObject var model: NotesModel

    var body: some View {
        let total = model.day?.threads.count ?? 0
        let done = model.finished.count
        let generating = model.phase == .generating
        let byUser: Bool = { if case .stopped(let b) = model.phase { return b }; return true }()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if generating { ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12) }
                Text(title(generating: generating, done: done, total: total, byUser: byUser))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            }
            Text(subtitle(generating: generating, done: done, total: total, byUser: byUser))
                .font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail).padding(.top, 4)
            HStack(spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hover)
                        Capsule().fill(Theme.text2).frame(width: total == 0 ? 0 : geo.size.width * CGFloat(done) / CGFloat(total))
                    }
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                }
                .frame(height: 4)
                Text("\(done) / \(total)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text2)
                    .frame(minWidth: 36, alignment: .trailing)
                if generating {
                    Button("停下") { model.stop() }.buttonStyle(NotesSmallButtonStyle(outlined: true))
                } else {
                    Button("接着整理") { model.resume() }.buttonStyle(NotesSmallButtonStyle(outlined: true))
                }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("整理进度，\(done) / \(total)")
    }

    private func title(generating: Bool, done: Int, total: Int, byUser: Bool) -> String {
        if generating { return "正在整理\(model.day.map { Calendar.current.isDateInToday($0.date) ? "今天" : "这一天" } ?? "这一天")的 \(total) 个问题" }
        if done >= total { return "\(total) 个问题都整理好了，还差这一天的小结" }
        return byUser ? "整理了 \(done) 个，停下了" : "整理了 \(done) 个，还有 \(max(0, total - done)) 个没整理"
    }

    private func subtitle(generating: Bool, done: Int, total: Int, byUser: Bool) -> String {
        if generating {
            let current = model.entries.first { $0.item == nil }
            return current.map { "第 \($0.number) 个：\($0.thread.turns[0].question)" } ?? "正在写这一天的小结…"
        }
        if done >= total { return "点「接着整理」把小结补上，已经整理好的问题不动。" }
        return "已经整理好的留着，接着整理会从第 \(done + 1) 个开始。"
    }
}

private struct NotesFailureCard: View {
    @ObservedObject var model: NotesModel
    let failure: AskFailure

    var body: some View {
        let provider = model.providerName
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: failure.symbol).font(.system(size: 15)).foregroundStyle(Theme.text2)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "exclamationmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(failure.isError ? Theme.danger : Theme.warn))
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(failure.title(provider: provider)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(failure.detail(provider: provider)).font(.system(size: 13)).foregroundStyle(Theme.text2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !failure.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(failure.actions.enumerated()), id: \.offset) { i, item in
                            Button(item.title) { model.perform(item.action) }
                                .buttonStyle(NotesSmallButtonStyle(solid: i == 0, outlined: i != 0))
                        }
                    }
                    .padding(.top, 9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }
}

/// 笔记页里的小按钮：28 高、6 圆角；solid 是墨黑实心（一屏最多一个），outlined 描边
struct NotesSmallButtonStyle: ButtonStyle {
    var solid = false
    var outlined = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: solid ? .medium : .regular))
            .foregroundStyle(solid ? Theme.onInk : (isEnabled ? Theme.text : Theme.text3))
            .padding(.horizontal, 12).frame(height: 28)
            .background(solid ? Theme.ink : (isEnabled ? (outlined ? Theme.elevated : Color.clear) : Theme.hover), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(outlined && isEnabled ? Theme.borderStrong : .clear, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - Anki 底栏

private struct NotesAnkiBar: View {
    @ObservedObject var model: NotesModel

    var body: some View {
        let count = model.picks.count
        let generating = model.phase == .generating
        HStack(spacing: 8) {
            if generating {
                Text("整理好后能勾选问题，导入 Anki 做卡片").font(.system(size: 12)).foregroundStyle(Theme.text3)
            } else {
                Text(count > 0 ? "选了 \(count) 个" : "没选问题")
                    .font(.system(size: 13, weight: count > 0 ? .medium : .regular).monospacedDigit())
                    .foregroundStyle(count > 0 ? Theme.text : Theme.text2)
                    .frame(minWidth: 62, alignment: .leading)
                Button(model.allPicked ? "全不选" : "全选") { model.toggleAll() }
                    .buttonStyle(NotesHoverTextStyle())
                    .disabled(model.finished.isEmpty)
                if count == 0, model.bar == .idle {
                    Text("勾上问题标题前的方框，就能导入 Anki").font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
            }
            Spacer(minLength: 8)
            right(count: count, generating: generating)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Theme.bg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("导入 Anki")
    }

    @ViewBuilder private func right(count: Int, generating: Bool) -> some View {
        if generating {
            importButton(enabled: false, busy: false)
        } else {
            switch model.bar {
            case .importing:
                deck
                importButton(enabled: false, busy: true)
            case .opening:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                    Text("正在打开 Anki").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Button("再试一次") {}.buttonStyle(NotesSolidStyle()).disabled(true)
            case .noAnki(let timedOut):
                HStack(spacing: 8) {
                    Circle().fill(Theme.warn).frame(width: 7, height: 7)
                    Text("Anki 没开着，卡片还没导进去").font(.system(size: 13)).foregroundStyle(Theme.text)
                    Text(timedOut ? "等了一阵还是连不上：要在 Anki 里装 AnkiConnect 插件（代码 2055492159）" : "选的都还勾着")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                }
                Button("打开 Anki") { model.openAnki() }
                    .buttonStyle(NotesSmallButtonStyle(outlined: true))
                    .help("第一次用要在 Anki 里装 AnkiConnect 插件（代码 2055492159）")
                Button("再试一次") { model.importPicked() }.buttonStyle(NotesSolidStyle()).disabled(count == 0)
            case .result(let added, let skipped):
                HStack(spacing: 8) {
                    Circle().fill(Theme.ok).frame(width: 7, height: 7)
                    Text(resultText(added: added, skipped: skipped)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.text)
                    Text("在牌组 \(AnkiCardBuilder.deckName)").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Button("在 Anki 里看") { model.showInAnki() }.buttonStyle(NotesSmallButtonStyle(outlined: true))
                Button("好") { model.dismissBar() }.buttonStyle(NotesHoverTextStyle())
            case .failed(let message):
                HStack(spacing: 8) {
                    Circle().fill(Theme.danger).frame(width: 7, height: 7)
                    Text("没导进去").font(.system(size: 13)).foregroundStyle(Theme.text)
                    Text(message).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
                }
                Button("再试一次") { model.importPicked() }.buttonStyle(NotesSolidStyle()).disabled(count == 0)
            case .idle:
                deck
                importButton(enabled: count > 0, busy: false)
            }
        }
    }

    private func resultText(added: Int, skipped: Int) -> String {
        if added > 0 && skipped > 0 { return "加了 \(added) 张，\(skipped) 张已经有了，跳过" }
        if added > 0 { return "加了 \(added) 张" }
        return skipped == 1 ? "这张已经有了，没有重复加" : "这 \(skipped) 张都已经有了，没有重复加"
    }

    private var deck: some View {
        Text("牌组 \(AnkiCardBuilder.deckName)").font(.system(size: 12)).foregroundStyle(Theme.text2)
            .padding(.horizontal, 8).frame(height: 28)
            .help("卡片放进 Anki 的这个牌组")
    }

    private func importButton(enabled: Bool, busy: Bool) -> some View {
        Button { model.importPicked() } label: {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small).scaleEffect(0.55).frame(width: 14, height: 14) }
                else { Image(systemName: "rectangle.on.rectangle").font(.system(size: 12)).frame(width: 14, height: 14) }
                Text(busy ? "正在导入" : "导入 Anki")
            }
        }
        .buttonStyle(NotesSolidStyle())
        .disabled(!enabled)
        .accessibilityLabel(busy ? "正在导入" : "导入 Anki")
        .accessibilityHint(enabled ? "把选中的 \(model.picks.count) 个问题做成 Anki 卡片" : "先勾上要导入的问题")
    }
}

/// 墨黑实心的主按钮（一屏最多一个）；不能点时灰
private struct NotesSolidStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: isEnabled ? .medium : .regular))
            .foregroundStyle(isEnabled ? Theme.onInk : Theme.text3)
            .padding(.horizontal, 12).frame(height: 28)
            .background(isEnabled ? Theme.ink : Theme.hover, in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

private struct NotesHoverTextStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(isEnabled ? Theme.text2 : Theme.text3)
            .padding(.horizontal, 8).frame(height: 28)
            .background(hovering && isEnabled ? Theme.hover : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

// MARK: - 提示条

/// 笔记页底部正中的提示条：卡片底、12 圆角、弹层阴影、7 点状态点（成功 ok、出错 danger）；不抢焦点，出错的有 ×
private struct NotesToastView: View {
    let toast: NotesToast
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(toast.isError ? Theme.danger : Theme.ok).frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                if let detail = toast.detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2)
                        .lineLimit(1).truncationMode(.head)   // 放不下省略开头，文件名留全
                }
            }
            if toast.isError {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(Theme.text2)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(NotesHoverStyle(radius: 5))
                .accessibilityLabel("关闭提示")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(minWidth: 300, maxWidth: 520)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderStrong, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([toast.title, toast.detail].compactMap { $0 }.joined(separator: "，"))
        .onAppear { NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: [toast.title, toast.detail].compactMap { $0 }.joined(separator: "，")]) }
    }
}
