import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension AppDelegate {
    func resetHotkeyGestures() {
        askHotkeyManagers.forEach { $0.recordingDidLeaveActiveState() }
    }

    // MARK: - 问 AI 的键盘快捷键

    /// 两套：看屏幕问（按下那一刻鼠标指在哪，截图上的标记就在哪）和纯提问（不截屏）。
    /// 手势：按住说、松开结束；轻点一下锁定、再点一下结束；按住期间 Esc 取消。
    func ensureAskHotkeyManagers() {
        guard askHotkeyManagers.isEmpty else { return }
        for (hotkey, captureScreen) in [(AskHotkey.screen, true), (AskHotkey.plain, false)] {
            let manager = HotkeyManager(
                profile: .ask(hotkey),
                onStart: { [weak self] in
                    guard let self else { return false }
                    // 鼠标此刻的位置（Quartz 全局坐标，原点左上），截图标记画在这里
                    let point = CGEvent(source: nil)?.location ?? .zero
                    return self.beginAskAtCursor(at: point, trigger: captureScreen ? "hotkey-screen" : "hotkey-plain",
                                                 captureScreen: captureScreen)
                },
                onStop: { [weak self] in
                    guard let self, self.isRecording else { return }
                    self.stopRecordingAndAsk()
                },
                isRecording: { [weak self] in self?.isRecording == true }
            )
            manager.debugLog = { [weak self] msg in self?.debugLog("AK[\(hotkey.prefix)]: \(msg)") }
            manager.onGestureClassified = { _ in }
            manager.onCancel = { [weak self] in self?.cancelRecording() }
            askHotkeyManagers.append(manager)
            debugLog("AK[\(hotkey.prefix)]: shortcut=\(hotkey.displayName) active=\(hotkey.isActive)\(hotkey.conflict.map { " conflict=\($0)" } ?? "")")
        }
    }

    /// 回答面板：在面板上按住说话就是接着这个话题追问
    func setupAnswerPanel() {
        AnswerPanel.log = { [weak self] in self?.debugLog($0) }
        answerPanel.onFollowUpStart = { [weak self] in
            // 上一轮还在出字时接不上话：等它答完再按住续聊
            guard let self, !self.isRecording, !self.isProcessing, !self.askInFlight else { return false }
            self.voiceQuestionFollowUp = true
            self.overlayWindow.recordingControls = .hidden
            guard self.startRecording(feedback: false) else { self.voiceQuestionFollowUp = false; return false }
            // 在面板上续聊：屏幕上此刻就是那张面板，没必要再截一次
            self.pendingAskScreen?.cancel()
            self.pendingAskScreen = nil
            self.pendingAskScreenNote = nil
            self.askTiming.reset(trigger: "follow-up", mode: "panel")
            self.answerPanel.setRecording(true)
            return true
        }
        answerPanel.onFollowUpEnd = { [weak self] cancelled in
            guard let self else { return }
            self.answerPanel.setRecording(false)
            if cancelled { self.cancelRecording() } else { self.stopRecordingAndAsk() }
        }
    }
}
