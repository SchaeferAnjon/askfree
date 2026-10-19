import Cocoa
import Combine
import AudioToolbox
import AVFoundation
import ApplicationServices
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension SettingsWindowController {
    // MARK: - Page: Home

    func buildHome(into stack: NSStackView) {
        stack.addArrangedSubview(pageHeader(eyebrow: "ASK FREE / 首页", title: "首页",
                                             sub: "按一个键说出问题，AI 看着你的屏幕回答。"))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        let hero = makeHomeHero()
        stack.addArrangedSubview(hero)
        stack.setCustomSpacing(24, after: hero)

        let healthTitle = sectionTitle("配置健康")
        stack.addArrangedSubview(healthTitle)
        stack.setCustomSpacing(8, after: healthTitle)
        stack.addArrangedSubview(makeHealthCard())
    }

    private func makeHomeHero() -> NSView {
        let card = makeCard()

        // 主角是「看屏幕问」：和原来的大标题同一个排法，下面一行是「只提问」
        let titlePrefix = label("长按或单击", size: 24, weight: .semibold, color: theme.text)
        let titleSuffix = label("看着屏幕问 AI", size: 24, weight: .semibold, color: theme.text)
        let hotkeyPicker = makeHotkeyPickerButton(for: .screen)

        titlePrefix.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleSuffix.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.addArrangedSubview(titlePrefix)
        titleRow.addArrangedSubview(hotkeyPicker)
        titleRow.addArrangedSubview(titleSuffix)
        titleRow.setContentCompressionResistancePriority(.required, for: .horizontal)

        let note = "按下那一刻鼠标指在哪，AI 就重点看哪。长按时松开结束；单击时再次单击结束。"
        let desc = label(note, size: 13, weight: .regular, color: theme.text3)
        desc.maximumNumberOfLines = 0
        desc.lineBreakMode = .byWordWrapping
        desc.subscribe(SettingsStore.shared.$hotkeys.map { $0.conflict(of: .screen) }.removeDuplicates()) { view, conflict in
            view.stringValue = conflict.map { "⚠️ \($0)，现在不会响应" } ?? note
        }

        let leftStack = NSStackView()
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 6
        leftStack.addArrangedSubview(titleRow)
        leftStack.addArrangedSubview(desc)
        leftStack.setCustomSpacing(14, after: desc)
        leftStack.addArrangedSubview(makeAskHotkeyHomeRow(.plain, suffix: "只提问，不看屏幕",
                                                          note: "不截屏，更快一点。"))

        // 问 AI 的几个用法：不列出来没人知道有（追问、换话题、联网、取消）
        let askHints = NSStackView()
        askHints.orientation = .horizontal
        askHints.alignment = .centerY
        askHints.spacing = 28
        askHints.addArrangedSubview(makeGestureHint(key: "回答还在时再按快捷键", label: "追问"))
        askHints.addArrangedSubview(makeGestureHint(key: "开头说「新话题」", label: "换话题"))
        askHints.addArrangedSubview(makeGestureHint(key: "开头说「搜一下」", label: "联网查"))
        askHints.addArrangedSubview(makeGestureHint(key: "说话时按 Esc", label: "取消"))

        let main = NSStackView()
        main.orientation = .vertical
        main.alignment = .leading
        main.distribution = .fill
        main.spacing = 14
        main.edgeInsets = NSEdgeInsets(top: 18, left: 28, bottom: 16, right: 28)
        main.addArrangedSubview(leftStack)
        let rule = makeHairline(insetH: 0)
        main.addArrangedSubview(rule)
        main.addArrangedSubview(askHints)
        mount(main, in: card)
        rule.widthAnchor.constraint(equalTo: main.widthAnchor, constant: -56).isActive = true
        return card
    }

    /// 首页快捷用法：键帽样式的动作 + 结果
    private func makeGestureHint(key: String, label text: String) -> NSView {
        let cap = NSView()
        cap.translatesAutoresizingMaskIntoConstraints = false
        cap.wantsLayer = true
        cap.layer?.cornerRadius = 6
        cap.layer?.borderWidth = 1
        cap.layer?.setAppearanceBorder(theme.sep)
        cap.layer?.setAppearanceBackground(theme.cardAlt)
        let capLabel = label(key, size: 12, weight: .medium, color: theme.text)
        capLabel.translatesAutoresizingMaskIntoConstraints = false
        cap.addSubview(capLabel)
        NSLayoutConstraint.activate([
            capLabel.leadingAnchor.constraint(equalTo: cap.leadingAnchor, constant: 9),
            capLabel.trailingAnchor.constraint(equalTo: cap.trailingAnchor, constant: -9),
            capLabel.topAnchor.constraint(equalTo: cap.topAnchor, constant: 4),
            capLabel.bottomAnchor.constraint(equalTo: cap.bottomAnchor, constant: -4),
        ])
        let arrow = label("→", size: 12, weight: .regular, color: theme.text3)
        let result = label(text, size: 13, weight: .medium, color: theme.text2)
        let row = NSStackView(views: [cap, arrow, result])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    /// 首页上的一行：「长按或单击 [快捷键 ▾] 只提问，不看屏幕」。点中间的按钮改键
    private func makeAskHotkeyHomeRow(_ hotkey: AskHotkey, suffix: String, note: String) -> NSView {
        let prefixLabel = label("长按或单击", size: 15, weight: .medium, color: theme.text)
        let suffixLabel = label(suffix, size: 15, weight: .medium, color: theme.text)
        let picker = makeHotkeyPickerButton(for: hotkey, compact: true)
        picker.font = .systemFont(ofSize: 14, weight: .semibold)
        let noteLabel = label(note, size: 12, weight: .regular, color: theme.text3)
        noteLabel.subscribe(SettingsStore.shared.$hotkeys.map { $0.conflict(of: hotkey) }.removeDuplicates()) { view, conflict in
            view.stringValue = conflict.map { "⚠️ \($0)，现在不会响应" } ?? note
        }
        for view in [prefixLabel, suffixLabel] { view.setContentCompressionResistancePriority(.required, for: .horizontal) }

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.addArrangedSubview(prefixLabel)
        row.addArrangedSubview(picker)
        row.addArrangedSubview(suffixLabel)
        row.addArrangedSubview(noteLabel)
        row.setCustomSpacing(14, after: suffixLabel)
        return row
    }

    private func makeHealthCard() -> NSView {
        let card = makeCard()
        let micStatus = micStatusInfo()
        let accessOK = AXIsProcessTrusted()
        let screenOK = ScreenSnapshotCapturer.hasPermission
        let asrOK = CloudASRTranscriber().isConfigured()
        let askOK = AskAI().isConfigured()

        var rows: [(String, String, Bool, String, Selector?)] = [
            ("麦克风", micStatus.sub, micStatus.ok, micStatus.tail,
             micStatus.ok ? nil : #selector(healthMicRowTapped)),
            ("辅助功能", accessOK ? "快捷键可用" : "未开启快捷键不响应，点击去系统设置开启",
             accessOK, accessOK ? "已允许" : "未允许",
             accessOK ? nil : #selector(healthAccessibilityRowTapped)),
            asrOK
                ? ("语音识别", "可以听懂你的问题", true, "已配置", nil)
                : ("语音识别", "请在「模型」页填写语音识别 Key", false, "未配置", #selector(healthModelRowTapped)),
            askOK
                ? ("问答模型", "可以回答问题", true, "已配置", nil)
                : ("问答模型", "请在「模型」页填写问答模型 Key", false, "未配置", #selector(healthModelRowTapped)),
        ]
        // 关了「提问时附带屏幕」就用不到这项权限，不拿它把首页标红
        if AskSettings.isScreenshotEnabled {
            rows.insert(("屏幕录制", screenOK ? "问 AI 能看到指针所在的屏幕" : "未开启问 AI 只听语音，点击开启（开完重启 Ask Free）",
                         screenOK, screenOK ? "已允许" : "未允许",
                         screenOK ? nil : #selector(healthScreenRowTapped)), at: 2)
        }

        let allOK = rows.allSatisfy { $0.2 }
        let failCount = rows.filter { !$0.2 }.count
        // 全绿默认折叠（这块没信息量），有问题默认展开；用户可手动点开/收起。
        let expanded = healthExpandedOverride ?? !allOK
        lastHealthExpanded = expanded

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        stack.addArrangedSubview(makeHealthSummaryRow(allOK: allOK, failCount: failCount, expanded: expanded))
        if expanded {
            stack.addArrangedSubview(makeHairline(insetH: 18))
            for (i, r) in rows.enumerated() {
                stack.addArrangedSubview(makeHealthRow(label: r.0, sub: r.1, ok: r.2, tail: r.3, action: r.4))
                if i < rows.count - 1 {
                    stack.addArrangedSubview(makeHairline(insetH: 18))
                }
            }
        }
        for v in stack.arrangedSubviews {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        mount(stack, in: card)
        return card
    }

    /// 摘要行：全绿时绿点「配置就绪 · 一切正常」，有问题时红字「N 项需要处理」；点击切换展开。
    private func makeHealthSummaryRow(allOK: Bool, failCount: Int, expanded: Bool) -> NSView {
        let dot = circle(color: allOK ? theme.ok : theme.danger, size: 8)
        let l = label(allOK ? "配置就绪 · 一切正常" : "\(failCount) 项需要处理",
                      size: 13, weight: .medium, color: allOK ? theme.text : theme.danger)
        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                accessibilityDescription: expanded ? "收起" : "展开")
        chevron.contentTintColor = theme.text3
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let h = NSStackView()
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 12
        h.edgeInsets = NSEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        h.addArrangedSubview(dot)
        h.addArrangedSubview(l)
        h.addArrangedSubview(spacer)
        h.addArrangedSubview(chevron)
        h.setCustomSpacing(12, after: dot)
        h.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleHealthExpanded)))
        return h
    }

    @objc private func toggleHealthExpanded() {
        // 以卡片上次实际画出来的状态为准取反，不另算一遍全绿（两套判断对不上时第一次点击没反应）
        healthExpandedOverride = !lastHealthExpanded
        invalidate(.home)
    }

    /// 麦克风：没问过 → 直接唤起系统授权弹窗；被拒过 → 系统不允许再弹，只能带用户去系统设置开。
    @objc private func healthMicRowTapped() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.invalidate(.home, .settings) }
            }
        case .denied, .restricted:
            settingsDelegate?.openMicrophoneSettings()
        default:
            break
        }
    }

    @objc private func healthModelRowTapped() {
        selectPage(.model)
    }

    @objc private func healthScreenRowTapped() {
        ScreenSnapshotCapturer.requestOrOpenSettings()
    }

    @objc private func healthAccessibilityRowTapped() {
        guard !AXIsProcessTrusted() else { return }
        settingsDelegate?.openAccessibilitySettings()
    }

    private func makeHealthRow(label labelText: String, sub: String, ok: Bool, tail: String,
                               action: Selector? = nil) -> NSView {
        let dot = circle(color: ok ? theme.ok : theme.danger, size: 8)
        let l = label(labelText, size: 13, weight: .medium, color: theme.text)
        let s = label(sub, size: 12, weight: .regular, color: theme.text2)
        let t = label(tail, size: 12, weight: .medium, color: ok ? theme.ok : theme.danger)

        l.setContentHuggingPriority(.required, for: .horizontal)
        s.setContentHuggingPriority(.defaultLow, for: .horizontal)
        s.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        t.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let h = NSStackView()
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 12
        h.edgeInsets = NSEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        h.addArrangedSubview(dot)
        h.addArrangedSubview(l)
        h.addArrangedSubview(s)
        h.addArrangedSubview(spacer)
        h.addArrangedSubview(t)
        h.setCustomSpacing(12, after: dot)
        h.setCustomSpacing(16, after: l)
        h.setCustomSpacing(12, after: s)
        h.setCustomSpacing(0, after: spacer)
        if let action = action {
            h.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: action))
        }
        return h
    }

    func makeHairline(insetH: CGFloat) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let line = NSView()
        line.wantsLayer = true
        line.layer?.setAppearanceBackground(theme.sep)
        line.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: insetH),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -insetH),
            line.topAnchor.constraint(equalTo: wrap.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            wrap.heightAnchor.constraint(equalToConstant: 1),
        ])
        return wrap
    }

    func micStatusInfo() -> (ok: Bool, sub: String, tail: String) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return (true, "可录音", "已允许")
        case .denied: return (false, "被拒绝过，点击去系统设置开启", "已拒绝")
        case .restricted: return (false, "受系统限制", "受限")
        case .notDetermined: return (false, "点击申请麦克风权限", "待授权")
        @unknown default: return (false, "未知状态", "未知")
        }
    }
}
