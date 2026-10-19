import Cocoa
import AVFoundation
import ApplicationServices
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension Notification.Name {
    static let askFreeAccessibilityGranted = Notification.Name("AskFreeAccessibilityGranted")
}

extension AppDelegate {
    func requestMicrophonePermissionIfUndetermined() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    /// 录音前看麦克风权限：拒绝过时引擎照样能开，但只录到静音，最后什么都不发生，用户不知道为什么。
    /// 没决定过就弹系统授权框，这一次先不录；拒绝过就说清楚并打开系统设置里的麦克风页。
    func hasMicrophonePermission(showFeedback: Bool) -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return false
        case .denied, .restricted:
            debugLog("Microphone permission denied; recording refused")
            if showFeedback {
                overlayWindow.showHint("麦克风权限未开启 · 请在「系统设置 → 隐私与安全性 → 麦克风」里打开 Ask Free")
                openMicrophoneSettings()
            }
            return false
        @unknown default:
            return true
        }
    }

    /// 语音识别和问答模型都要有 Key 才能问
    func canStartRecording(showFeedback: Bool) -> Bool {
        if isProcessing { return false }
        guard cloudTranscriber.isConfigured(), askAI.isConfigured() else {
            if showFeedback {
                overlayWindow.showHint("请先在「模型」页填入语音识别和问答模型的 API Key")
                showModelSettings()
            }
            return false
        }
        return true
    }

    func updateAccessibilityDependentFeatures() {
        let hasAccessibility = AXIsProcessTrusted()
        debugLog("Accessibility trusted=\(hasAccessibility)")

        guard hasAccessibility else {
            askHotkeyManagers.forEach { $0.stop() }
            askHotkeyManagers = []
            startAccessibilityWatcher()
            if !didPromptForAccessibility {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                didPromptForAccessibility = true
            }
            if !didReportMissingAccessibility {
                debugLog("Accessibility not granted yet; skipping global hotkey listener")
                showError("请授予辅助功能权限以启用快捷键")
                didReportMissingAccessibility = true
            }
            return
        }

        didPromptForAccessibility = false
        didReportMissingAccessibility = false
        ensureAskHotkeyManagers()
    }

    /// 辅助功能未授权时每 2 秒检测一次；用户在系统设置里一打开就立刻接管快捷键，
    /// 不用重启 App（事件监听是授权后新建的，能直接生效）。
    private func startAccessibilityWatcher() {
        guard axPollTimer == nil else { return }
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, AXIsProcessTrusted() else { return }
            self.axPollTimer?.invalidate()
            self.axPollTimer = nil
            self.debugLog("Accessibility granted while running; enabling hotkey without restart")
            self.updateAccessibilityDependentFeatures()
            NotificationCenter.default.post(name: .askFreeAccessibilityGranted, object: nil)
            self.overlayWindow.showHint("辅助功能已开启，现在可以用快捷键提问了", accent: .success)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
