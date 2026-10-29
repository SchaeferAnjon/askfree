import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension AppDelegate {
    // MARK: - 打字问 AI

    /// 双击：输入框没开就截屏开一个，开着就收起
    func toggleTypeAsk() {
        if typeAskPanel.isVisible {
            debugLog("TA: double tap → close")
            typeAskPanel.dismiss()
            dropPendingAskScreen()
        } else {
            beginTypeAsk()
        }
    }

    /// 双击那一刻截屏（指针在哪标记就画在哪，自己的窗口不进截图），然后弹输入框；回车提问，回答照旧进面板。
    /// 回答面板还在、话题还新鲜：这一问是追问
    private func beginTypeAsk() {
        guard !isRecording, !isProcessing else {
            debugLog("TA: begin refused (recording=\(isRecording) processing=\(isProcessing))")
            return
        }
        guard askAI.isConfigured() else {
            if UsageModeStore.isMember {
                overlayWindow.showHint(MemberAPIError.noServer.message)
            } else {
                overlayWindow.showHint("请先在「模型」页填入问答模型的 API Key")
                showModelSettings()
            }
            return
        }
        if MainActor.assumeIsolated({ blockedByMembership() }) { return }
        let point = CGEvent(source: nil)?.location ?? .zero
        askTiming.reset(trigger: "hotkey-type", mode: "type")
        startAskScreenCapture(at: point)
        let continuesThread = answerPanel.canContinueThread
        typeAskPanel.onSubmit = { [weak self] text in
            self?.submitQuestion(text, continuesThread: continuesThread)
        }
        typeAskPanel.onCancel = { [weak self] in
            self?.debugLog("TA: cancelled")
            self?.dropPendingAskScreen()
        }
        let placeholder = continuesThread ? "接着问…" : (AskSettings.isScreenshotEnabled ? "问点什么，AI 会看着屏幕回答" : "问点什么")
        typeAskPanel.show(placeholder: placeholder, below: answerPanel.isVisible ? answerPanel.frame : nil)
        // 打字那几秒里把 TLS 握手做掉
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.askAI.warmUpConnection() }
        debugLog("TA: begin at \(Int(point.x)),\(Int(point.y)) continuesThread=\(continuesThread) \(answerPanel.stateSummary)")
    }

    private func dropPendingAskScreen() {
        pendingAskScreen?.cancel()
        pendingAskScreen = nil
        pendingAskScreenNote = nil
    }
}
