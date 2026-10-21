import Cocoa
import Combine
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension SettingsWindowController {
    // MARK: 指针问 AI

    @objc private func askScreenshotChanged(_ sender: VPToggle) {
        config.save(bool: sender.isOn, forKey: AskSettings.screenshotEnabledKey)
    }

    /// 设置页「问 AI」卡片：看屏幕、附图、思考，展开后是完整的使用说明和视觉模型手填框
    func makeAskSettingsCard() -> NSView {
        makeExpandableCard(id: "askHelp", title: "回答方式",
                           summary: "AI 怎么看屏幕、要不要联网附图、回答前要不要先想一想。",
                           rows: [makeAskScreenshotRow(),
                                  makeAskImagesRow(),
                                  makeAskThinkingToggleRow(),
                                  makeAskThinkingEffortRow()]) {
            self.makeAskHotkeyHelp("""
            怎么用：按住快捷键说出问题，松开就提问；不想一直按着，就轻点一下开始、说完再点一下结束。按住期间按 Esc 取消。回答显示在屏幕右上角，按住回答面板继续说话可以追问。

            看屏幕问：按下快捷键那一刻截鼠标所在的那块屏幕，用细红框框住鼠标附近，连同一张整屏缩略图一起发给模型。问题和屏幕无关时模型会忽略截图，照常回答。截图只用于这一次提问，不保存。

            只提问：不截屏。适合问和屏幕无关的问题，或者屏幕上有不想发出去的内容的时候。

            打字问：双击 Control（可在「设置 → 快捷键」换），双击那一刻截下屏幕，右上角弹出输入框，打完回车发送，Esc 取消。再双击一次也是收起。

            联网：DeepSeek 自己能搜；智谱、豆包的接口不能联网，同时填了千问 Key 时，需要最新信息的问题模型会自己判断、自动转给千问联网回答；也可以用「搜一下……」开头直接联网。

            撞键：两个快捷键设成同一个时，「看屏幕问 AI」优先，「只提问」不响应。一个用 Option、另一个用右 Option 时，前者只认左边那颗 Option。

            看屏幕问用的模型：按「模型」里选的那一家，自动换成同一家支持读图的模型。免费额度用完会自动降到同一家的下一个候选。想换别的填下面这一栏。
            """)
        }
    }

    /// 带标题、说明和若干设置行的卡片，底部「查看使用方法」展开更多说明
    func makeExpandableCard(id: String, title: String, summary: String, rows: [NSView],
                            detailTitle: String = "查看使用方法", details: () -> NSView) -> NSView {
        let card = makeCard()
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        text.addArrangedSubview(label(title, size: 16, weight: .semibold, color: theme.text))
        let desc = label(summary, size: 12.5, weight: .regular, color: theme.text3)
        desc.maximumNumberOfLines = 0
        text.addArrangedSubview(desc)
        column.addArrangedSubview(text)
        text.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -40).isActive = true

        for row in rows {
            column.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -40).isActive = true
        }

        let expanded = expandedCards.contains(id)
        let disclosure = VPButton(title: expanded ? "收起说明" : detailTitle,
                                  style: .secondary, size: .small, theme: theme,
                                  target: self, action: #selector(expandableCardToggled(_:)))
        disclosure.identifier = NSUserInterfaceItemIdentifier(id)
        disclosure.setAccessibilityExpanded(expanded)
        column.addArrangedSubview(disclosure)
        if expanded {
            let body = details()
            column.addArrangedSubview(body)
            body.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -40).isActive = true
        }
        mount(column, in: card)
        return card
    }

    @objc private func expandableCardToggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if expandedCards.contains(id) {
            expandedCards.remove(id)
        } else {
            expandedCards.insert(id)
        }
        invalidate(selectedPage)
    }

    func makeAskHotkeyRow(_ hotkey: AskHotkey, desc: String) -> NSView {
        let button = makeHotkeyPickerButton(for: hotkey, compact: true)
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        return makeAskCursorRow(title: hotkey.title, desc: desc, control: button) { descLabel in
            // 和别的键撞了就把说明换成撞键提示，改好了换回来
            descLabel.subscribe(SettingsStore.shared.$hotkeys.map { $0.conflict(of: hotkey) }.removeDuplicates()) { view, conflict in
                view.stringValue = conflict.map { "⚠️ \($0)，现在不会响应。" } ?? desc
            }
        }
    }

    /// 打字问 AI 的双击键选择（首页和设置页共用）。跟着 store 换选中项
    func makeTypeAskDropdown() -> VPDropdown {
        let store = SettingsStore.shared
        let items = TypeAskHotkey.choices.map { VPDropdown.Item(value: $0.rawValue, title: "双击 \($0.symbol) \($0.displayName)") }
            + [VPDropdown.Item(value: "none", title: "不设置")]
        let popup = VPDropdown(items: items, selectedValue: store.typeAsk.modifier?.rawValue ?? "none",
                               trackBg: theme.card,
                               trackBorder: Self.dropdownBorder,
                               textColor: theme.text, chevronColor: theme.text3)
        popup.setAccessibilityLabel("\(TypeAskHotkey.title)快捷键")
        popup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        popup.onSelect = { store.setTypeAsk(RecordingHotkeyModifier(rawValue: $0)) }
        popup.subscribe(store.$typeAsk.map { $0.modifier?.rawValue ?? "none" }.removeDuplicates()) { popup, value in
            if popup.selectedValue != value { popup.setSelectedValue(value) }
        }
        return popup
    }

    func makeTypeAskRow() -> NSView {
        let desc = "截下此刻的屏幕，弹出输入框打字提问，回车发送。不方便说话的时候用。回答浮窗还在时就是追问。"
        return makeAskCursorRow(title: TypeAskHotkey.title, desc: desc, control: makeTypeAskDropdown()) { descLabel in
            descLabel.subscribe(SettingsStore.shared.$typeAsk.map(\.conflict).removeDuplicates()) { view, conflict in
                view.stringValue = conflict.map { "⚠️ \($0)，现在不会响应。" } ?? desc
            }
        }
    }

    private func makeAskImagesRow() -> NSView {
        let toggle = VPToggle(theme: theme, target: self, action: #selector(askImagesChanged(_:)))
        toggle.setAccessibilityLabel("联网回答附图")
        bindToggle(toggle, to: SettingsStore.shared.$askImagesEnabled)
        return makeAskCursorRow(title: "联网回答附图",
                                desc: "需要联网的问题，回答下方附 3 张相关图片（DuckDuckGo 图片搜索，不用 Key），点一张在浏览器里看原图。",
                                control: toggle)
    }

    @objc private func askImagesChanged(_ sender: VPToggle) {
        SettingsStore.shared.setAskImagesEnabled(sender.isOn)
    }

    /// 开关订阅一个布尔值：值和开关当前状态不一样时才拨过去（带动画），用户刚拨的那个开关不会被重播动画
    func bindToggle<P: Publisher>(_ toggle: VPToggle, to publisher: P) where P.Output == Bool, P.Failure == Never {
        toggle.subscribe(publisher.removeDuplicates()) { toggle, on in
            guard toggle.isOn != on else { return }
            toggle.setOn(on, animated: toggle.window != nil)
        }
    }

    private func makeAskThinkingToggleRow() -> NSView {
        let toggle = VPToggle(theme: theme, target: self, action: #selector(askThinkingChanged(_:)))
        toggle.setAccessibilityLabel("回答前先思考")
        bindToggle(toggle, to: SettingsStore.shared.$askThinkingEnabled)
        return makeAskCursorRow(title: "回答前先思考",
                                desc: "关着最快（约 1 秒出字）。打开后要看图推理、要计算的难题答得更准，每问多等 1 到 3 秒，难题更久。联网查询的那一问不受影响。",
                                control: toggle)
    }

    private func makeAskThinkingEffortRow() -> NSView {
        let items = AskThinkingEffort.allCases.map { VPDropdown.Item(value: $0.rawValue, title: $0.displayName) }
        let store = SettingsStore.shared
        let popup = VPDropdown(items: items, selectedValue: store.askThinkingEffort.rawValue,
                               trackBg: theme.card,
                               trackBorder: Self.dropdownBorder,
                               textColor: theme.text, chevronColor: theme.text3)
        popup.setAccessibilityLabel("思考强度")
        popup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        popup.onSelect = { value in
            guard let effort = AskThinkingEffort(rawValue: value) else { return }
            store.setAskThinkingEffort(effort)
        }
        popup.subscribe(store.$askThinkingEffort.removeDuplicates()) { popup, effort in
            if popup.selectedValue != effort.rawValue { popup.setSelectedValue(effort.rawValue) }
        }
        // 没开「回答前先思考」时这一行变淡、说明换成提示
        popup.subscribe(store.$askThinkingEnabled.removeDuplicates()) { popup, enabled in
            popup.alphaValue = enabled ? 1 : 0.45
        }
        return makeAskCursorRow(title: "思考强度", desc: "", control: popup) { descLabel in
            descLabel.subscribe(store.$askThinkingEnabled.removeDuplicates()) { view, enabled in
                view.stringValue = enabled
                    ? "越高想得越久、越细。最多等它想 8 / 15 / 30 秒（低 / 高 / 最高），到点还没答就直接给一个不思考的快答案。"
                    : "打开「回答前先思考」后生效。"
            }
        }
    }

    @objc private func askThinkingChanged(_ sender: VPToggle) {
        SettingsStore.shared.setAskThinkingEnabled(sender.isOn)   // 「思考强度」行跟着变淡或恢复
    }

    private func makeAskScreenshotRow() -> NSView {
        let toggle = VPToggle(theme: theme, target: self, action: #selector(askScreenshotChanged(_:)))
        toggle.setOn(AskSettings.isScreenshotEnabled, animated: false)
        toggle.setAccessibilityLabel("让 AI 看屏幕")
        return makeAskCursorRow(title: "让 AI 看屏幕",
                                desc: "提问时把指针所在的那块屏幕一起发给模型，需要屏幕录制权限。关掉就只发语音。",
                                control: toggle)
    }

    /// bindDesc：说明文字要跟着设置变时，在这里拿到说明标签去订阅 store
    func makeAskCursorRow(title: String, desc: String, control: NSView,
                          bindDesc: ((NSTextField) -> Void)? = nil) -> NSView {
        let titleLabel = label(title, size: 13, weight: .medium, color: theme.text)
        let descLabel = label(desc, size: 12, weight: .regular, color: theme.text3)
        descLabel.maximumNumberOfLines = 0
        bindDesc?(descLabel)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(descLabel)
        layoutTextColumn(textStack, beside: control)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        row.distribution = .fill
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(control)
        return row
    }

    /// 「回答方式」卡片展开后的说明 + 视觉模型手填框（看屏幕问会读这一项）
    private func makeAskHotkeyHelp(_ text: String) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12

        let help = label(text, size: 12.5, weight: .regular, color: theme.text2)
        help.maximumNumberOfLines = 0
        column.addArrangedSubview(help)
        help.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true

        let field = makeTextField(config.string(forKey: AskSettings.visionModelKey), mono: true)
        field.placeholderString = "留空 = 用默认的读图模型"
        field.identifier = NSUserInterfaceItemIdentifier("askVisionModel")
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        column.addArrangedSubview(makeAskCursorRow(title: "视觉模型（可选）",
                                                   desc: "官方换代时自己填新名字，不用等 Ask Free 发版。只对填写时选的那一家生效。",
                                                   control: field))
        column.arrangedSubviews.last?.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }
}
