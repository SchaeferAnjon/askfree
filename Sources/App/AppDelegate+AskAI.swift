import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension AppDelegate {
    /// 提问录音结束：识别出问题交给 AI，答案流进回答面板。
    func stopRecordingAndAsk() {
        guard isRecording else { return }
        let followUp = voiceQuestionFollowUp
        voiceQuestionFollowUp = false
        let continuesThread = followUp || askContinuesThread
        askContinuesThread = false
        answerPanel.setRecording(false)
        isRecording = false
        resetHotkeyGestures()
        isProcessing = true
        if followUp { answerPanel.setListening(.processing) } else { overlayWindow.show(state: .processing(message: "→ AI")) }
        let noSpeech: () -> Void = { [weak self] in
            guard let self else { return }
            self.finishAsk()
            if followUp { self.answerPanel.setListening(.noSpeech) } else { self.overlayWindow.showHint("没听到问题", accent: .neutral) }
        }
        let transcribeStartedAt = Date()
        audioRecorder.stopRecording { [weak self] samples in
            guard let self else { return }
            guard let samples, samples.count > 16000 / 2 else {
                DispatchQueue.main.async { noSpeech() }
                return
            }
            self.cloudTranscriber.transcribe(samples: samples) { [weak self] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .success(let raw):
                        let spoken = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "。．.，,！!？?；;"))
                        self.askTiming.transcribeMs = Int(Date().timeIntervalSince(transcribeStartedAt) * 1000)
                        if !self.submitQuestion(spoken, continuesThread: continuesThread) { noSpeech() }
                    case .failure(let err):
                        // 没听到有效语音：安静地提示一次，不走红框 + 文字条的两段式报错
                        if case CloudASRTranscriber.TranscriptionError.noSpeech = err { noSpeech(); return }
                        self.finishAsk()
                        self.answerPanel.setListening(.idle)
                        let message = (err as? LocalizedError)?.errorDescription ?? "识别失败"
                        self.showError(message)
                    }
                }
            }
        }
    }

    /// 问题文字到手（语音识别出来的、打字的）：定下接着聊还是新话题，带上屏幕发出去。
    /// 返回 false = 去掉「新话题」几个字后什么都不剩，没发
    @discardableResult
    func submitQuestion(_ text: String, continuesThread: Bool) -> Bool {
        // 浮窗还在但想换话题：用「新话题」开头，这几个字不算进问题里
        let (question, wantsNewThread) = AskThreading.stripNewThreadPrefix(text)
        let continuesThread = continuesThread && !wantsNewThread
        guard !question.isEmpty else { return false }
        debugLog("ASK question chars=\(question.count) trigger=\(askTiming.trigger) continuesThread=\(continuesThread)")
        overlayWindow.hide()
        answerPanel.setListening(.idle)
        // 带不带历史和追加还是新开话题用同一个判断：识别期间浮窗被关掉了就是新话题，不能带旧历史
        let appending = continuesThread && answerPanel.isVisible && !askInFlight
        let history = appending ? answerPanel.history : []
        // 面板上换成这一轮之前先换编号：上一轮还在路上的回调从这一刻起就不能再写进面板
        askRound += 1
        let round = askRound
        if appending { answerPanel.appendQuestion(question) } else { answerPanel.startThread(question: question) }
        // 图只随当轮发：多轮追问不重复传图（截图另存进历史，见 recordHistory）。
        // 追问照样截图，但先只发文字，模型说要看屏幕才发（AskScreenTool）
        resolveAskScreen { screen, note in
            self.sendAsk(question: question, history: history, screen: screen, screenNote: note, round: round)
        }
        return true
    }

    /// 启动参数 -askText：在指针处截屏，把这句话当成识别出的问题发出去（开发实测用，跳过录音和识别）
    func devAsk(_ question: String) {
        debugLog("Launch argument: ask \(question.count) chars")
        askTiming = AskTiming()
        startAskScreenCapture(at: CGEvent(source: nil)?.location ?? .zero)
        askRound += 1
        let round = askRound
        answerPanel.startThread(question: question)
        // 真实使用时截图和说话并行；这里没有说话那几秒，先等 3 秒再取图
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.resolveAskScreen { screen, note in
                self.sendAsk(question: question, history: [], screen: screen, screenNote: note, round: round)
            }
        }
    }

    /// 把问题（可能带屏幕内容）发给模型，逐字流进面板。
    /// screenNote 非空 = 这次没能带屏幕内容，原因直接写在面板上，不静默。
    private func sendAsk(question: String,
                         history: [(question: String, answer: String)],
                         screen: AskAI.AskScreenContext?,
                         screenNote: String?,
                         round: Int) {
        let thread = answerPanel.threadID
        lastAskScreen = screen
        let draft = AskHistoryDraft()
        draft.via = Self.historyVia(trigger: askTiming.trigger)
        askInFlight = true
        // 问题已经发出，回答在面板里流式显示：放开录音，别让所有快捷键在回答的十几秒里都没反应
        finishAsk()
        if let screenNote {
            let needsPermission = screenNote == ScreenSnapshotError.noPermission.userMessage
            if !needsPermission && ScreenSnapshotCapturer.needsRelaunch {
                // 权限是启动后才给的：截屏要换个新进程才生效，说清楚并给「重新打开」
                answerPanel.setScreenNote("这次没看屏幕：屏幕录制刚打开，重新打开 Ask Free 后生效", action: .relaunch)
            } else {
                answerPanel.setScreenNote(Self.screenBannerText(screenNote, needsPermission: needsPermission),
                                          action: needsPermission ? .grant : nil)
            }
        }

        // 首字迟迟不来就在面板里说一声，别让用户盯着「正在思考…」干等
        askSlowHintWork?.cancel()
        let slowHint = DispatchWorkItem { [weak self] in
            guard let self, self.askRound == round else { return }
            self.answerPanel.setNote("网络较慢，还在等模型回答…")
        }
        askSlowHintWork = slowHint
        DispatchQueue.main.asyncAfter(deadline: .now() + AskVision.slowHintAfter, execute: slowHint)

        askAI.answer(question: question, history: history, screen: screen, onPartial: { [weak self] partial in
            guard let self, self.askRound == round else { return }
            self.askSlowHintWork?.cancel()
            self.answerPanel.updatePartial(partial)
        }, onImages: { [weak self] images in
            self?.recordHistoryImages(images, draft: draft)
            // 只挂在还是这一话题、这一轮的浮窗上；用户已经问了下一题就丢掉
            guard let self, self.askRound == round, self.answerPanel.threadID == thread else { return }
            self.answerPanel.setImages(images)
        }, onScreenUsed: { [weak self] in
            draft.screenUsed = true
            // 追问时模型不一定看屏幕：真发给它了才挂截图，没挂就是只按前面的对话答的
            guard let self, let screen, self.askRound == round else { return }
            self.answerPanel.setScreenshot(overviewJPEG: screen.overviewJPEG, closeUpJPEG: screen.closeUpJPEG)
        }, onRouteNote: { [weak self] note in
            // 这一问转去联网了：「正在联网查…」→ 出字后换成「已联网查询」；状态条答完写「联网」
            draft.searched = true
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.askRound == round else { return }
                self.answerPanel.markSearched()
                self.answerPanel.setNote(note)
            }
        }, onThinking: { [weak self] in
            // 模型真的开始吐思考内容（关思考没生效）会先沉默一阵：告诉用户它在想，不是卡住了
            guard let self, self.askRound == round else { return }
            self.answerPanel.setNote(AskVision.thinkingNotice)
        }, onStats: { [weak self] stats in
            guard let self, self.askRound == round else { return }
            self.askTiming.modelStats = stats
        }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                // 用户已经问了下一题（另起了话题）：旧回答不碰面板
                guard self.askRound == round else { return }
                self.askInFlight = false
                self.askSlowHintWork?.cancel()
                self.askSlowHintWork = nil
                let totalMs = Int(Date().timeIntervalSince(self.askTiming.startedAt) * 1000)
                switch result {
                case .success(let answer):
                    self.debugLog("ASK answered chars=\(answer.count) \(self.askTiming.summary(totalMs: totalMs))")
                    self.answerPanel.finish(answer: answer)
                    self.recordHistory(draft, thread: thread, question: question, answer: answer,
                                       screen: draft.screenUsed ? screen : nil)
                case .failure(let err):
                    let reason = (err as? LocalizedError)?.errorDescription ?? "\(err)"
                    self.debugLog("ASK failed: \(reason) \(self.askTiming.summary(totalMs: totalMs))")
                    self.answerPanel.fail(Self.askFailure(from: err))
                }
            }
        }
    }

    /// 报错卡「重试」：同一个话题里把这一句再问一遍，屏幕内容照上次的发
    func retryAsk(_ question: String) {
        guard !askInFlight else { return }
        askTiming.reset(trigger: "retry", mode: "panel")
        let history = answerPanel.history
        askRound += 1
        let round = askRound
        answerPanel.appendQuestion(question)
        sendAsk(question: question, history: history, screen: lastAskScreen, screenNote: nil, round: round)
    }

    /// 回答失败的原因分成几类，面板按类给标题、怎么办和按钮；认不出的原样写出来
    static func askFailure(from err: Error) -> AskFailure {
        if case AskAI.AskError.noAPIKey = err { return .noKey }
        if case AskAI.AskError.quotaExhausted = err { return .quota }
        if let url = err as? URLError {
            switch url.code {
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return .offline
            default: break
            }
        }
        let reason = (err as? LocalizedError)?.errorDescription ?? "\(err)"
        if reason.hasPrefix("API Key 无效") { return .invalidKey }
        if reason.hasPrefix("账号欠费") { return .quota }
        return .other(reason)
    }

    /// 「这次没看屏幕：…」：去掉原因里「这次只按问题回答」那半句，面板上一行说完
    static func screenBannerText(_ note: String, needsPermission: Bool) -> String {
        if needsPermission { return "这次没看屏幕：还没给屏幕录制权限" }
        let reason = note.components(separatedBy: "，这次只按问题回答").first ?? note
        return "这次没看屏幕：" + reason.trimmingCharacters(in: CharacterSet(charactersIn: "。"))
    }

    /// 答完的一轮记进历史：文字、真发给模型的截图、已经到了的图；开着的历史页跟着刷新
    private func recordHistory(_ draft: AskHistoryDraft, thread: String, question: String, answer: String,
                               screen: AskAI.AskScreenContext?) {
        let turn = AskHistoryTurn(id: draft.id, thread: thread, question: question, answer: answer, images: draft.images,
                                  via: draft.via, searched: draft.searched ? true : nil)
        do {
            try AskHistoryStore.shared.append(turn, screenshot: screen.map { ($0.overviewJPEG, $0.closeUpJPEG) })
            draft.recorded = true
            NotificationCenter.default.post(name: .askFreeHistoryDidChange, object: nil)
        } catch {
            debugLog("ASK history write failed: \(error)")
        }
        saveHistoryThumbs(draft)
    }

    /// 图和回答谁先到不一定：回答没记下就先放着，记下了就补进那一轮
    private func recordHistoryImages(_ images: [AskImage], draft: AskHistoryDraft) {
        draft.images = images
        guard draft.recorded else { return }
        do {
            try AskHistoryStore.shared.setImages(images, turnID: draft.id)
        } catch {
            debugLog("ASK history images write failed: \(error)")
        }
        saveHistoryThumbs(draft)
    }

    /// 图的缩略图存一份到本机，存好了让历史页换成本机的
    private func saveHistoryThumbs(_ draft: AskHistoryDraft) {
        guard draft.recorded, !draft.images.isEmpty else { return }
        AskHistoryStore.shared.saveImageThumbs(draft.images, turnID: draft.id) {
            NotificationCenter.default.post(name: .askFreeHistoryDidChange, object: nil)
        }
    }

    /// 历史里记下是怎么问的，历史页按它筛
    private static func historyVia(trigger: String) -> String? {
        switch trigger {
        case "hotkey-screen", "onboarding": return "screen"
        case "hotkey-plain": return "plain"
        case "hotkey-type": return "type"
        case "follow-up": return "panel"
        default: return nil
        }
    }

    private func finishAsk() {
        isProcessing = false
        if overlayWindow.capsuleCenterOnScreen != nil { overlayWindow.hide() }
    }

    // MARK: - 指针问 AI

    /// 键盘快捷键提问开始：point 是 Quartz 全局坐标（原点左上），截图和画标记都用它。
    /// trigger：日志里的触发方式。captureScreen=false 是纯提问，不截屏。
    func beginAskAtCursor(at point: CGPoint, trigger: String, captureScreen: Bool) -> Bool {
        guard !isRecording, !isProcessing else {
            debugLog("AC: begin refused (recording=\(isRecording) processing=\(isProcessing))")
            return false
        }
        askTiming.reset(trigger: trigger, mode: "hotkey")
        typeAskPanel.dismiss()
        voiceQuestionFollowUp = false
        // 回答浮窗还在屏幕上（展开、小条、钉住都算）且话题还新鲜：接着聊。浮窗没了就是新话题
        askContinuesThread = answerPanel.canContinueThread
        // 键盘触发从第一帧就是带叉号和对勾的大胶囊：轻点锁定后手已经松开，要能点对勾结束
        overlayWindow.recordingControls = .cancelAndFinish
        guard startRecording() else {
            askContinuesThread = false
            debugLog("AC: startRecording refused")
            return false
        }
        if captureScreen {
            startAskScreenCapture(at: point)
        } else {
            pendingAskScreen?.cancel()
            pendingAskScreen = nil
            pendingAskScreenNote = nil
            askTiming.fallback = "plain"
        }
        // 用户说话那几秒里把 TLS 握手做掉，首字能早几百毫秒
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.askAI.warmUpConnection() }
        debugLog("AC: begin trigger=\(trigger) at \(Int(point.x)),\(Int(point.y)) continuesThread=\(askContinuesThread) \(answerPanel.stateSummary)")
        return true
    }

    /// 触发瞬间就截图，画标记、缩放、编码全在后台队列，和用户说话并行。
    /// 没权限 / 关了开关时不截，提问照常走纯文本，并把原因留给面板提示。
    func startAskScreenCapture(at point: CGPoint) {
        pendingAskScreen?.cancel()
        pendingAskScreen = nil
        pendingAskScreenNote = nil
        guard AskSettings.isScreenshotEnabled else {
            askTiming.fallback = "off"
            return
        }
        guard ScreenSnapshotCapturer.hasPermission else {
            askTiming.fallback = "noPermission"
            pendingAskScreenNote = ScreenSnapshotError.noPermission.userMessage
            // 开发版 -skipPermissionPrompts（无人值守实测）不弹授权框：权限要先在系统设置里给好
            if !didPromptForScreenCapture, !DevLaunchOptions.skipPermissionPrompts {
                didPromptForScreenCapture = true
                debugLog("AC: screen recording permission missing → prompting once")
                // 第一次调会弹系统授权框；之前拒过就直接返回 false，这时才帮用户打开系统设置
                MainActor.assumeIsolated { ScreenSnapshotCapturer.requestOrOpenSettings() }
            }
            return
        }
        pendingAskScreenNote = nil
        let pending = PendingAskScreen()
        pendingAskScreen = pending
        ScreenSnapshotCapturer.capture(at: point) { [weak self, weak pending] result in
            pending?.complete(result)
            switch result {
            case .success(let snapshot):
                self?.debugLog("AC: captured in \(snapshot.captureMs)+\(snapshot.encodeMs)ms (\(snapshot.sizeSummary))")
            case .failure(let error):
                self?.debugLog("AC: capture failed (\(error.debugName))")
            }
        }
    }

    /// 取图：好了就用，没好就等一会儿，等不到 / 失败就退回纯文本并把原因交给面板
    private func resolveAskScreen(_ callback: @escaping (AskAI.AskScreenContext?, String?) -> Void) {
        guard let pending = pendingAskScreen else {
            // 原因只用一次，免得下一问还挂着上一问的「没法看屏幕」
            let note = pendingAskScreenNote
            pendingAskScreenNote = nil
            callback(nil, note)
            return
        }
        pendingAskScreen = nil
        pending.onReady(timeout: 2.5) { [weak self] result in
            guard let self else { callback(nil, nil); return }
            switch result {
            case .success(let snapshot):
                self.askTiming.captureMs = snapshot.captureMs
                self.askTiming.encodeMs = snapshot.encodeMs
                self.askTiming.screenKB = (snapshot.overviewJPEG.count + snapshot.closeUpJPEG.count) / 1024
                callback(AskAI.AskScreenContext(overviewJPEG: snapshot.overviewJPEG,
                                                     closeUpJPEG: snapshot.closeUpJPEG), nil)
            case .failure(let error):
                self.askTiming.fallback = error.debugName
                callback(nil, error.userMessage)
            case nil:
                self.askTiming.fallback = "slowCapture"
                self.debugLog("AC: screenshot not ready in time → text only")
                callback(nil, "截屏没赶上，这次只按问题回答。")
            }
        }
    }
}

/// 正在问的这一轮要记进历史的东西。回答、截图用没用、找到的图分别从不同回调到，先攒在这里
private final class AskHistoryDraft {
    let id = UUID().uuidString
    var screenUsed = false
    var images: [AskImage] = []
    var recorded = false
    var via: String?
    var searched = false
}
