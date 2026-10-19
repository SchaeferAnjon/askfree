import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension SettingsWindowController {
    @objc private func asrVersionChanged(_ sender: VPSegmentedControl) {
        let version = Self.asrVersion(forSegment: sender.selectedSegment)
        config.save(values: ["bigasr_version": version.rawValue])
        invalidate(.home)   // 首页健康卡的「语音识别」按当前版本判断是否已配置
    }

    @objc private func asrProviderChanged(_ sender: VPSegmentedControl) {
        let provider: CloudASRTranscriber.ASRProvider = (sender.selectedSegment == 1) ? .bailian : .volcano
        switch provider {
        case .volcano:
            // 回到火山：之前若就是火山某档则保留，否则用极速版
            let cur = CloudASRTranscriber().currentVersion()
            let v: CloudASRTranscriber.ASRVersion = (cur.provider == .volcano) ? cur : .turbo
            config.save(values: ["bigasr_version": v.rawValue])
        case .bailian:
            config.save(values: ["bigasr_version": "bailian"])
        }
        refreshASRFields(for: provider)
        // 识别服务商变了，问答卡片可能要在「填框」和「已复用」之间切换，刷新一下
        if let seg = askProviderControl {
            refreshAskKeyField(for: askProvider(forSegment: seg.selectedSegment))
        }
        invalidate(.home)   // 换了服务商，首页健康卡的「语音识别」要按新服务商的 Key 重新判断
    }

    /// 按服务商刷新识别卡片的动态区（Key + 版本/模型），与「问答模型」同一范式。
    private func refreshASRFields(for provider: CloudASRTranscriber.ASRProvider) {
        guard let container = asrKeyContainer else { return }
        container.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch provider {
        case .volcano:
            let keyField = makeSecureField(config.string(forKey: "bigasr_api_key"))
            keyField.delegate = self
            bigASRAPIKeyField = keyField
            bailianKeyField = nil   // 旧的百炼框已移除，别让 persistModelFields 再读它
            let keyRow = makeFieldRow(label: "API Key", control: keyField, placeholder: "请输入豆包 API Key")
            container.addArrangedSubview(keyRow)
            keyRow.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

            let versionLabel = label("识别版本", size: 12.5, weight: .medium, color: theme.text2)
            let versionSeg = VPSegmentedControl(
                labels: ["极速版", "标准版", "2.0"],
                trackBg: theme.cardAlt, trackBorder: theme.sep,
                selBg: theme.segSelBg, selBorder: theme.sep,
                selText: theme.text, normalText: theme.text2,
                target: self, action: #selector(asrVersionChanged(_:)))
            versionSeg.selectedSegment = Self.asrVersionSegmentIndex(for: CloudASRTranscriber().currentVersion())
            asrVersionControl = versionSeg
            let versionHint = label("极速版略快最稳，三种速度差不多。每个版本送 20 小时免费额度（半年有效），用完可切到下一个。", size: 11.5, weight: .regular, color: theme.text3)
            versionHint.maximumNumberOfLines = 0
            let versionRow = NSStackView()
            versionRow.orientation = .vertical
            versionRow.alignment = .leading
            versionRow.spacing = 5
            versionRow.addArrangedSubview(versionLabel)
            versionRow.addArrangedSubview(versionSeg)
            versionRow.addArrangedSubview(versionHint)
            container.addArrangedSubview(versionRow)
            versionRow.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            versionSeg.widthAnchor.constraint(equalTo: versionRow.widthAnchor).isActive = true

            asrGetKeyButton?.identifier = NSUserInterfaceItemIdentifier("https://console.volcengine.com/speech/app")

        case .bailian:
            let keyField = makeSecureField(config.string(forKey: "dashscope_api_key"))
            keyField.delegate = self
            bailianKeyField = keyField
            bigASRAPIKeyField = nil   // 旧的火山框已移除
            let keyRow = makeFieldRow(label: "DashScope API Key", control: keyField, placeholder: "请输入 DashScope API Key")
            container.addArrangedSubview(keyRow)
            keyRow.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

            let modelHint = label("qwen3-asr-flash 同步快、效果好，仅支持 5 分钟以内的音频。送 10 小时免费额度（90 天有效，用完会自动扣费，建议去控制台开「用完即停」）。和「问答模型」的通义千问共用一个 Key。", size: 11.5, weight: .regular, color: theme.text3)
            modelHint.maximumNumberOfLines = 0
            container.addArrangedSubview(modelHint)
            modelHint.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true

            asrGetKeyButton?.identifier = NSUserInterfaceItemIdentifier("https://bailian.console.aliyun.com/")
        }
    }

    private static func asrProviderSegmentIndex(for provider: CloudASRTranscriber.ASRProvider) -> Int {
        switch provider {
        case .volcano: return 0
        case .bailian: return 1
        }
    }

    private static func asrVersionSegmentIndex(for version: CloudASRTranscriber.ASRVersion) -> Int {
        switch version {
        case .turbo: return 0
        case .standard: return 1
        case .v2: return 2
        case .bailian: return 0
        }
    }

    private static func asrVersion(forSegment index: Int) -> CloudASRTranscriber.ASRVersion {
        switch index {
        case 1: return .standard
        case 2: return .v2
        default: return .turbo
        }
    }

    // MARK: - Page: Model

    func buildModel(into stack: NSStackView) {
        stack.addArrangedSubview(pageHeader(
            eyebrow: "ASK FREE / 模型", title: "模型设置",
            sub: "用你自己的 API。语音和问题直连你选的服务商，没有中间商。"))
        stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)

        // Prepare field instances fresh from config（secret 经 string 路由钥匙串）
        dashscopeAPIKeyField = makeSecureField(config.string(forKey: "dashscope_api_key"))
        arkAPIKeyField = makeSecureField(config.string(forKey: "ark_api_key"))
        deepseekAPIKeyField = makeSecureField(config.string(forKey: DeepSeekEndpoint.secretKey))
        // bigASRAPIKeyField / bailianKeyField 由识别卡片按服务商动态创建（refreshASRFields）
        // Persist edits as soon as a field loses focus ("改动即时保存")
        for field in [dashscopeAPIKeyField, arkAPIKeyField, deepseekAPIKeyField] {
            field?.delegate = self
        }

        // 还没填 Key 时，顶部一句明确的「最后一步」引导
        if !CloudASRTranscriber().isConfigured() || !AskAI().isConfigured() {
            let callout = makeFirstRunCallout()
            stack.addArrangedSubview(callout)
            stack.setCustomSpacing(14, after: callout)
        }

        // 推荐组合横幅：新用户不知道怎么搭时照抄即可
        let combo = makeRecommendedComboBanner()
        stack.addArrangedSubview(combo)
        stack.setCustomSpacing(20, after: combo)

        // ① 语音识别 + ② 问答模型：左右并列，体现"听懂 → 回答"的顺序，也填满横向空间。
        // 每张卡片外套一层"卡片 + 底部弹性占位"，矮卡被拉高时多余高度由占位吸收，内容不被撑开。
        let columns = NSStackView()
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 16
        let recCard = makeRecognitionCard()
        let askCard = makeAskModelCard()
        columns.addArrangedSubview(recCard)
        columns.addArrangedSubview(askCard)
        recCard.heightAnchor.constraint(equalTo: askCard.heightAnchor).isActive = true   // 两卡片等高、底部对齐
        stack.addArrangedSubview(columns)
    }

    private func makeFirstRunCallout() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 11
        card.layer?.setAppearanceBackground(theme.accent.withAlphaComponent(0.12))
        card.translatesAutoresizingMaskIntoConstraints = false

        let title = label("⚡ 最后一步", size: 13, weight: .semibold, color: theme.accent)
        let body = label("填入下面的 API Key，就能开始用了。", size: 12.5, weight: .regular, color: theme.text2)
        body.maximumNumberOfLines = 0

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(body)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 13, left: 16, bottom: 13, right: 16)
        row.addArrangedSubview(textStack)

        mount(row, in: card)
        return card
    }

    /// 「推荐搭配」横幅：墨黑实心小标签 + 加重文字，样式与教程横幅同款卡片。
    private func makeRecommendedComboBanner() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 11
        card.layer?.borderWidth = 1
        card.layer?.setAppearanceBorder(theme.accent.withAlphaComponent(0.35))
        card.layer?.setAppearanceBackground(theme.accentSoft)
        card.translatesAutoresizingMaskIntoConstraints = false

        // 墨黑实心小标签（同 primary 按钮配色）
        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 6
        chip.layer?.setAppearanceBackground(theme.accent)
        chip.translatesAutoresizingMaskIntoConstraints = false
        let chipLabel = NSTextField(labelWithString: "推荐搭配")
        chipLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        chipLabel.textColor = theme.onAccent
        chipLabel.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(chipLabel)
        NSLayoutConstraint.activate([
            chipLabel.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 9),
            chipLabel.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -9),
            chipLabel.topAnchor.constraint(equalTo: chip.topAnchor, constant: 4),
            chipLabel.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -4),
        ])

        let text = label("❶ 识别用「火山引擎（豆包）」 ＋ ❷ 问答用「DeepSeek」最快，需要最新信息时它会自己联网。",
                         size: 13, weight: .medium, color: theme.text)
        text.maximumNumberOfLines = 0
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 13, left: 16, bottom: 13, right: 16)
        row.addArrangedSubview(chip)
        row.addArrangedSubview(text)

        mount(row, in: card)
        return card
    }

    private func makeRecognitionCard() -> NSView {
        let card = makeCard()

        let badge = makeSectionBadge("1")
        let titleLbl = label("语音识别（必填）", size: 15, weight: .semibold, color: theme.text)
        let headRow = NSStackView()
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 10
        headRow.addArrangedSubview(badge)
        headRow.addArrangedSubview(titleLbl)

        let desc = label("把你说的问题转成文字。",
                          size: 12.5, weight: .regular, color: theme.text3)
        desc.maximumNumberOfLines = 0

        // 服务商分段：火山引擎 / 百炼(阿里)
        let providerLabel = label("服务商", size: 12.5, weight: .medium, color: theme.text2)
        let providerSeg = VPSegmentedControl(
            labels: ["火山引擎（豆包）", "百炼（阿里）"],
            trackBg: theme.cardAlt, trackBorder: theme.sep,
            selBg: theme.segSelBg, selBorder: theme.sep,
            selText: theme.text, normalText: theme.text2,
            target: self, action: #selector(asrProviderChanged(_:)))
        let asrProviderNow = CloudASRTranscriber().currentVersion().provider
        providerSeg.selectedSegment = Self.asrProviderSegmentIndex(for: asrProviderNow)
        asrProviderControl = providerSeg
        // 9-15 Ray：识别服务商只留火山，百炼选项隐藏；已经在用百炼的老用户仍能看到分段（好切回来）
        let showASRProviderSeg = asrProviderNow == .bailian

        // 动态区：随服务商切换（火山→Key+版本三选；百炼→DashScope Key+模型说明）
        let keyContainer = NSStackView()
        keyContainer.orientation = .vertical
        keyContainer.alignment = .leading
        keyContainer.spacing = 10
        asrKeyContainer = keyContainer

        let getKey = makeLinkButton(title: "↗ 点此获取密钥", urlString: "https://console.volcengine.com/speech/app")
        asrGetKeyButton = getKey

        // Test row
        let testBtn = VPButton(title: "▷ 测试连接", style: .secondary, size: .regular,
                               theme: theme, target: self, action: #selector(testRecognitionConnection))
        asrTestButton = testBtn

        let result = label("", size: 12.5, weight: .medium, color: theme.text3)
        asrTestResultLabel = result

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let testRow = NSStackView()
        testRow.orientation = .horizontal
        testRow.alignment = .centerY
        testRow.spacing = 10
        testRow.addArrangedSubview(testBtn)
        testRow.addArrangedSubview(result)
        testRow.addArrangedSubview(spacer)

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        inner.addArrangedSubview(headRow)
        inner.addArrangedSubview(desc)
        if showASRProviderSeg {
            inner.addArrangedSubview(providerLabel)
            inner.addArrangedSubview(providerSeg)
        }
        inner.addArrangedSubview(keyContainer)
        inner.addArrangedSubview(getKey)
        inner.addArrangedSubview(testRow)
        inner.setCustomSpacing(4, after: headRow)
        inner.setCustomSpacing(14, after: desc)
        if showASRProviderSeg {
            inner.setCustomSpacing(6, after: providerLabel)
            inner.setCustomSpacing(12, after: providerSeg)
        }
        inner.setCustomSpacing(12, after: getKey)

        let filler = NSView()
        filler.setContentHuggingPriority(.init(1), for: .vertical)
        inner.addArrangedSubview(filler)

        // 分段被隐藏时不在视图树里，不能给它挂宽度约束（否则抛异常，整页空白）
        for v in (showASRProviderSeg ? [desc, providerSeg, keyContainer, testRow] : [desc, keyContainer, testRow]) {
            v.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -36).isActive = true
        }

        mount(inner, in: card)
        refreshASRFields(for: CloudASRTranscriber().currentVersion().provider)
        return card
    }

    private func makeAskModelCard() -> NSView {
        let card = makeCard()

        let badge = makeSectionBadge("2")
        let titleLbl = label("问答模型（必填）", size: 15, weight: .semibold, color: theme.text)
        let headRow = NSStackView()
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 10
        headRow.addArrangedSubview(badge)
        headRow.addArrangedSubview(titleLbl)

        let desc = label("回答你的问题。看屏幕问时自动换成同一家支持读图的模型。",
                          size: 12.5, weight: .regular, color: theme.text3)
        desc.maximumNumberOfLines = 0

        // 服务商：千问 / DeepSeek；豆包默认隐藏，手改配置选了豆包时才显示
        // 自绘分段控件，软填充观感（详见 VPSegmentedControl）
        let current = config.string(forKey: "ask_provider") ?? "qwen"
        askSegProviders = current == "doubao"
            ? ["qwen", "deepseek", "doubao"]
            : ["qwen", "deepseek"]
        let seg = VPSegmentedControl(
            labels: askSegProviders.map { Self.askProviderLabel($0) },
            trackBg: theme.cardAlt,
            trackBorder: theme.sep,
            selBg: theme.segSelBg,
            selBorder: theme.sep,
            selText: theme.text,
            normalText: theme.text2,
            target: self,
            action: #selector(askProviderChanged(_:)))
        seg.selectedSegment = askSegmentIndex(for: current)
        askProviderControl = seg

        // Key field container (swapped by selection)
        let keyContainer = NSStackView()
        keyContainer.orientation = .vertical
        keyContainer.alignment = .leading
        keyContainer.spacing = 10
        askKeyContainer = keyContainer

        let getKey = makeLinkButton(title: "↗ 点此获取密钥", urlString: "https://console.volcengine.com/ark")
        askGetKeyButton = getKey

        // Test row
        let testBtn = VPButton(title: "▷ 测试连接", style: .secondary, size: .regular,
                               theme: theme, target: self, action: #selector(testAskConnection))
        askTestButton = testBtn

        let result = label("", size: 12.5, weight: .medium, color: theme.text3)
        askTestResultLabel = result

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let testRow = NSStackView()
        testRow.orientation = .horizontal
        testRow.alignment = .centerY
        testRow.spacing = 10
        testRow.addArrangedSubview(testBtn)
        testRow.addArrangedSubview(result)
        testRow.addArrangedSubview(spacer)

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 12
        inner.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        inner.addArrangedSubview(headRow)
        inner.addArrangedSubview(desc)
        inner.addArrangedSubview(seg)
        inner.addArrangedSubview(keyContainer)
        inner.addArrangedSubview(getKey)
        inner.addArrangedSubview(testRow)
        inner.setCustomSpacing(4, after: headRow)
        inner.setCustomSpacing(16, after: desc)
        inner.setCustomSpacing(14, after: seg)
        inner.setCustomSpacing(12, after: getKey)

        let filler = NSView()
        filler.setContentHuggingPriority(.init(1), for: .vertical)
        inner.addArrangedSubview(filler)

        desc.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -36).isActive = true
        keyContainer.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -36).isActive = true
        testRow.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -36).isActive = true

        mount(inner, in: card)

        // Populate the key field / hint for the current selection
        refreshAskKeyField(for: current)
        return card
    }

    /// 声波品牌标：圆角盒子 + 钟形声波（与 App 图标同款）。小盒(<40)用 3 根、大盒用 5 根；
    /// 深色盒子上波形用浅色(onAccent)。用 CALayer 画实心柱，原生清晰。
    func makeWaveformMark(box: CGFloat, corner: CGFloat, boxColor: NSColor, waveColor: NSColor) -> NSView {
        // viewBox 0..100 柱子：(x, 宽, y, 高, 圆角)
        let bars5: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (11, 10, 37.2, 25.6, 5), (28, 10, 26, 48, 5), (45, 10, 18, 64, 5),
            (62, 10, 29.2, 41.6, 5), (79, 10, 38.8, 22.4, 5)
        ]
        let bars3: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (10, 18, 30.2, 39.7, 9), (41, 18, 18, 64, 9), (72, 18, 33.4, 33.3, 9)
        ]
        let bars = box < 40 ? bars3 : bars5
        let mark = box * 0.68            // 波形占盒子 68%
        let off = (box - mark) / 2
        let k = mark / 100.0

        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = corner
        v.layer?.setAppearanceBackground(boxColor)
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: box),
            v.heightAnchor.constraint(equalToConstant: box),
        ])
        for (x, w, y, h, r) in bars {
            let bar = CALayer()
            bar.setAppearanceBackground(waveColor)
            // CALayer 默认 y 向上、viewBox y 向下 → 翻转：柱底 = box - off - (y+h)*k
            bar.frame = CGRect(x: off + x*k, y: box - off - (y+h)*k, width: w*k, height: h*k)
            bar.cornerRadius = r*k
            v.layer?.addSublayer(bar)
        }
        return v
    }

    private func makeSectionBadge(_ text: String) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 6
        v.layer?.setAppearanceBackground(theme.accentSoft)
        v.translatesAutoresizingMaskIntoConstraints = false
        let l = label(text, size: 12, weight: .bold, color: theme.accent)
        l.alignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(l)
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 22),
            v.heightAnchor.constraint(equalToConstant: 22),
            l.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    /// A vertical field: label on top, control below (matches the mockup).
    private func makeFieldRow(label labelText: String, control: NSView, placeholder: String) -> NSView {
        let l = label(labelText, size: 12.5, weight: .medium, color: theme.text2)
        if let field = control as? NSTextField {
            field.placeholderString = placeholder
        }
        control.translatesAutoresizingMaskIntoConstraints = false
        control.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.addArrangedSubview(l)
        stack.addArrangedSubview(control)
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    func makeLinkButton(title: String, urlString: String) -> NSButton {
        let btn = NSButton(title: title, target: self, action: #selector(openLink(_:)))
        btn.isBordered = false
        btn.bezelStyle = .inline
        btn.contentTintColor = theme.accent
        btn.font = .systemFont(ofSize: 12.5, weight: .semibold)
        let attr = NSMutableAttributedString(string: title)
        attr.addAttribute(.foregroundColor, value: theme.accent, range: NSRange(location: 0, length: attr.length))
        attr.addAttribute(.font, value: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                          range: NSRange(location: 0, length: attr.length))
        btn.attributedTitle = attr
        btn.identifier = NSUserInterfaceItemIdentifier(urlString)
        return btn
    }

    @objc private func openLink(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func askProviderLabel(_ provider: String) -> String {
        switch provider {
        case "doubao": return "火山引擎（豆包）"
        case "deepseek": return "DeepSeek"
        default: return "百炼（阿里）"
        }
    }

    private func askSegmentIndex(for provider: String) -> Int {
        askSegProviders.firstIndex(of: provider) ?? 0 // qwen（推荐，放最前）
    }

    private func askProvider(forSegment index: Int) -> String {
        askSegProviders.indices.contains(index) ? askSegProviders[index] : "qwen"
    }

    @objc private func askProviderChanged(_ sender: VPSegmentedControl) {
        let provider = askProvider(forSegment: sender.selectedSegment)
        config.save(value: provider, forKey: "ask_provider")
        refreshAskKeyField(for: provider)
        askTestResultLabel?.stringValue = ""
        invalidate(.home)
    }

    /// Rebuild the ask model key field to match the selected provider.
    private func refreshAskKeyField(for provider: String) {
        guard let container = askKeyContainer else { return }
        askGetKeyButton?.isHidden = false
        askTestButton?.isEnabled = true
        askTestButton?.title = "▷ 测试连接"
        container.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch provider {
        case "qwen":
            let rec = label("✓ 推荐。自带联网搜索，问最新的事也答得上。", size: 11.5, weight: .medium, color: theme.accent)
            rec.maximumNumberOfLines = 0
            container.addArrangedSubview(rec)
            rec.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            // 识别已用阿里(百炼) key 时，问答复用同一个 DashScope Key，不再出重复输入框
            let asrUsesBailian = CloudASRTranscriber().currentVersion().provider == .bailian
            let dashKey = config.string(forKey: "dashscope_api_key") ?? ""
            if asrUsesBailian && !dashKey.isEmpty {
                let reused = label("✓ 已复用识别填的 DashScope Key，无需重填（同一个阿里 key 通用）。", size: 12, weight: .medium, color: theme.accent)
                reused.maximumNumberOfLines = 0
                container.addArrangedSubview(reused)
                reused.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            } else {
                let row = makeFieldRow(label: "通义千问 API Key", control: dashscopeAPIKeyField!,
                                       placeholder: "请输入 DashScope API Key")
                container.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            }
            let modelRow = makeQwenAskModelDropdownRow()
            container.addArrangedSubview(modelRow)
            modelRow.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            askGetKeyButton?.identifier = NSUserInterfaceItemIdentifier("https://bailian.console.aliyun.com/")
        case "deepseek":
            let rec = label("⚡ 最快。本机实测带截图提问首字约 1.2 秒，比其他几家快一倍以上。", size: 11.5, weight: .medium, color: theme.accent)
            rec.maximumNumberOfLines = 0
            container.addArrangedSubview(rec)
            rec.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            let row = makeFieldRow(label: "DeepSeek API Key", control: deepseekAPIKeyField!,
                                   placeholder: "请输入 DeepSeek API Key")
            container.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            let modelRow = makeAskModelRow(
                configKey: DeepSeekEndpoint.modelConfigKey,
                presets: [DeepSeekEndpoint.defaultModel, "deepseek-v4-pro"],
                caption: "deepseek-flash 快且够用（默认，看屏幕问也用它）；deepseek-v4-pro 质量更好但更慢。")
            container.addArrangedSubview(modelRow)
            modelRow.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            let searchHint = label("需要最新信息的问题，DeepSeek 会自己判断、自动联网搜索；也可以用「搜一下……」开头直接联网。",
                                   size: 11.5, weight: .regular, color: theme.text3)
            searchHint.maximumNumberOfLines = 0
            container.addArrangedSubview(searchHint)
            searchHint.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            askGetKeyButton?.identifier = NSUserInterfaceItemIdentifier(DeepSeekEndpoint.consoleURL)
        default: // doubao
            let warn = label("⚠️ 火山引擎（豆包）不能联网，建议换「百炼（阿里）」或「DeepSeek」。", size: 11.5, weight: .medium, color: theme.text2)
            warn.maximumNumberOfLines = 0
            container.addArrangedSubview(warn)
            warn.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            let row = makeFieldRow(label: "豆包大模型 API Key", control: arkAPIKeyField!,
                                   placeholder: "请输入豆包大模型 API Key")
            container.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            let modelRow = makeAskModelRow(
                configKey: "doubao_ask_model",
                presets: ["doubao-seed-2-0-pro-260215", "doubao-seed-1-6-flash-250828"],
                caption: "两个模型按需选：doubao-seed-2-0-pro-260215 质量更好（默认）；doubao-seed-1-6-flash-250828 更快，但质量一般。")
            container.addArrangedSubview(modelRow)
            modelRow.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            askGetKeyButton?.identifier = NSUserInterfaceItemIdentifier("https://console.volcengine.com/ark")
        }
    }

    /// 问答模型默认值（留空时回落）。
    private func askModelDefault(forKey key: String) -> String {
        switch key {
        case "qwen_ask_model": return QwenModelRouter.autoValue
        case "doubao_ask_model": return "doubao-seed-2-0-pro-260215"
        case DeepSeekEndpoint.modelConfigKey: return DeepSeekEndpoint.defaultModel
        default: return ""
        }
    }

    /// 千问问答模型下拉选项：value → 展示名。顺序即下拉框顺序。
    private var qwenAskModelOptions: [(value: String, title: String)] {
        [(QwenModelRouter.autoValue, "自动 · 质量优先（推荐）"),
         (QwenModelRouter.autoSpeedValue, "自动 · 速度优先"),
         ("qwen3.8-max", "qwen3.8-max · 质量最好"),
         ("qwen3.7-max", "qwen3.7-max · 质量好"),
         ("qwen3.7-flash", "qwen3.7-flash · 快，付费最便宜"),
         ("qwen3.7-plus", "qwen3.7-plus · 均衡"),
         ("qwen3.6-flash", "qwen3.6-flash · 最快")]
    }

    /// 「模型」行（千问专用）：下拉框，首项「自动选择」。
    /// 额度冷却中的模型加「额度可能已用完」标记（标记来自请求层捕捉到的 403）。
    private func makeQwenAskModelDropdownRow() -> NSView {
        let def = askModelDefault(forKey: "qwen_ask_model")
        let saved = config.string(forKey: "qwen_ask_model") ?? ""
        let current = saved.isEmpty ? def : saved

        // 9-15 Ray：先别给用户太多选择，这三档隐藏；正选着的仍显示
        let hiddenModels: Set<String> = ["qwen3.8-max", "qwen3.7-max", "qwen3.6-flash"]
        var options = qwenAskModelOptions.filter { !hiddenModels.contains($0.value) || $0.value == current }
        if !current.isEmpty, !options.contains(where: { $0.value == current }) {
            options.append((current, "自定义：\(current)"))
        }

        let items = options.map { opt -> VPDropdown.Item in
            let exhausted = !QwenModelRouter.isAuto(opt.value) && QwenModelRouter.isExhausted(opt.value)
            return VPDropdown.Item(value: opt.value,
                                   title: exhausted ? opt.title + "（当前不可用）" : opt.title,
                                   warn: exhausted)
        }
        // 白底 + 细边框：与上方 API Key 输入框同款观感（同处「标签下的单值控件」位置）
        // 收起时选中项若已用完 → 红字（此时用户需要动手换）；菜单里其余已用完项只用弱化色，避免满屏红。
        let popup = VPDropdown(items: items, selectedValue: current,
                               trackBg: theme.card,
                               trackBorder: Self.dropdownBorder,
                               textColor: theme.text, chevronColor: theme.text3,
                               warnColor: theme.danger, mutedColor: theme.text3)
        popup.onSelect = { [weak self] value in
            guard let self else { return }
            self.config.save(value: value, forKey: "qwen_ask_model")
            self.askTestResultLabel?.stringValue = ""
            // 重建本页让状态行跟随新选择。必须延到下一轮 runloop：invalidate 会拆掉
            // 正在执行回调的那个下拉控件所在的视图树，同步拆会在它自己的方法栈上释放它。
            DispatchQueue.main.async { [weak self] in self?.invalidate(.model) }
        }

        let lbl = label("模型", size: 12.5, weight: .medium, color: theme.text2)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.addArrangedSubview(lbl)
        stack.addArrangedSubview(popup)

        // 状态行：自动模式告诉用户「现在在用哪个」；手动选中的模型额度用完则红字给出路。
        if let status = qwenAskStatusLine(for: current) {
            stack.addArrangedSubview(status)
            status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let cap = label("两种自动模式都会在某个模型免费额度用完时自动换下一个，无需手动切换：质量优先从 3.7-plus 往下用；速度优先从 3.7-flash 开始，出字明显更快。每个模型各送 100 万 Token 免费额度；建议在百炼控制台开启「免费额度用完即停」，额度用完 App 才能感知并自动切换。",
                        size: 11.5, weight: .regular, color: theme.text3)
        cap.maximumNumberOfLines = 0
        stack.addArrangedSubview(cap)
        cap.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// 模型下拉框下方的状态行；没什么可说时返回 nil。
    /// - 自动模式：显示当前实际会用的模型（用自动的人最关心这个）。
    /// - 手动模式且该模型额度已用完：红字 + 指出路（换「自动选择」）。
    private func qwenAskStatusLine(for current: String) -> NSTextField? {
        if QwenModelRouter.isAuto(current) {
            guard let inUse = QwenModelRouter.candidates(for: current).first else { return nil }
            let skipped = QwenModelRouter.qualityChain.filter { QwenModelRouter.isExhausted($0) }.count
            let suffix = skipped > 0 ? "（已自动跳过 \(skipped) 个当前不可用的模型）" : ""
            let l = label("当前在用：\(inUse)\(suffix)", size: 11.5, weight: .medium, color: theme.text2)
            l.maximumNumberOfLines = 0
            return l
        }
        guard QwenModelRouter.isExhausted(current) else { return nil }
        // 403 既可能是免费额度用完，也可能是这把 Key 没开通该模型——两种都得换模型，文案一并覆盖。
        let l = label("这个模型当前不可用（免费额度已用完，或这个 Key 未开通它），回答会失败。建议改用「自动 · 质量优先」，会自动换到可用的模型。",
                      size: 11.5, weight: .medium, color: theme.danger)
        l.maximumNumberOfLines = 0
        return l
    }


    /// 「模型」行：复用识别版本的横向分段样式，从预设模型里切换。
    private func makeAskModelRow(configKey: String, presets: [String], caption: String) -> NSView {
        let def = askModelDefault(forKey: configKey)
        let saved = config.string(forKey: configKey) ?? ""
        let current = saved.isEmpty ? def : saved
        let selected = presets.firstIndex(of: current) ?? (saved.isEmpty ? (presets.firstIndex(of: def) ?? 0) : -1)
        let customModelNotice = (!saved.isEmpty && selected == -1) ? "当前使用：\(current)。它不在上方预设里；点上方任一项才会切换。" : nil
        let modelSeg = VPSegmentedControl(
            labels: presets,
            trackBg: theme.cardAlt,
            trackBorder: theme.sep,
            selBg: theme.segSelBg,
            selBorder: theme.sep,
            selText: theme.text,
            normalText: theme.text2,
            target: self,
            action: #selector(askModelSegmentChanged(_:)))
        modelSeg.identifier = NSUserInterfaceItemIdentifier(configKey)
        modelSeg.selectedSegment = selected
        askModelPresets[configKey] = presets

        let lbl = label("模型", size: 12.5, weight: .medium, color: theme.text2)
        let cap = label(caption, size: 11.5, weight: .regular, color: theme.text3)
        cap.maximumNumberOfLines = 0
        let customNotice = customModelNotice.map {
            label($0, size: 11.5, weight: .medium, color: theme.text2)
        }
        customNotice?.maximumNumberOfLines = 0

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.addArrangedSubview(lbl)
        stack.addArrangedSubview(modelSeg)
        if let customNotice {
            stack.addArrangedSubview(customNotice)
            customNotice.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.addArrangedSubview(cap)
        modelSeg.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        cap.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    @objc private func askModelSegmentChanged(_ sender: VPSegmentedControl) {
        guard let key = sender.identifier?.rawValue,
              let presets = askModelPresets[key], !presets.isEmpty else { return }
        let index = max(0, min(sender.selectedSegment, presets.count - 1))
        let value = presets[index]
        config.save(value: value, forKey: key)
        askTestResultLabel?.stringValue = ""
    }

    /// Persist the model-tab field values to the local config file.
    /// Drops zhipu_api_key entirely; leaves any existing stored value for that key untouched.
    private func persistModelFields() {
        // 各家 API Key 直接走 saveSecret（写钥匙串 + 校验）；field 为 nil 时不动，避免清空已存的 key。
        // 空字符串 = 删除该 key；saveSecret 失败（钥匙串写不进）则提示重试，不静默成功。
        var secretOK = true
        if let f = bigASRAPIKeyField {
            secretOK = config.saveSecret(f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "bigasr_api_key") && secretOK
        }
        if let f = arkAPIKeyField {
            secretOK = config.saveSecret(f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ark_api_key") && secretOK
        }
        if let f = deepseekAPIKeyField {
            secretOK = config.saveSecret(f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DeepSeekEndpoint.secretKey) && secretOK
        }
        // DashScope Key 在识别(百炼)和问答(通义千问)共用同一 config key，取两处非空的
        let dsBailian = bailianKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dsAsk = dashscopeAPIKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if bailianKeyField != nil || dashscopeAPIKeyField != nil {
            secretOK = config.saveSecret(!dsBailian.isEmpty ? dsBailian : dsAsk, forKey: "dashscope_api_key") && secretOK
        }
        config.save(values: ["ask_provider": askProviderControl.map { askProvider(forSegment: $0.selectedSegment) } ?? "qwen"])
        if !secretOK {
            showAlert(title: "保存失败", message: "API Key 保存到钥匙串失败，请重试")
        }
        // 首页"语音识别 / 问答模型"健康卡依赖这些配置
        invalidate(.home)
    }

    @objc private func testRecognitionConnection() {
        // 先结束正在编辑的框：controlTextDidEndEditing 会把两处 DashScope Key 同步好，再保存
        window?.makeFirstResponder(nil)
        persistModelFields()
        asrTestButton?.isEnabled = false
        asrTestResultLabel?.textColor = theme.text3
        asrTestResultLabel?.stringValue = "测试中…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let silence = [Float](repeating: 0, count: 4800) // ~0.3s @16k
            CloudASRTranscriber().transcribe(samples: silence, sampleRate: 16000) { result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.asrTestButton?.isEnabled = true
                    switch result {
                    case .success:
                        self.setTestResult(self.asrTestResultLabel, ok: true, text: "✓ 连接成功")
                    case .failure(let error):
                        // 只有服务端明确判"静音/无语音"（火山 20000003 / 百炼空结果）才算通过——
                        // 说明鉴权、服务开通、网络全链路都通了，只是我们发的确实是静音。
                        // 其它一律如实报错。以前把"非鉴权错误"都当"凭证有效"，
                        // 结果账号没开通极速版（45000030 resource not granted）也显示 ✓，用户真录音才红框。
                        if case CloudASRTranscriber.TranscriptionError.noSpeech? = error as? CloudASRTranscriber.TranscriptionError {
                            self.setTestResult(self.asrTestResultLabel, ok: true, text: "✓ 连接成功")
                        } else {
                            self.setTestResult(self.asrTestResultLabel, ok: false,
                                               text: "✗ " + Self.shortError(error))
                        }
                    }
                }
            }
        }
    }

    @objc private func testAskConnection() {
        window?.makeFirstResponder(nil)   // 同 testRecognitionConnection：先结束编辑再保存
        persistModelFields()
        askTestButton?.isEnabled = false
        askTestResultLabel?.textColor = theme.text3
        askTestResultLabel?.stringValue = "测试中…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            AskAI().answer(question: "只回复 OK 两个字母") { result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.askTestButton?.isEnabled = true
                    switch result {
                    case .success:
                        self.setTestResult(self.askTestResultLabel, ok: true, text: "✓ 连接成功")
                    case .failure(let error):
                        self.setTestResult(self.askTestResultLabel, ok: false,
                                           text: "✗ " + Self.shortError(error))
                    }
                }
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field.identifier?.rawValue == "askVisionModel" {
            config.save(value: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                        forKey: AskSettings.visionModelKey)
            // 记下填的时候用的是哪一家，换了服务商就不把这个模型名发给别家（见 visionOverride）
            let provider = config.string(forKey: "ask_provider") ?? "qwen"
            config.save(value: ["qwen", "deepseek", "zhipu", "doubao"].contains(provider) ? provider : "",
                        forKey: AskSettings.visionModelProviderKey)
            return
        }
        // 识别(百炼)与问答(通义千问)的 DashScope Key 框联动，保持一致
        if field === bailianKeyField {
            dashscopeAPIKeyField?.stringValue = field.stringValue
            // 识别百炼填了 key → 问答通义千问那边切到「已复用」
            DispatchQueue.main.async { [weak self] in
                guard let self, let seg = self.askProviderControl else { return }
                self.refreshAskKeyField(for: askProvider(forSegment: seg.selectedSegment))
            }
        } else if field === dashscopeAPIKeyField {
            bailianKeyField?.stringValue = field.stringValue
        }
        let modelFields: [NSTextField?] = [bigASRAPIKeyField, bailianKeyField,
                                           dashscopeAPIKeyField, arkAPIKeyField, deepseekAPIKeyField]
        guard modelFields.contains(where: { $0 === field }) else { return }
        persistModelFields()
    }

    private func setTestResult(_ label: NSTextField?, ok: Bool, text: String) {
        label?.textColor = ok ? theme.ok : theme.danger
        label?.stringValue = text
    }

    private static func errorMessage(_ error: Error) -> String {
        if let local = error as? LocalizedError, let desc = local.errorDescription {
            return desc
        }
        return error.localizedDescription
    }

    private static func shortError(_ error: Error) -> String {
        let msg = errorMessage(error)
        if msg.count > 60 { return String(msg.prefix(60)) + "…" }
        return msg
    }
}
