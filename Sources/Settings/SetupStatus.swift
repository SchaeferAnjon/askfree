// SetupStatus.swift
// Ask Free
//
// 「还差什么」只有一套：两个 Key、三项权限、看屏幕问的提问键。
// 欢迎引导的步骤、主窗口「开始」三步、侧栏的橙点和状态卡、菜单栏第一行都读这里，做完一处几处一起变。

import SwiftUI
import AVFoundation
import ApplicationServices
import Combine
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension Notification.Name {
    /// 语音与模型里存了 Key、换了服务商
    static let askFreeModelSettingsDidChange = Notification.Name("AskFreeModelSettingsDidChange")
}

@MainActor
final class SetupStatus: ObservableObject {
    static let shared = SetupStatus()

    @Published private(set) var mic: AVAuthorizationStatus = .notDetermined
    @Published private(set) var accessibility = false
    @Published private(set) var screenRecording = false
    /// 屏幕录制是启动后才打开的，这次运行还截不到：要重新打开 Ask Free
    @Published private(set) var screenNeedsRelaunch = false
    @Published private(set) var asrReady = false
    @Published private(set) var askReady = false
    @Published private(set) var screenHotkeySet = false
    /// 关了「让 AI 看屏幕」就用不到屏幕录制，不拿它算还差几步
    @Published private(set) var screenshotEnabled = true

    private var watchers = 0
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {
        refresh()
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, .askFreeAccessibilityGranted,
                     .askFreeHotkeyDidChange, .askFreeModelSettingsDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    // MARK: 分组（怎么算在 AskFreeCore 的 SetupChecklist，这里只读值）

    typealias Item = SetupItem

    var checklist: SetupChecklist {
        SetupChecklist(micAuthorized: mic == .authorized, accessibility: accessibility, screenRecording: screenRecording,
                       screenshotEnabled: screenshotEnabled, asrReady: asrReady, askReady: askReady,
                       screenHotkeySet: screenHotkeySet)
    }

    var micReady: Bool { mic == .authorized }
    var keysReady: Bool { checklist.keysReady }
    var permissionsReady: Bool { checklist.permissionsReady }
    var missingPermissions: Int { checklist.missingPermissions }
    func isDone(_ item: Item) -> Bool { checklist.isDone(item) }
    var missing: [Item] { checklist.missing }
    var allDone: Bool { checklist.allDone }

    /// 「火山引擎听，DeepSeek 答」
    var providerSummary: String {
        let asr = CloudASRTranscriber().currentVersion().provider == .bailian ? "阿里百炼" : "火山引擎"
        let ask: String
        switch AskFreeConfig.shared.string(forKey: "ask_provider") ?? "qwen" {
        case "deepseek": ask = "DeepSeek"
        case "doubao": ask = "豆包"
        default: ask = "通义千问"
        }
        return "\(asr)听，\(ask)答"
    }

    // MARK: 读

    func refresh() {
        let config = AskFreeConfig.shared
        set(\.mic, AVCaptureDevice.authorizationStatus(for: .audio))
        set(\.accessibility, AXIsProcessTrusted())
        set(\.screenRecording, ScreenSnapshotCapturer.hasPermission)
        set(\.screenNeedsRelaunch, ScreenSnapshotCapturer.needsRelaunch)
        set(\.asrReady, CloudASRTranscriber().isConfigured())
        set(\.askReady, AskAI().isConfigured())
        set(\.screenHotkeySet, AskHotkey.screen.current(in: config) != nil)
        set(\.screenshotEnabled, AskSettings.isScreenshotEnabled)
    }

    /// 窗口开着时每秒看一次：用户在系统设置里拖图标授权时，回到窗口前勾就已经打上了
    func beginWatching() {
        watchers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func endWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<SetupStatus, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    // MARK: 动作（授权）

    /// 麦克风：没问过就弹系统框；拒绝过只能去系统设置打开
    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { SetupStatus.shared.refresh() } }
            }
        default:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// 辅助功能：打开系统设置，右边浮出能拖的图标
    func requestAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        PermissionDragHelper.shared.show(for: .accessibility)
    }

    func requestScreenRecording() {
        ScreenSnapshotCapturer.requestOrOpenSettings()
    }
}

/// 欢迎引导走到哪了：走完或跳过记一笔，之后启动不再自动出现
enum OnboardingProgress {
    private static let doneKey = "onboardingCompleted"
    private static let stepKey = "onboardingStep"

    static var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: doneKey) }
        set { UserDefaults.standard.set(newValue, forKey: doneKey) }
    }

    /// 中途关掉时停在哪一步，「继续设置…」回到这里
    static var step: Int {
        get { UserDefaults.standard.integer(forKey: stepKey) }
        set { UserDefaults.standard.set(newValue, forKey: stepKey) }
    }
}
