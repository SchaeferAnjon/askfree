import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension Notification.Name {
    /// 历史里多了一轮问答（答完一题时发）
    static let askFreeHistoryDidChange = Notification.Name("AskFreeHistoryDidChange")
}

enum HistoryPage {
    /// 一次列出多少个话题，更早的点「显示更早的」再加
    static let pageSize = 50
}

/// 话题行头部的点击：带上是哪个话题
private final class HistoryClick: NSClickGestureRecognizer {
    var threadID = ""
}

extension SettingsWindowController {
    // MARK: - Page: History

    func buildHistory(into stack: NSStackView) {
        stack.addArrangedSubview(pageHeader(eyebrow: "ASK FREE / 历史", title: "历史",
                                             sub: "问过的问题和回答只存在这台 Mac 上，只有文字，不存截图。"))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        let search = NSSearchField()
        search.placeholderString = "搜索问题或回答"
        search.stringValue = historyQuery
        search.target = self
        search.action = #selector(historySearchChanged(_:))
        search.translatesAutoresizingMaskIntoConstraints = false
        search.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let clear = VPButton(title: "清空全部", style: .danger, size: .small,
                             theme: theme, target: self, action: #selector(clearHistoryTapped))
        historyClearButton = clear

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let toolbar = NSStackView(views: [search, spacer, clear])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        stack.addArrangedSubview(toolbar)
        stack.setCustomSpacing(24, after: toolbar)

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        historyList = list
        stack.addArrangedSubview(list)
        reloadHistoryList()
    }

    /// 按当前搜索词重建话题列表：按天分组，最近的在前
    func reloadHistoryList() {
        guard let list = historyList else { return }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let all = AskHistoryStore.shared.threads()
        let query = historyQuery.trimmingCharacters(in: .whitespaces)
        let threads = query.isEmpty ? all : all.filter { $0.matches(query) }
        historyClearButton?.isHidden = all.isEmpty

        if threads.isEmpty {
            let text = query.isEmpty ? "还没有记录。按快捷键问一个问题，答完就会出现在这里。" : "没有找到含「\(query)」的问答。"
            let card = makeCard()
            let empty = label(text, size: 13, weight: .regular, color: theme.text3)
            let wrap = NSStackView(views: [empty])
            wrap.edgeInsets = NSEdgeInsets(top: 22, left: 20, bottom: 22, right: 20)
            mount(wrap, in: card)
            list.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            return
        }

        var days: [(day: Date, threads: [AskHistoryThread])] = []
        for thread in threads.prefix(historyLimit) {
            let day = Calendar.current.startOfDay(for: thread.updatedAt)
            if days.last?.day == day { days[days.count - 1].threads.append(thread) } else { days.append((day, [thread])) }
        }

        for (day, items) in days {
            let title = sectionTitle(Self.historyDayTitle(day))
            list.addArrangedSubview(title)
            list.setCustomSpacing(8, after: title)

            let rows = NSStackView()
            rows.orientation = .vertical
            rows.alignment = .leading
            rows.spacing = 0
            for (i, thread) in items.enumerated() {
                rows.addArrangedSubview(makeHistoryRow(thread))
                if i < items.count - 1 { rows.addArrangedSubview(makeHairline(insetH: 18)) }
            }
            for v in rows.arrangedSubviews { v.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
            let card = makeCard()
            mount(rows, in: card)
            list.addArrangedSubview(card)
            list.setCustomSpacing(24, after: card)
        }

        if threads.count > historyLimit {
            let more = VPButton(title: "显示更早的", style: .secondary, size: .small,
                                theme: theme, target: self, action: #selector(showMoreHistory))
            list.addArrangedSubview(more)
        }

        for case let v in list.arrangedSubviews where !(v is VPButton) {
            v.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
    }

    /// 一个话题：收起时是「时间 · 第一个问题 · 回答开头」一行；展开后列出每一轮问答，回答可以选中复制
    private func makeHistoryRow(_ thread: AskHistoryThread) -> NSView {
        let expanded = historyExpanded.contains(thread.id)
        let first = thread.turns[0]

        let time = label(Self.historyTimeFormatter.string(from: thread.startedAt), size: 12, weight: .regular, color: theme.text3)
        time.font = monoFont(size: 12, weight: .regular)
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        let question = label(first.question, size: 14, weight: .medium, color: theme.text)
        let textColumn = NSStackView(views: [question])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 3
        if !expanded {
            question.maximumNumberOfLines = 1
            question.lineBreakMode = .byTruncatingTail
            let preview = AnswerPanel.plainText(fromMarkdown: first.answer)
                .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "`", with: "")
            let previewLabel = label(preview, size: 12, weight: .regular, color: theme.text3)
            previewLabel.maximumNumberOfLines = 1
            previewLabel.lineBreakMode = .byTruncatingTail
            textColumn.addArrangedSubview(previewLabel)
        }

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                accessibilityDescription: expanded ? "收起" : "展开")
        chevron.contentTintColor = theme.text3
        let trailing = NSStackView(views: [chevron])
        trailing.orientation = .horizontal
        trailing.alignment = .centerY
        trailing.spacing = 10
        if thread.turns.count > 1 {
            trailing.insertArrangedSubview(label("\(thread.turns.count) 轮", size: 12, weight: .regular, color: theme.text3), at: 0)
        }

        let header = NSStackView(views: [time, textColumn, trailing])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 14
        header.edgeInsets = NSEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        layoutTextColumn(textColumn, beside: trailing)
        let click = HistoryClick(target: self, action: #selector(toggleHistoryThread(_:)))
        click.threadID = thread.id
        header.addGestureRecognizer(click)

        let row = NSStackView(views: [header])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 0
        header.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        row.menu = makeHistoryMenu(thread.id)

        guard expanded else { return row }

        // 展开：和头部的问题左对齐（让过时间那一列）
        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        body.edgeInsets = NSEdgeInsets(top: 0, left: 20 + time.intrinsicContentSize.width + 14, bottom: 16, right: 20)
        for (i, turn) in thread.turns.enumerated() {
            if i > 0 {
                let eyebrow = label("追问 · \(Self.historyTimeFormatter.string(from: turn.at))", size: 11, weight: .medium, color: theme.text3)
                body.addArrangedSubview(eyebrow)
                body.setCustomSpacing(4, after: eyebrow)
                body.addArrangedSubview(label(turn.question, size: 14, weight: .medium, color: theme.text))
            }
            let answer = NSTextField(labelWithAttributedString: historyAnswerText(turn.answer))
            answer.isSelectable = true
            answer.allowsEditingTextAttributes = true   // 选中时保住加粗、缩进，不退回纯文本
            answer.maximumNumberOfLines = 0
            answer.lineBreakMode = .byWordWrapping
            answer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            body.addArrangedSubview(answer)
            body.setCustomSpacing(18, after: answer)
        }

        let copy = VPButton(title: "复制", style: .secondary, size: .small,
                            theme: theme, target: self, action: #selector(copyHistoryThread(_:)))
        copy.identifier = NSUserInterfaceItemIdentifier(thread.id)
        let delete = VPButton(title: "删除", style: .danger, size: .small,
                              theme: theme, target: self, action: #selector(deleteHistoryThread(_:)))
        delete.identifier = NSUserInterfaceItemIdentifier(thread.id)
        let actions = NSStackView(views: [copy, delete])
        actions.orientation = .horizontal
        actions.spacing = 8
        body.addArrangedSubview(actions)

        for v in body.arrangedSubviews where v !== actions {
            v.widthAnchor.constraint(equalTo: body.widthAnchor,
                                     constant: -(body.edgeInsets.left + body.edgeInsets.right)).isActive = true
        }
        row.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        return row
    }

    private func makeHistoryMenu(_ threadID: String) -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [("复制", #selector(copyHistoryThread(_:))), ("删除", #selector(deleteHistoryThread(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = threadID
            menu.addItem(item)
        }
        return menu
    }

    /// 回答正文：和回答面板同一套轻量 Markdown（小标题、条目、**加粗**），排成可选中的富文本
    private func historyAnswerText(_ md: String) -> NSAttributedString {
        let size: CGFloat = 13.5
        let out = NSMutableAttributedString()
        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            style.paragraphSpacing = 8
            var font = NSFont.systemFont(ofSize: size)
            var text = line
            if line.hasPrefix("#") {
                text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                font = .systemFont(ofSize: size, weight: .semibold)
                style.paragraphSpacingBefore = out.length == 0 ? 0 : 4
            } else if let r = line.range(of: #"^(?:[-•·*]|\d+[.、)）])\s+"#, options: .regularExpression) {
                let marker = line[r].trimmingCharacters(in: .whitespaces)
                let bullet = marker.first?.isNumber == true
                    ? marker.trimmingCharacters(in: CharacterSet(charactersIn: ".、)）")) + "."
                    : "•"
                text = bullet + "\t" + line[r.upperBound...]
                style.tabStops = [NSTextTab(textAlignment: .left, location: 20)]
                style.headIndent = 20
                style.firstLineHeadIndent = 4
                style.paragraphSpacing = 5
            }
            if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
            let start = out.length
            out.append(historyInline(text, font: font))
            out.addAttributes([.paragraphStyle: style, .foregroundColor: theme.text], range: NSRange(location: start, length: out.length - start))
        }
        return out
    }

    /// 行内的 **加粗** 和 `代码`；符号不配对解析不了就按原文
    private func historyInline(_ s: String, font: NSFont) -> NSAttributedString {
        guard s.contains("*") || s.contains("`"),
              let parsed = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: s, attributes: [.font: font])
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = font
            if intent.contains(.code) { runFont = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular) }
            if intent.contains(.stronglyEmphasized) { runFont = .systemFont(ofSize: font.pointSize, weight: .semibold) }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: [.font: runFont]))
        }
        return out
    }

    private static let historyTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 今天 / 昨天 / 10月19日 周日 / 2025年10月19日
    private static func historyDayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = calendar.isDate(day, equalTo: Date(), toGranularity: .year) ? "M月d日 EEE" : "yyyy年M月d日"
        return f.string(from: day)
    }

    // MARK: - Actions

    @objc private func historySearchChanged(_ sender: NSSearchField) {
        guard sender.stringValue != historyQuery else { return }
        historyQuery = sender.stringValue
        historyLimit = HistoryPage.pageSize
        reloadHistoryList()
    }

    @objc func historyDidChange() {
        reloadHistoryList()
    }

    @objc private func toggleHistoryThread(_ sender: HistoryClick) {
        if historyExpanded.remove(sender.threadID) == nil { historyExpanded.insert(sender.threadID) }
        reloadHistoryList()
    }

    @objc private func showMoreHistory() {
        historyLimit += HistoryPage.pageSize
        reloadHistoryList()
    }

    /// 按钮把话题 id 放在 identifier 里，右键菜单放在 representedObject 里
    private func historyThreadID(_ sender: Any) -> String? {
        (sender as? NSMenuItem)?.representedObject as? String ?? (sender as? NSView)?.identifier?.rawValue
    }

    @objc private func copyHistoryThread(_ sender: Any) {
        guard let id = historyThreadID(sender),
              let thread = AskHistoryStore.shared.threads().first(where: { $0.id == id }) else { return }
        let text = thread.turns.map { "问：\($0.question)\n\n\(AnswerPanel.plainText(fromMarkdown: $0.answer))" }
            .joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func deleteHistoryThread(_ sender: Any) {
        guard let id = historyThreadID(sender) else { return }
        do {
            try AskHistoryStore.shared.deleteThread(id)
        } catch {
            showAlert(title: "删除失败", message: error.localizedDescription)
        }
        historyExpanded.remove(id)
        reloadHistoryList()
    }

    @objc private func clearHistoryTapped() {
        let alert = NSAlert()
        alert.messageText = "清空全部历史？"
        alert.informativeText = "所有问过的问题和回答都会删掉，不能恢复。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try AskHistoryStore.shared.deleteAll()
        } catch {
            showAlert(title: "清空失败", message: error.localizedDescription)
        }
        historyExpanded.removeAll()
        reloadHistoryList()
    }
}
