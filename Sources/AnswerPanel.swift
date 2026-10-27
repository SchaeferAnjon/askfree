import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif
import SwiftUI

/// 问 AI 的回答面板（design/panels 方向 A「右上对话卡」）：贴右上角的一张卡，从屏幕右缘滑入，
/// 内容高度变化时顶右角不动、Esc 关闭。卡顶一条固定高度的状态条，追问在卡里连成编号的线，
/// 卡片还开着时换话题，旧话题折成一行；报错是带按钮的一块。内容用 SwiftUI 排版。
final class AnswerPanel {
    static var log: ((String) -> Void)?
    private var panel: KeyablePanel?
    private var hosting: FirstMouseHostingView?
    /// 离屏的一份对话内容，只用来量高度（ScrollView 里 SwiftUI 自己报不准）
    private var measure: NSHostingView<TurnsView>?
    let model = AnswerModel()
    private var escMonitor: Any?
    private var mouseUpMonitor: Any?
    private var outsideClickMonitor: Any?
    private var appearanceObserver: NSObjectProtocol?
    private var hotkeyObserver: NSObjectProtocol?
    // 「点外面缩成小框」：小框静止 4s 后 1s 淡出；鼠标停留 150ms 回满；再离开重新倒计时
    static let collapsedWidth: CGFloat = 320
    private var dismissTimer: Timer?
    private var hoverTimer: Timer?
    private var hoverSince: Date?
    /// 缩过一次之后才启用「鼠标离开面板就再缩」；新话题 / 固定 / 收起时复位
    private var hoverArmed = false
    /// 点外面时回答还没出完：等出完再缩
    private var collapseWhenDone = false
    /// 每起一次窗口尺寸动画加一，动画结束时用来认「我是不是最后一次」
    private var layoutGeneration = 0
    /// 尺寸动画预计结束的时刻；在这之前的核对交给动画结束回调去做
    private var frameAnimationEnds = Date.distantPast
    /// 续聊录音进行中（面板侧兜底记录，防止 SwiftUI 手势丢了 onEnded 之后录音停不下来）
    private var followUpActive = false
    static let width: CGFloat = 400
    static let cornerRadius: CGFloat = 12
    private static let margin: CGFloat = 12
    /// 正文左右内边距：左右等距，正文居中不偏
    static let contentInset: CGFloat = 16
    /// 回答区上下内边距（上 14、下 6）：离屏测高只量内容，摆窗口时加回来
    static let bodyPadding: (top: CGFloat, bottom: CGFloat) = (14, 6)
    /// 对话正文宽度：面板宽 − 两侧内边距。滚动条强制成细的 overlay 样式，
    /// 浮在右侧那 18pt 留白上，不占布局、也压不到字，所以不再额外让出通道
    static var contentWidth: CGFloat { width - contentInset * 2 }

    /// 面板空白处长按到时：开始续聊录音（返回 false = 没开始）
    var onFollowUpStart: (() -> Bool)?
    /// 续聊松手（cancelled = 拖开取消）
    var onFollowUpEnd: ((_ cancelled: Bool) -> Void)?
    /// 底栏「打字」
    var onType: (() -> Void)?
    /// 报错卡「重试」：把这一句再问一遍（面板已经撤掉了没答成的那一轮）
    var onRetry: ((_ question: String) -> Void)?
    /// 报错卡「去填 Key」「去换一家」
    var onOpenModels: (() -> Void)?
    /// 「这次没看屏幕」那条的「去授权」
    var onGrantScreen: (() -> Void)?

    /// 正在滑出的面板不算在屏上（马上就收起了）
    var isVisible: Bool { (panel?.isVisible ?? false) && !isHiding }
    /// 面板在屏幕上的位置（打字问的输入框贴在它下面）
    var frame: NSRect? { panel?.frame }
    /// 滑出动画进行中；动画回调只在这一轮没被新的 present 打断时才 orderOut
    private var isHiding = false
    private var hideGeneration = 0
    /// 当前话题 id（写历史用；新话题换新 id）
    private(set) var threadID = UUID().uuidString
    /// 最近一次问答动静的时刻。钉住的浮窗可以放很久，隔太久的旧对话不该被带进新问题
    private var lastActivityAt = Date.distantPast
    /// 此刻再提问是不是该接着当前话题：浮窗还在屏幕上、至少答完过一轮、而且不是很久以前的
    var canContinueThread: Bool {
        isVisible && !history.isEmpty && Date().timeIntervalSince(lastActivityAt) < AskThreading.staleAfter
    }
    /// 日志用：为什么这一问接着聊 / 另起话题
    var stateSummary: String {
        "panel(visible=\(isVisible) hiding=\(isHiding) collapsed=\(model.collapsed) answered=\(history.count) idle=\(Int(Date().timeIntervalSince(lastActivityAt)))s)"
    }
    /// 本话题已完成的问答对，续聊时作为上下文
    var history: [(question: String, answer: String)] {
        model.turns.filter { $0.state == .answered }.map { ($0.question, $0.answer) }
    }

    /// 新话题：清空重来。卡片还在屏上、上个话题答过时，旧话题折成卡顶一行
    func startThread(question: String) {
        let answered = model.turns.filter { $0.state == .answered }
        model.previousTopic = isVisible && !answered.isEmpty ? PreviousTopic(question: answered[0].question, turns: answered) : nil
        model.showPrevious = false
        model.expandedTurns = []
        model.turns = [AnswerTurn(question: question)]
        model.headerIndex = 0
        threadID = UUID().uuidString
        resetCollapse()
        model.contentHeight = Self.thinkingRowHeight
        trustMeasure = false
        present()
        trustMeasure = true
    }

    /// 续聊：追加一轮
    func appendQuestion(_ question: String) {
        lastActivityAt = Date()
        model.turns.append(AnswerTurn(question: question))
        resetCollapse()
        present()
    }

    func updatePartial(_ text: String) {
        guard let last = model.turns.indices.last else { return }
        model.turns[last].answer = text
        model.turns[last].state = .streaming
        scheduleStreamingRelayout()
    }

    /// 流式出字期间窗口的长法。每来一段就量一次、跳一次，字出得快（DeepSeek 一秒十几段）时窗口一抖一抖的。
    /// 改成：最多每 0.15 秒量一次；只长不缩（量到的高度偶尔会比上一次小几个点，那是 measure 没跟上，不是内容变短）；
    /// 每次长到 48 点的整数倍，多预留一点，接下来几段字直接填进已有的空间，不用再动窗口。
    /// 回答结束后 finish 会按精确高度定一次。
    private static let streamingStep: CGFloat = 48
    private static let streamingInterval: TimeInterval = 0.15
    private var streamingRelayoutScheduled = false

    private func scheduleStreamingRelayout() {
        guard !streamingRelayoutScheduled else { return }
        streamingRelayoutScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.streamingInterval) { [weak self] in
            guard let self else { return }
            self.streamingRelayoutScheduled = false
            guard self.model.turns.last?.state == .streaming else { return }
            self.relayout(streaming: true)
        }
    }

    func finish(answer: String) {
        guard let last = model.turns.indices.last else { return }
        lastActivityAt = Date()
        model.turns[last].answer = answer
        model.turns[last].state = .answered
        relayout()
        settleAfterFinish()
        if collapseWhenDone { collapseWhenDone = false; collapse() }
    }

    /// 这次没看屏幕：回答上面一条橙底提示；没给屏幕录制权限时带「去授权」
    func setScreenNote(_ text: String, needsPermission: Bool) {
        guard let last = model.turns.indices.last else { return }
        model.turns[last].screenNote = text
        model.turns[last].screenNeedsPermission = needsPermission
        relayoutAfterStateChange()
    }

    /// 这一问转去联网查了：状态条答完写「联网」
    func markSearched() {
        guard let last = model.turns.indices.last else { return }
        model.turns[last].searched = true
    }

    /// 给当前这一轮加一行小灰字（正在联网查、网络较慢、在想）。传 nil 清掉。
    func setNote(_ text: String?) {
        guard let last = model.turns.indices.last else { return }
        guard model.turns[last].note != text else { return }
        model.turns[last].note = text
        relayout()
    }

    /// 这一轮发给模型的两张截图（指针附近已用细红框框出）：挂在回答上方，让用户知道它看到的是什么
    func setScreenshot(overviewJPEG: Data, closeUpJPEG: Data) {
        guard let last = model.turns.indices.last,
              let overview = NSImage(data: overviewJPEG), let closeUp = NSImage(data: closeUpJPEG) else { return }
        model.turns[last].screenshot = AskScreenshot(closeUp: closeUp, overview: overview,
                                                     closeUpJPEG: closeUpJPEG, overviewJPEG: overviewJPEG)
        relayoutAfterStateChange()
    }

    /// 联网找到的图到了：挂在当前这一轮下面
    func setImages(_ images: [AskImage]) {
        guard let last = model.turns.indices.last, !images.isEmpty else { return }
        model.turns[last].images = images
        relayoutAfterStateChange()
    }

    func fail(_ failure: AskFailure) {
        guard let last = model.turns.indices.last else { return }
        model.turns[last].failure = failure
        model.turns[last].state = .failed
        // 报错卡比「在想」高得多：先让离屏测高按新内容重算，再核对两次，否则窗口停在旧高度、头尾被挤出去
        relayoutAfterStateChange()
        settleAfterFinish()
        if collapseWhenDone { collapseWhenDone = false; collapse() }
    }

    /// 录音状态 → 面板蓝光 / 待取消红光；底栏同步换成音浪
    func setRecording(_ recording: Bool, cancelArmed: Bool = false) {
        model.recording = recording
        model.cancelArmed = cancelArmed
        if !recording { followUpActive = false }   // 快捷键停止的续聊不经 endFollowUp，别把状态留着
        if recording { model.footer = .listening; model.wave.start() } else { model.wave.stop(); if model.footer == .listening { model.footer = .idle } }
    }

    /// 底栏状态：识别中 / 没听到 / 已取消 / 恢复提示（后两者 1.6s 后自动恢复）
    func setListening(_ state: AnswerModel.FooterState) {
        model.footer = state
        if state == .noSpeech || state == .cancelled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.model.footer == state else { return }
                self.model.footer = .idle
            }
        }
    }

    /// 录音音量（0…1），底栏音浪用
    func updateAudioLevel(_ level: Float) {
        model.wave.level = CGFloat(min(max(level, 0), 1))
    }

    func hide() {
        guard let panel, panel.isVisible, !isHiding else { return }
        isHiding = true
        hideGeneration += 1
        let generation = hideGeneration
        removeEscMonitor()
        removeMouseUpMonitor()
        removeOutsideClickMonitor()
        resetCollapse()
        if followUpActive { endFollowUp(cancelled: true) }
        model.recording = false
        let screen = panel.screen ?? Self.screenUnderMouse()
        var out = panel.frame
        // 「减少动态效果」打开时原地淡出，不往右滑
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion { out.origin.x = screen.frame.maxX + 12 }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.15 : 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(out, display: true)
            panel.animator().alphaValue = reduceMotion ? 0 : 0.2
        }, completionHandler: { [weak self, weak panel] in
            // 滑出途中又弹出了新回答：这次收起作废，别把新面板藏掉
            guard let self, self.hideGeneration == generation, self.isHiding else { return }
            self.isHiding = false
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        })
    }

    // MARK: - 私有

    private func present() {
        if panel == nil { createPanel() }
        applyAppearance()   // 兜底：万一漏了切换通知，每次弹出时再核对一次
        refreshHotkeyHint()
        guard let panel, let hosting else { return }
        refreshViewsForNewContent()
        let screen = Self.screenUnderMouse()
        model.maxContentHeight = max(160, screen.visibleFrame.height * 0.7 - 140)   // 140 ≈ 头（两行问题）+ 尾 + 内边距
        // SwiftUI 的内容尺寸要到下一个运行循环才按新内容更新，先同步布局一次再量，
        // 否则会拿到上一条回答的高度，内容悬在中间、上下露出空的磨砂底。
        hosting.layoutSubtreeIfNeeded()
        tuneScroller()   // 弹出这一帧就是细 overlay 滚动条，不会先闪一下系统的粗条
        let size = fittingSize(of: hosting)
        let vf = screen.visibleFrame
        let final = NSRect(x: vf.maxX - size.width - Self.margin, y: vf.maxY - size.height - Self.margin,
                           width: size.width, height: size.height)
        if isHiding {
            // 正在滑出：作废那次收起，下面按全新弹出走（重新滑入、重装 Esc / 点外面的监听）
            isHiding = false
            hideGeneration += 1
        } else if panel.isVisible {
            // 面板已在屏上（固定着、或上一题还没收）：内容整体换新，窗口直接定到新高度。
            // 若走动画，旧窗口比新内容高的那 0.2 秒里内容会贴底、顶上露一块空底。
            panel.setFrame(final, display: true)
            if let content = panel.contentView { hosting.frame = content.bounds }
            panel.invalidateShadow()
            relayoutAfterStateChange(animated: false)
            return
        }
        // 「减少动态效果」打开时原地淡入，不从屏幕右缘滑进来
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let start = reduceMotion ? final : NSRect(x: screen.frame.maxX + 12, y: final.origin.y, width: size.width, height: size.height)
        panel.alphaValue = reduceMotion ? 0 : 1
        // 先定窗口尺寸，再把内容视图铺满：内容视图带自动缩放，若先设它再改窗口，会随窗口尺寸差被二次缩放，
        // 上次面板高、这次内容短时内容就被挤到底部、顶上露一块空底
        panel.setFrame(start, display: false)
        if let content = panel.contentView { hosting.frame = content.bounds }
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.15 : 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.19, 1.0, 0.22, 1.0)
            panel.animator().setFrame(final, display: true)
            if reduceMotion { panel.animator().alphaValue = 1 }
        }, completionHandler: { [weak self] in
            panel.invalidateShadow()
            self?.relayoutAfterStateChange()
        })
        installEscMonitor()
        installMouseUpMonitor()
        installOutsideClickMonitor()
    }

    private func makeAnswerView() -> AnswerView {
        AnswerView(model: model,
                   onCopy: { [weak self] in self?.copyAnswer() },
                   onClose: { [weak self] in self?.hide() },
                   onTogglePin: { [weak self] in self?.togglePin() },
                   onHoldStart: { [weak self] in self?.beginFollowUp() ?? false },
                   onHoldEnd: { [weak self] cancelled in self?.endFollowUp(cancelled: cancelled) },
                   onType: { [weak self] in self?.onType?() },
                   onAction: { [weak self] action in self?.perform(action) },
                   onGrantScreen: { [weak self] in self?.onGrantScreen?() })
    }

    private func perform(_ action: AskFailure.Action) {
        switch action {
        case .openModels:
            onOpenModels?()
        case .retry:
            guard let last = model.turns.last, last.state == .failed else { return }
            model.turns.removeLast()
            onRetry?(last.question)
        }
    }

    /// 内容整体换了（新问题、收起 / 展开）之后、量尺寸之前调。
    /// model 一改，SwiftUI 要到下一轮界面刷新才重算视图，立刻去量拿到的还是换之前的高度：
    /// 新问题开始时浮窗先按上一条回答的高度摆出来（2026-09-21 实测 410，应为 145），
    /// 等主线程忙完发请求那半秒才缩回去，上下各露一条空底。重新给一次 rootView 会让它当场按现在的 model 重算。
    private func refreshViewsForNewContent() {
        measure?.rootView = TurnsView(model: model, width: Self.contentWidth)
        hosting?.rootView = makeAnswerView()
        measure?.layoutSubtreeIfNeeded()
        hosting?.layoutSubtreeIfNeeded()
    }

    private func createPanel() {
        measure = NSHostingView(rootView: TurnsView(model: model, width: Self.contentWidth))
        let hosting = FirstMouseHostingView(rootView: makeAnswerView())
        let size = fittingSize(of: hosting)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        effect.addSubview(hosting)

        let p = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = effect
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        // 与底部胶囊同层（胶囊窗口 isFloatingPanel 实际是 floating 层）：续聊时胶囊后显示、压在面板上方
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isMovable = false
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.onEscape = { [weak self] in self?.hide() }
        panel = p
        self.hosting = hosting
        // 深浅跟「设置 → 外观」走（与主窗口一致）；内容用 Theme 的动态色
        MainWindowAppearance.observeSystemChanges()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: MainWindowAppearance.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyAppearance() }
        applyAppearance()
        // 底栏键帽跟着设置里的快捷键走
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .askFreeHotkeyDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshHotkeyHint() }
    }

    /// 底栏键帽按实际生效的快捷键写：说话键（优先看屏幕问那套）和双击打字键，没设或被撞掉的不写。
    /// 状态条「已答 · DeepSeek」的那一家也在弹出时取一次
    private func refreshHotkeyHint() {
        let voice = [AskHotkey.screen, AskHotkey.plain].first(where: \.isActive)?.current.map(Self.keyCap)
        let typing = TypeAskHotkey.isActive() ? TypeAskHotkey.current().map(\.symbol) : nil
        if model.voiceKey != voice { model.voiceKey = voice }
        if model.typeKey != typing { model.typeKey = typing }
        let provider = Self.providerName(AskFreeConfig.shared.string(forKey: "ask_provider") ?? "qwen")
        if model.providerName != provider { model.providerName = provider }
    }

    /// 键帽上的字：右⌥、⌘、自定义组合原样
    private static func keyCap(_ shortcut: RecordingHotkeyShortcut) -> String {
        switch shortcut {
        case .modifier(let m): return m == .rightOption || m == .rightCommand ? "右\(m.symbol)" : m.symbol
        case .custom(let c): return c.displayName
        }
    }

    static func providerName(_ id: String) -> String {
        switch id {
        case "deepseek": return "DeepSeek"
        case "doubao": return "豆包"
        case "zhipu": return "智谱"
        default: return "千问"
        }
    }

    private func applyAppearance() {
        guard let panel else { return }
        let appearance = MainWindowAppearance.resolve()
        if panel.appearance?.name != appearance.name { panel.appearance = appearance }
    }

    /// 新话题刚开始：内容只有一行「正在思考…」，高度是已知的。这时不去问 measure：
    /// 它不在屏幕上，SwiftUI 更新得慢半拍，量到的还是上一条回答的高度（2026-09-21 实测 593，应为 145），
    /// 浮窗会先按旧高度摆出来、上下各露一条空底，等主线程空下来才缩回去。
    private var trustMeasure = true
    private static let thinkingRowHeight: CGFloat = 24

    private func fittingSize(of hosting: FirstMouseHostingView) -> NSSize {
        if let measure, trustMeasure {
            measure.layoutSubtreeIfNeeded()
            let h = measure.fittingSize.height
            if h > 1, abs(h - model.contentHeight) > 0.5 {
                model.contentHeight = h
                hosting.layoutSubtreeIfNeeded()
            }
        }
        var size = hosting.fittingSize
        if size.width < 10 || size.height < 10 { size = NSSize(width: Self.width, height: 120) }
        size.width = model.collapsed ? Self.collapsedWidth : Self.width
        return size
    }

    /// 内容高度变了 → 面板跟着长/缩，顶右角不动；对话超过上限后始终滚到最新一轮
    /// animated=false：直接定到新尺寸。新问题顶掉上一条回答时用，旧高度只该一闪而过，不该慢慢缩
    private func relayout(animated: Bool = true, streaming: Bool = false) {
        guard let panel, let hosting else { return }
        DispatchQueue.main.async {
            hosting.layoutSubtreeIfNeeded()
            self.tuneScroller()
            var target = self.fittingSize(of: hosting)
            let current = panel.frame
            self.scrollToBottom()
            if streaming {
                // 只长不缩，且按整步长；步长撑不过内容区上限（超过上限的部分靠滚动）
                let clampedContent = min(max(self.model.contentHeight, 24), self.model.maxContentHeight)
                let maxWindow = target.height - clampedContent + self.model.maxContentHeight
                let stepped = min((target.height / Self.streamingStep).rounded(.up) * Self.streamingStep, maxWindow)
                target.height = max(current.height, stepped)
                guard target.height > current.height + 0.5 else { return }
            }
            guard abs(target.height - current.height) > 0.5 || abs(target.width - current.width) > 0.5 else { return }
            AnswerPanel.log?(String(format: "AnswerPanel relayout content=%.1f target=%.1f current=%.1f", self.model.contentHeight, target.height, current.height))
            let frame = NSRect(x: current.maxX - target.width, y: current.maxY - target.height,
                               width: target.width, height: target.height)
            // 流式出字期间每段都会长高：不做动画，直接定到新高度。动画途中窗口比内容矮，
            // 文字会被往上挤、一段一跳；逐字流出本身就是过渡，不需要再补动画。
            if !animated || self.model.turns.last?.state == .streaming {
                panel.setFrame(frame, display: true)
                if let content = panel.contentView { hosting.frame = content.bounds }
                panel.invalidateShadow()
                self.scrollToBottom()
                return
            }
            self.layoutGeneration += 1
            let generation = self.layoutGeneration
            self.frameAnimationEnds = Date().addingTimeInterval(0.22)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.9, 0.3, 1.0)
                panel.animator().setFrame(frame, display: true)
            }, completionHandler: { [weak self, weak panel, weak hosting] in
                guard let panel, let hosting, let content = panel.contentView else { return }
                hosting.frame = content.bounds
                panel.invalidateShadow()
                self?.scrollToBottom()
                // 被新一次动画打断的旧动画也会走到这里：只让最后一次核对，否则动画途中会互相重排成一串
                if self?.layoutGeneration == generation {
                    self?.frameAnimationEnds = .distantPast   // 动画确实结束了，回调可能比预计时刻早一两毫秒
                    self?.settleLayout()
                }
            })
        }
    }

    /// 收起 / 展开是先改 model 再量尺寸，但 SwiftUI 要到下一轮才把小框和完整内容换过来，
    /// 量早了拿到的还是换之前的高度：小框悬在一个高窗口中间，或者完整内容挤在小框大小的窗口里
    /// （2026-09-21 实测收起后窗口 320x190，应为 320x54）。所以状态切换后隔一会儿再量一次，
    /// 动画结束后也核对一次，对不上就重排；对得上时 relayout 自己会直接返回，不会循环。
    private func settleLayout() {
        guard let panel, let hosting, panel.isVisible, Date() >= frameAnimationEnds else { return }
        hosting.layoutSubtreeIfNeeded()
        let target = fittingSize(of: hosting)
        let current = panel.frame
        // 核对是纠错，直接定到位。走动画的话，这 0.22 秒里流式出字还在直接设尺寸，两边会打架，
        // 窗口最后停在动画的旧目标上，比内容矮一截，头尾被切掉（DeepSeek 出字快，整条回答 0.3 秒内就流完）
        if abs(target.height - current.height) > 0.5 || abs(target.width - current.width) > 0.5 { relayout(animated: false) }
    }

    /// 回答出完后再核对两次：最后一段文字进来时 measure 可能还没跟上，量到的高度会少一段
    private func settleAfterFinish() {
        for delay in [0.35, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.model.collapsed else { return }
                self.frameAnimationEnds = .distantPast
                self.settleLayout()
            }
        }
    }

    private func relayoutAfterStateChange(animated: Bool = true) {
        refreshViewsForNewContent()
        relayout(animated: animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.settleLayout() }
    }

    private func beginFollowUp() -> Bool {
        guard !followUpActive, onFollowUpStart?() == true else { return false }
        followUpActive = true
        return true
    }

    private func endFollowUp(cancelled: Bool) {
        guard followUpActive else { return }
        followUpActive = false
        onFollowUpEnd?(cancelled)
    }

    /// 兜底：不管哪个子视图吞了事件，本 App 收到「左键松开」就结束续聊录音
    private func installMouseUpMonitor() {
        removeMouseUpMonitor()
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self, self.followUpActive else { return event }
            DispatchQueue.main.async { self.endFollowUp(cancelled: self.model.cancelArmed) }
            return event
        }
    }

    /// 没固定时，点面板外任何地方就收起（全局监听收不到自己窗口里的点击，所以面板内点击天然不算）
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.model.pinned, self.panel?.isVisible == true, !self.model.collapsed else { return }
            self.collapse()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor); self.outsideClickMonitor = nil }
    }

    private func removeMouseUpMonitor() {
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor); self.mouseUpMonitor = nil }
    }

    // MARK: - 点外面缩成小框

    private func collapse() {
        guard let panel, panel.isVisible, !model.pinned, !model.collapsed else { return }
        // 回答还在出 / 正在录音：先不缩，出完再缩
        if model.recording || model.turns.last.map({ $0.state == .thinking || $0.state == .streaming }) == true {
            collapseWhenDone = true
            return
        }
        model.collapsed = true
        hoverArmed = true
        relayoutAfterStateChange()
        startDismissCountdown()
        startHoverPolling()
    }

    private func expand() {
        cancelDismissCountdown()
        guard model.collapsed else { return }
        model.collapsed = false
        relayoutAfterStateChange()
    }

    private func togglePin() {
        model.pinned.toggle()
        if model.pinned {
            // 小框上点图钉 = 我要留着：直接展开并固定
            cancelDismissCountdown()
            stopHoverPolling()
            hoverArmed = false
            collapseWhenDone = false
            if model.collapsed { model.collapsed = false; relayoutAfterStateChange() }
        }
    }

    private func resetCollapse() {
        cancelDismissCountdown()
        stopHoverPolling()
        hoverArmed = false
        collapseWhenDone = false
        if model.collapsed { model.collapsed = false }
    }

    /// 小框静止 4s，最后 1s 淡出，然后收起
    private func startDismissCountdown() {
        dismissTimer?.invalidate()
        panel?.alphaValue = 1
        let t = Timer(timeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self, let panel = self.panel, self.model.collapsed else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 1.0
                panel.animator().alphaValue = 0.1
            }, completionHandler: { [weak self] in
                guard let self, self.model.collapsed, self.dismissTimer != nil else { return }
                self.hide()
            })
        }
        RunLoop.main.add(t, forMode: .common)
        dismissTimer = t
    }

    private func cancelDismissCountdown() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 1
        }
    }

    /// 20Hz 看鼠标在不在面板上：小框上停留 150ms 才算「回来」（去菜单栏顺路擦过不算）；回满后离开就再缩
    private func startHoverPolling() {
        guard hoverTimer == nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.hoverTick() }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    private func stopHoverPolling() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverSince = nil
    }

    private func hoverTick() {
        guard let panel, panel.isVisible, hoverArmed, !model.pinned else { stopHoverPolling(); return }
        let inside = NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
        if model.collapsed {
            if inside {
                if hoverSince == nil { hoverSince = Date() }
                if Date().timeIntervalSince(hoverSince!) >= 0.15 { hoverSince = nil; expand() }
            } else {
                hoverSince = nil
            }
        } else if !inside, !model.recording {
            collapse()
        }
    }

    /// 找到 SwiftUI ScrollView 背后的 NSScrollView，直接滚到底
    private func scrollToBottom() {
        guard model.turns.count > 1 else { return }   // 只有一轮长回答时停在开头，从上往下读
        guard let hosting, let sv = Self.findScrollView(in: hosting), let doc = sv.documentView else { return }
        sv.layoutSubtreeIfNeeded()
        let clipH = sv.contentView.bounds.height
        let docH = doc.frame.height
        guard docH > clipH + 0.5 else { return }
        let y = doc.isFlipped ? docH - clipH : 0
        sv.contentView.scroll(to: NSPoint(x: 0, y: y))
        sv.reflectScrolledClipView(sv.contentView)
    }

    /// 滚动条收细：强制细一号的 overlay 样式 —— 不占布局、不滚动时自动淡出、贴着面板右内缘。
    /// 系统设成「始终显示滚动条」时也照样 overlay：这是悬浮面板，与通知中心同款做法
    private func tuneScroller() {
        guard let hosting, let sv = Self.findScrollView(in: hosting) else { return }
        if sv.scrollerStyle != .overlay { sv.scrollerStyle = .overlay }
        sv.autohidesScrollers = true
        sv.scrollerKnobStyle = .default
        if let scroller = sv.verticalScroller {
            if scroller.controlSize != .small { scroller.controlSize = .small }
            scroller.scrollerStyle = .overlay
        }
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        for sub in view.subviews {
            if let sv = sub as? NSScrollView { return sv }
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }

    /// 「复制」复制标题栏正显示的那一轮回答（标题跟着滚动走，看的是哪轮就复制哪轮）
    private var lastAnswer: String? {
        let i = model.headerIndex
        if model.turns.indices.contains(i), model.turns[i].state == .answered { return model.turns[i].answer }
        return model.turns.last(where: { $0.state == .answered })?.answer
    }

    private func copyAnswer() {
        guard let text = lastAnswer, !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Self.plainText(fromMarkdown: text), forType: .string)
        model.copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.model.copied = false }
    }

    /// 复制到别处用纯文本：小标题去掉 #、加粗去掉 **、条目统一成「• 」/「1. 」、多余空行合并
    static func plainText(fromMarkdown md: String) -> String {
        var lines: [String] = []
        for raw in md.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            line = line.replacingOccurrences(of: "**", with: "")
            line = line.replacingOccurrences(of: #"^[-•·*]\s+"#, with: "• ", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^(\d+)[.、)）]\s+"#, with: "$1. ", options: .regularExpression)
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }   // 合并连续空行、去掉开头空行
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel, event.keyCode == 53 else { return event }
            self.hide()
            return nil
        }
    }

    private func removeEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor); self.escMonitor = nil }
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// 可拉伸的圆角遮罩图（NSVisualEffectView 官方圆角姿势）
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// 面板平时不是 key window（用户在别的 App 里），第一下按下默认会被系统吞掉去「激活窗口」，
/// 长按续聊就收不到；声明接受第一下鼠标，按下即达。
private final class FirstMouseHostingView: NSHostingView<AnswerView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 无边框面板默认不能成为 key window，选文字 / Esc 都需要它能
private final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

// MARK: - 数据

struct AnswerTurn: Identifiable {
    enum State { case thinking, streaming, answered, failed }
    let id = UUID()
    let question: String
    var answer = ""
    var state: State = .thinking
    /// 这一轮的小灰字（正在联网查、网络较慢、在想），显示在回答上方
    var note: String?
    /// 这次没看屏幕的原因：回答上面一条橙底提示；needsPermission 时带「去授权」
    var screenNote: String?
    var screenNeedsPermission = false
    /// 这一问转去联网查了（状态条写「联网」）
    var searched = false
    /// 没答成：报错卡
    var failure: AskFailure?
    /// 联网回答附的图（回答下方一排小图，点开看大图）
    var images: [AskImage] = []
    /// 这一轮发给模型的截图（问题右边的缩略图）
    var screenshot: AskScreenshot?
}

struct AskScreenshot {
    let closeUp: NSImage
    let overview: NSImage
    let closeUpJPEG: Data
    let overviewJPEG: Data
}

/// 卡片还开着时换了话题：旧话题折成卡顶一行「上个话题：… · 2 问」
struct PreviousTopic {
    let question: String
    let turns: [AnswerTurn]
}

/// 没答成的几种情况：每种一句标题、一句怎么办、一两个按钮（design/panels A2）
enum AskFailure: Equatable {
    case noKey, invalidKey, quota, timeout, offline
    case other(String)

    enum Action { case openModels, retry }

    var symbol: String {
        switch self {
        case .noKey, .invalidKey: return "key"
        case .quota: return "creditcard"
        case .timeout: return "clock"
        case .offline: return "wifi.slash"
        case .other: return "exclamationmark.bubble"
        }
    }

    /// 橙 = 还差一步，红 = 出错了
    var isError: Bool {
        switch self {
        case .noKey, .timeout, .offline: return false
        case .invalidKey, .quota, .other: return true
        }
    }

    func title(provider: String) -> String {
        switch self {
        case .noKey: return "还没填问答模型的 Key"
        case .invalidKey: return "\(provider) 不认这个 Key"
        case .quota: return "\(provider) 的额度用完了"
        case .timeout: return "\(provider) 没有回应"
        case .offline: return "连不上网络"
        case .other: return "没答成"
        }
    }

    func detail(provider: String) -> String {
        switch self {
        case .noKey: return "回答要用你自己的 AI Key。在「语音与模型」页填好 DeepSeek 或千问的 Key，就能接着问这一句。"
        case .invalidKey: return "可能复制少了几位，或者在官网删掉了。到「语音与模型」页重新粘贴，点「验证」试一下。"
        case .quota: return "账号欠费或免费额度用完了。到服务商控制台看看，或者在「语音与模型」页换一家。"
        case .timeout: return "可能是网络不稳，也可能是它正忙。"
        case .offline: return "检查一下网络，连上后再问一次。"
        case .other(let reason): return reason
        }
    }

    /// 第一个是黑色主按钮
    var actions: [(title: String, action: Action)] {
        switch self {
        case .noKey: return [("去填 Key", .openModels), ("填好了，再问一次", .retry)]
        case .invalidKey: return [("去换 Key", .openModels), ("重试", .retry)]
        case .quota: return [("去换一家", .openModels), ("重试", .retry)]
        case .timeout, .offline, .other: return [("再试一次", .retry)]
        }
    }
}

final class AnswerModel: ObservableObject {
    @Published var turns: [AnswerTurn] = []
    @Published var pinned = false
    @Published var recording = false
    @Published var cancelArmed = false
    @Published var copied = false
    enum FooterState { case idle, listening, processing, noSpeech, cancelled }
    @Published var footer: FooterState = .idle
    /// 底栏键帽：生效中的说话键（右⌥）和双击打字键（⌃）；没设就不写
    @Published var voiceKey: String?
    @Published var typeKey: String?
    /// 状态条「已答 · DeepSeek」的那一家
    @Published var providerName = "AI"
    @Published var previousTopic: PreviousTopic?
    @Published var showPrevious = false
    /// 旧的几轮默认压成两行，点开的记在这里
    @Published var expandedTurns: Set<UUID> = []
    let wave = PanelWaveClock()
    @Published var maxContentHeight: CGFloat = 400
    /// 「复制」复制哪一轮（跟着滚动走：哪一轮的问句块滚到上半部分就是哪一轮）
    @Published var headerIndex = 0
    /// 点外面后缩成只剩一行状态条的小框
    @Published var collapsed = false
    @Published var contentHeight: CGFloat = 40

    /// 状态条：粗体的状态 + 灰字的补充
    var status: (title: String, detail: String) {
        let answeredCount = turns.filter { $0.state == .answered }.count
        if recording { return ("正在听", answeredCount > 0 ? "第 \(turns.count + 1) 问" : "") }
        if footer == .processing { return ("识别中", "") }
        guard let last = turns.last else { return ("", "") }
        let nth = turns.count > 1 ? "第 \(turns.count) 问" : ""
        switch last.state {
        case .thinking:
            if last.note?.contains("联网") == true { return ("正在联网查", nth) }
            return ("在想", nth)
        case .streaming:
            return ("正在回答", nth)
        case .answered:
            let parts = [nth, providerName, last.searched ? "联网" : ""].filter { !$0.isEmpty }
            return ("已答", parts.joined(separator: " · "))
        case .failed:
            return ("没答成", nth)
        }
    }
}

// MARK: - 视图

struct AnswerView: View {
    @ObservedObject var model: AnswerModel
    let onCopy: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onHoldStart: () -> Bool
    let onHoldEnd: (_ cancelled: Bool) -> Void
    let onType: () -> Void
    let onAction: (AskFailure.Action) -> Void
    let onGrantScreen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            if !model.collapsed {
                Hairline()
                ScrollView(.vertical, showsIndicators: true) {
                    TurnsView(model: model, width: AnswerPanel.contentWidth, onAction: onAction, onGrantScreen: onGrantScreen)
                        .padding(.horizontal, AnswerPanel.contentInset)
                        .padding(.top, AnswerPanel.bodyPadding.top)
                        .padding(.bottom, AnswerPanel.bodyPadding.bottom)
                }
                .coordinateSpace(name: "answerScroll")
                .onPreferenceChange(TurnTopKey.self) { tops in
                    let threshold = min(model.contentHeight, model.maxContentHeight) * 0.5
                    let idx = tops.filter { $0.value <= threshold }.keys.max() ?? 0
                    if idx != model.headerIndex { model.headerIndex = idx }
                }
                // 高度由 AnswerPanel 离屏实测后写入 model，超过上限才滚动。窗口比内容高的那一瞬间
                // （流式出字时窗口按整步长预留），多出来的空间给回答区：状态条钉在顶上、底栏贴在底下
                .frame(minHeight: clampedContentHeight, idealHeight: clampedContentHeight, maxHeight: .infinity)
                Hairline()
                footer
            }
        }
        .frame(width: model.collapsed ? AnswerPanel.collapsedWidth : AnswerPanel.width)
        .frame(maxHeight: .infinity, alignment: .top)
        // 近实心的面板色：复杂背景上字也清楚
        .background(Theme.bg.opacity(0.94))
        .overlay(
            // 正在听：描一圈墨黑边；拖开要取消时变红
            RoundedRectangle(cornerRadius: AnswerPanel.cornerRadius, style: .continuous)
                .strokeBorder(model.cancelArmed ? Theme.danger : Theme.ink, lineWidth: 1.5)
                .opacity(model.recording ? 1 : 0)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.15), value: model.recording)
        )
    }

    private var clampedContentHeight: CGFloat {
        min(max(model.contentHeight, 24), model.maxContentHeight) + AnswerPanel.bodyPadding.top + AnswerPanel.bodyPadding.bottom
    }

    // MARK: 状态条

    /// 高度固定 40：换状态时卡片不跳
    private var statusBar: some View {
        let status = model.status
        return HStack(spacing: 8) {
            BrandGlyph().frame(width: 16, height: 16)
            if model.previousTopic != nil, model.turns.count == 1 {
                Text("新话题").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Theme.selected, in: RoundedRectangle(cornerRadius: 5))
            }
            HStack(spacing: 0) {
                Text(status.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                if !status.detail.isEmpty {
                    Text(" · " + status.detail).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            PanelIconButton(symbol: model.pinned ? "pin.fill" : "pin", on: model.pinned,
                            help: model.pinned ? "已钉住：点外面也不收起" : "钉住：点外面也不收起", action: onTogglePin)
            if !model.collapsed {
                PanelIconButton(symbol: model.copied ? "checkmark" : "doc.on.doc", on: false,
                                help: "复制这一轮回答", action: onCopy)
            }
            PanelIconButton(symbol: "xmark", on: false, help: "关掉，结束这个话题（Esc）", action: onClose)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(model.collapsed ? Color.clear : Theme.surface.opacity(0.9))
    }

    // MARK: 底栏

    @ViewBuilder private var footer: some View {
        HStack(spacing: 4) {
            switch model.footer {
            case .listening:
                PanelWave(clock: model.wave, color: model.cancelArmed ? Theme.danger : Theme.ink)
                Text(model.cancelArmed ? "松开就取消" : "松开就问；拖开取消")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            case .processing:
                ProgressView().controlSize(.mini)
                Text("识别中").font(.system(size: 12)).foregroundStyle(Theme.text2).padding(.leading, 4)
                Spacer(minLength: 0)
            case .noSpeech, .cancelled:
                Text(model.footer == .noSpeech ? "没听到问题" : "已取消").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            case .idle:
                HoldToAskButton(keyCap: model.voiceKey, onStart: onHoldStart, onEnd: onHoldEnd, model: model)
                FooterButton(symbol: "keyboard", title: "打字", prefix: model.typeKey == nil ? nil : "双击", keyCap: model.typeKey, action: onType)
                Spacer(minLength: 4)
                Text("开头说「新话题」另起").font(.system(size: 12)).foregroundStyle(Theme.text3).lineLimit(1)
                    .padding(.trailing, 4)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: 44)
    }
}

/// 对话正文：上个话题折叠行、编号连线的几轮问答。同一份视图既显示也离屏测高。
struct TurnsView: View {
    @ObservedObject var model: AnswerModel
    /// 显示与离屏测高用同一个宽度，换行才一致
    let width: CGFloat
    var onAction: (AskFailure.Action) -> Void = { _ in }
    var onGrantScreen: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let previous = model.previousTopic { previousTopic(previous) }
            ForEach(Array(model.turns.enumerated()), id: \.element.id) { index, turn in
                turnView(turn, index: index)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: TurnTopKey.self, value: [index: g.frame(in: .named("answerScroll")).minY])
                    })
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 上个话题

    @ViewBuilder private func previousTopic(_ previous: PreviousTopic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { model.showPrevious.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 12))
                    Text("上个话题：\(previous.question) · \(previous.turns.count) 问").lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: model.showPrevious ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if model.showPrevious {
                ForEach(previous.turns) { turn in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(turn.question).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                        Text(AnswerPanel.plainText(fromMarkdown: turn.answer)).font(.system(size: 13)).foregroundStyle(Theme.text2)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                }
            }
            HStack(spacing: 8) {
                Rectangle().fill(Theme.border).frame(height: 1)
                Text("新话题").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text3).fixedSize()
                Rectangle().fill(Theme.border).frame(height: 1)
            }
        }
        .padding(.bottom, 14)
    }

    // MARK: 一轮

    @ViewBuilder private func turnView(_ turn: AnswerTurn, index: Int) -> some View {
        let multi = model.turns.count > 1
        let isLast = index == model.turns.count - 1
        let compact = multi && !isLast && !model.expandedTurns.contains(turn.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    if multi && index > 0 {
                        Text("追问").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3)
                    }
                    Text(turn.question)
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .foregroundStyle(compact ? Theme.text2 : Theme.text)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let shot = turn.screenshot, !compact { ScreenThumb(shot: shot) }
            }
            if compact {
                Button { model.expandedTurns.insert(turn.id) } label: {
                    Text(AnswerPanel.plainText(fromMarkdown: turn.answer))
                        .font(.system(size: 13)).foregroundStyle(Theme.text2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("点一下看全文")
                .accessibilityHint("展开这一轮的全文")
            } else {
                answerBody(turn, isLast: isLast)
            }
        }
        .padding(.leading, multi ? 30 : 0)
        .padding(.bottom, 14)
        // 编号之间的竖线：从这一问的圆圈下面连到下一问
        .background(alignment: .topLeading) {
            if multi && !isLast {
                Rectangle().fill(Theme.borderStrong).frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 22)
                    .padding(.bottom, -17)   // 连到下一问的圆圈（它在「追问」小字下面）
                    .padding(.leading, 9.25)
            }
        }
        .overlay(alignment: .topLeading) {
            if multi {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isLast ? Theme.onInk : Theme.text2)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(isLast ? Theme.ink : Theme.elevated))
                    .overlay(Circle().strokeBorder(isLast ? Theme.ink : Theme.borderStrong, lineWidth: 1.5))
                    .padding(.top, index > 0 ? 17 : 1)
            }
        }
    }

    @ViewBuilder private func answerBody(_ turn: AnswerTurn, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 「这次没看屏幕」只挂在当前这一问上，展开看旧的几轮时不重复
            if isLast, let screenNote = turn.screenNote { screenBanner(screenNote, needsPermission: turn.screenNeedsPermission) }
            if let note = turn.note, !note.isEmpty, turn.state != .failed {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 11))
                    Text(note).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            answerContent(turn)
            if !turn.images.isEmpty { AskImagesRow(images: turn.images) }
        }
    }

    /// 这次没看屏幕：橙底一条，没给权限时带「去授权」
    private func screenBanner(_ text: String, needsPermission: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "display").font(.system(size: 13)).foregroundStyle(Theme.warn)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if needsPermission {
                Button("去授权", action: onGrantScreen).buttonStyle(PanelButtonStyle(solid: false, small: true))
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func answerContent(_ turn: AnswerTurn) -> some View {
        switch turn.state {
        case .thinking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(turn.screenshot == nil ? "在想…" : "看着你指的地方，在想…").font(.system(size: 13)).foregroundStyle(Theme.text3)
            }
            .padding(.vertical, 4)
        case .streaming, .answered:
            AnswerText(text: turn.answer)
        case .failed:
            if let failure = turn.failure {
                FailureCard(failure: failure, provider: model.providerName, onAction: onAction)
            } else {
                Text(turn.answer).font(.system(size: 14)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 报错块：左边事物图标加橙 / 红角标，一句标题、一句怎么办、按钮
private struct FailureCard: View {
    let failure: AskFailure
    let provider: String
    let onAction: (AskFailure.Action) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: failure.symbol).font(.system(size: 15)).foregroundStyle(Theme.text)
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
                Text(failure.detail(provider: provider)).font(.system(size: 13)).foregroundStyle(Theme.text2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(Array(failure.actions.enumerated()), id: \.offset) { i, item in
                        Button(item.title) { onAction(item.action) }
                            .buttonStyle(PanelButtonStyle(solid: i == 0, small: false))
                    }
                }
                .padding(.top, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

/// 问题右边的小缩略图：这次发给 AI 的画面（细红框框着指的地方）；点开看「指着的地方」和「整个屏幕」两张
private struct ScreenThumb: View {
    let shot: AskScreenshot
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            Image(nsImage: shot.overview)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 58, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(hovering ? Theme.text2 : Theme.borderStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("发给 AI 的画面，红框是你指着的地方。点开看大图")
        .accessibilityLabel("发给 AI 的截图")
        .accessibilityHint("用「预览」打开指着的地方和整个屏幕两张图")
    }

    /// 两张图写进临时文件夹，用「预览」打开（本机文件，不走外部链接）
    private func open() {
        let dir = FileManager.default.temporaryDirectory
        do {
            for (name, jpeg) in [("askfree-screen", shot.overviewJPEG), ("askfree-closeup", shot.closeUpJPEG)] {
                let url = dir.appendingPathComponent("\(name).jpg")
                try jpeg.write(to: url)
                NSWorkspace.shared.open(url)
            }
        } catch {
            AnswerPanel.log?("ASK screenshot open failed: \(error.localizedDescription)")
        }
    }
}

/// 回答下面的一排图（模型点名要图，或联网时顺手找的）：固定 3 格、竖长方形，人像照片也看得清脸；
/// 点一张用默认浏览器打开原图（来源网页在悬停提示里）。尺寸固定是为了图片加载完成时不用再重排浮窗。
struct AskImagesRow: View {
    let images: [AskImage]
    @State private var hovering: String?
    private static let spacing: CGFloat = 8
    private static let cellWidth = (AnswerPanel.contentWidth - spacing * 2) / 3
    private static let cellHeight: CGFloat = 160

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                Button { AppLinks.safeOpen(image.full) } label: {
                    AsyncImage(url: URL(string: image.thumb)) { phase in
                        switch phase {
                        // 填满格子、从顶上裁：人像的脸一般在上半部
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                                .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
                        case .failure: Image(systemName: "photo").foregroundStyle(Theme.text3)
                        default: ProgressView().controlSize(.small)
                        }
                    }
                    .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(hovering == image.id ? Theme.text2 : Theme.border))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 ? image.id : nil }
                .help(image.title.isEmpty ? image.pageURL : image.title)
                .accessibilityLabel(image.title.isEmpty ? "找到的第 \(index + 1) 张图" : "第 \(index + 1) 张图：\(image.title)")
                .accessibilityHint("用浏览器打开原图")
            }
        }
        .padding(.top, 2)
    }
}

/// 回答正文：轻量 Markdown —— 空行分段、「### 」小标题、「- 」「1. 」条目（悬挂缩进）、**加粗**；正文 14 号
struct AnswerText: View {
    let text: String
    private let body14 = Font.system(size: 14)

    private enum Block { case heading(String), paragraph(String), bullet(String), numbered(String, String) }

    private var blocks: [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para.removeAll() }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { out.append(.heading(title)) }
                continue
            }
            if let r = line.range(of: #"^(?:[-•·*]|\d+[.、)）])\s+"#, options: .regularExpression) {
                flush()
                let marker = String(line[r.lowerBound..<r.upperBound]).trimmingCharacters(in: .whitespaces)
                let body = String(line[r.upperBound...])
                if marker.first?.isNumber == true {
                    let num = marker.trimmingCharacters(in: CharacterSet(charactersIn: ".、)）")) + "."
                    out.append(.numbered(num, body))
                } else {
                    out.append(.bullet(body))
                }
            } else {
                para.append(line)
            }
        }
        flush()
        return out
    }

    /// 行内 Markdown（加粗/斜体）→ Text；解析失败或流式中途符号不配对时按纯文本显示
    private func inline(_ s: String) -> Text {
        if s.contains("*") || s.contains("`"),
           let attr = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .heading(let s):
                    inline(s).font(.system(size: 14, weight: .semibold))
                        .padding(.top, index == 0 ? 0 : 6)
                        .fixedSize(horizontal: false, vertical: true)
                case .paragraph(let s):
                    inline(s).font(body14).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.text3).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        inline(s).font(body14).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 3)
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(n).font(body14).foregroundStyle(Theme.text2).monospacedDigit()
                            .frame(minWidth: 18, alignment: .trailing)
                        inline(s).font(body14).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, .safe)
    }
}

/// 状态条左边的小标志：Ask Free 的指针问号，跟字一个颜色
private struct BrandGlyph: View {
    var body: some View {
        if let image = NSImage(named: "statusbar-icon") {
            Image(nsImage: image).resizable().renderingMode(.template).foregroundStyle(Theme.text)
        }
    }
}

/// 状态条右边三个一样的图标钮：28×28、圆角 6、悬停加底
private struct PanelIconButton: View {
    let symbol: String
    let on: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(on || hovering ? Theme.text : Theme.text2)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 面板里的按钮：实心墨黑主按钮一张面板最多一个，其余白底描边
private struct PanelButtonStyle: ButtonStyle {
    let solid: Bool
    let small: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 12 : 13, weight: .medium))
            .foregroundStyle(solid ? Theme.onInk : Theme.text)
            .padding(.horizontal, small ? 9 : 12)
            .frame(height: small ? 24 : 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(solid ? Theme.ink : Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(solid ? Color.clear : Theme.borderStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

/// 底栏键帽：右⌥、⌃
private struct PanelKeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.borderStrong, lineWidth: 1))
    }
}

/// 底栏的「打字」：图标 + 字 + 「双击 ⌃」
private struct FooterButton: View {
    let symbol: String
    let title: String
    let prefix: String?
    let keyCap: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(title)
                if let prefix { Text(prefix).foregroundStyle(Theme.text3) }
                if let keyCap { PanelKeyCap(text: keyCap) }
            }
            .font(.system(size: 12))
            .foregroundStyle(hovering ? Theme.text : Theme.text2)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 底栏的「按住追问」：按下就开始说，松开就问；按着拖开 70 点算取消（拖回来又不取消）
private struct HoldToAskButton: View {
    let keyCap: String?
    let onStart: () -> Bool
    let onEnd: (_ cancelled: Bool) -> Void
    @ObservedObject var model: AnswerModel
    @State private var pressStart: CGPoint?
    @State private var active = false
    @State private var dragCancel = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic").font(.system(size: 12))
            Text("按住追问")
            if let keyCap { PanelKeyCap(text: keyCap) }
        }
        .font(.system(size: 12))
        .foregroundStyle(hovering || active ? Theme.text : Theme.text2)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.selected : (hovering ? Theme.hover : .clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if pressStart == nil {
                        pressStart = value.startLocation
                        dragCancel = false
                        active = onStart()
                    }
                    guard active, let start = pressStart else { return }
                    let d = hypot(value.location.x - start.x, value.location.y - start.y)
                    let armed = dragCancel ? d > 45 : d >= 70
                    if armed != dragCancel { dragCancel = armed; model.cancelArmed = armed }
                }
                .onEnded { _ in
                    if active { onEnd(dragCancel) }
                    active = false
                    dragCancel = false
                    pressStart = nil
                }
        )
        .help("按住说话追问，松开就问")
        .accessibilityLabel("按住追问")
    }
}

/// 面板底栏音浪的时钟：60Hz、common 模式（按住鼠标时主线程在追踪模式，默认模式定时器和 TimelineView 都不走）。
/// 算法与 SiriCapsuleView.tick 完全一样：快起慢落 + 目标值衰减 + 钟形包络 + 三个正弦叠加 + 抖动。
final class PanelWaveClock: ObservableObject {
    static let bars = 9
    @Published var heights: [CGFloat] = Array(repeating: 3, count: PanelWaveClock.bars)
    var level: CGFloat = 0
    private var smooth: CGFloat = 0
    private var time: Double = 0
    private var timer: Timer?
    let maxHeight: CGFloat = 24

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        level = 0
        smooth = 0
        heights = Array(repeating: 3, count: Self.bars)
    }

    private func tick() {
        if level > smooth { smooth += (level - smooth) * 0.4 } else { smooth += (level - smooth) * 0.08 }
        level *= 0.92
        time += 0.016 * 1.2
        let energy = max(smooth, 0.15)
        var next = heights
        for i in 0..<Self.bars {
            let pos = CGFloat(i) / CGFloat(Self.bars - 1)
            let bell = exp(-pow((pos - 0.5) * 2.0, 2))
            let wave = 0.6 + sin(time * 4.0 + Double(i) * 0.4) * 0.3 + sin(time * 6.5 + Double(i) * 0.7) * 0.2 + sin(time * 3.0 + Double(i) * 0.2) * 0.15
            let jitter = CGFloat.random(in: -1.5...1.5) * energy * 4
            let target = max(3, min(maxHeight, 3 + pow(energy, 0.7) * maxHeight * bell * CGFloat(wave) + jitter))
            next[i] += (target - next[i]) * 0.4
        }
        heights = next
    }
}

/// 面板底栏音浪：墨黑竖条
private struct PanelWave: View {
    @ObservedObject var clock: PanelWaveClock
    let color: Color
    private let barW: CGFloat = 3
    private let gap: CGFloat = 2.5

    var body: some View {
        Canvas { g, size in
            for (i, raw) in clock.heights.enumerated() {
                let h = max(raw, 3)
                let rect = CGRect(x: CGFloat(i) * (barW + gap), y: (size.height - h) / 2, width: barW, height: h)
                g.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(color))
            }
        }
        .frame(width: CGFloat(PanelWaveClock.bars) * (barW + gap) - gap, height: 28)
        .padding(.leading, 6)
    }
}

/// 每一轮在滚动区里的顶边 y（滚动坐标系），用来决定「复制」复制哪一轮
private struct TurnTopKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
