import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension AppDelegate {
    // MARK: - Recording Flow

    /// - Parameter feedback: 不能录（没配 Key、没麦克风权限）时要不要弹提示胶囊。
    ///   面板续聊传 false：在面板上按住不该冒出提示
    @discardableResult
    func startRecording(feedback: Bool = true) -> Bool {
        guard !isRecording else { return false }
        guard canStartRecording(showFeedback: feedback) else { return false }
        guard hasMicrophonePermission(showFeedback: feedback) else { return false }
        isRecording = true
        debugLog("START recording")

        pendingOverlayHide?.cancel()   // 取消上一轮错误浮窗的延时隐藏，避免误杀本次录音浮窗
        overlayWindow.askGlow = true
        // 面板上续聊：录音状态画在面板底栏里（音浪 + 识别中），不弹底部胶囊
        if !voiceQuestionFollowUp { overlayWindow.show(state: .recording) }

        let errorMsg = audioRecorder.startRecording { [weak self] level in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.voiceQuestionFollowUp { self.answerPanel.updateAudioLevel(level) } else { self.overlayWindow.updateAudioLevel(level) }
            }
        }

        if let errorMsg = errorMsg {
            isRecording = false
            showError("录音启动失败: \(errorMsg)")
            return false
        }
        return true
    }

    /// 叉号、Esc、面板上拖开：丢掉这段录音，不识别
    func cancelRecording() {
        debugLog("CANCEL recording called, isRecording=\(isRecording), isProcessing=\(isProcessing)")
        pendingAskScreen?.cancel()
        pendingAskScreen = nil
        pendingAskScreenNote = nil
        askContinuesThread = false
        let wasFollowUp = voiceQuestionFollowUp
        voiceQuestionFollowUp = false
        answerPanel.setRecording(false)
        guard isRecording else {
            debugLog("CANCEL ignored: not recording")
            return
        }
        pendingOverlayHide?.cancel()
        pendingOverlayHide = nil
        isRecording = false
        resetHotkeyGestures()
        isProcessing = false
        overlayWindow.hide()
        audioRecorder.stopRecording { _ in }
        if wasFollowUp { answerPanel.setListening(.cancelled) }
    }

    func showError(_ message: String) {
        pendingOverlayHide?.cancel()
        overlayWindow.show(state: .error(message: message))
        // 失败提示按文字长短停留 4~12 秒
        let seconds = min(12.0, max(4.0, Double(message.count) * 0.2))
        // 红色胶囊本身不画文字，只闪 0.7 秒表示"失败了"，随后换成可读的文字条说明原因。
        // 用 pendingOverlayHide 挂这个切换：期间若又开始录音会被取消，不会误把录音胶囊收掉。
        let work = DispatchWorkItem { [weak self] in
            self?.overlayWindow.showErrorHint(message, seconds: seconds)
        }
        pendingOverlayHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
}
