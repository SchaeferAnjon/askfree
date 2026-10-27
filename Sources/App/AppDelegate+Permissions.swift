import Cocoa
import AVFoundation
import ApplicationServices
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension Notification.Name {
    static let askFreeAccessibilityGranted = Notification.Name("AskFreeAccessibilityGranted")
}

/// 重新打开自己：屏幕录制在启动后才打开时，要换一个新进程截屏才生效。
/// 起一个小 shell 等这个进程退出（最多 10 秒），再 `open -n` 拉起同一个 App，然后自己退出。
enum AppRelaunch {
    static func relaunch() {
        let app = NSApp.delegate as? AppDelegate
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "i=0; while /bin/kill -0 \"$0\" 2>/dev/null && [ $i -lt 100 ]; do /bin/sleep 0.1; i=$((i+1)); done; /usr/bin/open -n \"$1\"",
                          String(pid), Bundle.main.bundleURL.path]
        do {
            try task.run()
        } catch {
            app?.debugLog("Relaunch failed to start helper: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "没能重新打开 Ask Free"
            alert.informativeText = "请从菜单栏图标里点「退出 Ask Free」，再从「应用程序」里打开它。"
            alert.runModal()
            return
        }
        app?.debugLog("Relaunching to pick up screen recording permission")
        NSApp.terminate(nil)
    }
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
            stopAskHotkeys()
            startAccessibilityWatcher()
            if !didPromptForAccessibility {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                // 用户在系统授权框上点「打开系统设置」后，旁边浮出能拖的图标
                MainActor.assumeIsolated { PermissionDragHelper.shared.show(for: .accessibility) }
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
        MainActor.assumeIsolated { PermissionDragHelper.shared.show(for: .accessibility) }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
