import Cocoa
import AVFoundation
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 集中管理外部链接，换地址只改这里。
enum AppLinks {
    /// 开源代码仓库
    static let sourceCodeURL = "https://github.com/SchaeferAnjon/askfree"
}

/// 启动参数（scripts/dev_run.sh 透传）：
/// - `-openPage <start|history|hotkeys|models|answer|recording|permissions|general|about|onboarding>`：
///   启动后打开主窗口并切到该页（onboarding 打开欢迎引导），正式版也认
/// - `-skipPermissionPrompts`：不弹系统授权框，只在开发版（Ask Free Dev）生效
/// - `-askText <问题>`：启动 3 秒后在指针处截屏并问这句话，走的是看屏幕问 AI 的整条流程、只跳过说话，只在开发版生效
enum DevLaunchOptions {
    private static let arguments = ProcessInfo.processInfo.arguments

    static let openPageArgument: String? = {
        guard let i = arguments.firstIndex(of: "-openPage"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1].lowercased()
    }()

    static let openPage: MainPage? = openPageArgument.flatMap { MainPage(argument: $0) }

    static let openOnboarding: Bool = openPageArgument == "onboarding"

    static let skipPermissionPrompts: Bool = AppIdentity.isDevBuild && arguments.contains("-skipPermissionPrompts")

    static let askText: String? = {
        guard AppIdentity.isDevBuild, let i = arguments.firstIndex(of: "-askText"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }()
}

extension Bundle {
    /// 展示用版本号（CFBundleShortVersionString），取不到时为空串。
    var appVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var overlayWindow: OverlayWindow!
    var audioRecorder: AudioRecorder!
    var cloudTranscriber: CloudASRTranscriber!
    var askAI: AskAI!
    /// 问 AI 的两套键盘快捷键：看屏幕问、纯提问
    var askHotkeyManagers: [HotkeyManager] = []
    /// 在回答面板上按住发起的续聊（带本话题上下文，追加在面板里）
    var voiceQuestionFollowUp = false
    /// 快捷键提问时回答浮窗还在屏幕上：这一问接着当前话题（带历史），而不是另起一个。
    /// 和 voiceQuestionFollowUp 的区别：那个是「按住浮窗说话」，录音状态画在浮窗里、不出胶囊。
    var askContinuesThread = false
    /// 这一轮提问附带的屏幕内容。触发瞬间就开始截，和用户说话并行：
    /// 等语音识别出文字时图早已就绪，截图对总耗时的贡献基本是 0
    var pendingAskScreen: PendingAskScreen?
    /// 这一轮提问的分段耗时，收尾时写一行日志，回头看就知道慢在哪
    var askTiming = AskTiming()
    /// 这次没能带屏幕内容的原因（要显示在回答面板里，不能静默）
    var pendingAskScreenNote: String?
    /// 屏幕录制权限只引导一次，别每次触发都弹
    var didPromptForScreenCapture = false
    /// 首字迟迟不来时在面板里提示「网络较慢」，不让用户干等
    var askSlowHintWork: DispatchWorkItem?
    /// 第几轮提问：回答在面板里流式出字时录音不再被占住，旧回答的回调按这个编号丢掉，不写进新一轮。
    /// 面板开始显示新一轮（startThread / appendQuestion）时加一
    var askRound = 0
    /// 有一轮回答还在路上。这期间新提问一律另起话题，面板上按住续聊先不接（上一轮还没答完，接不上）
    var askInFlight = false
    /// 最近一问发出去的屏幕内容：报错卡「重试」时照原样再发
    var lastAskScreen: AskAI.AskScreenContext?
    let answerPanel = AnswerPanel()
    /// 打字问 AI：双击修饰键弹出的输入框和它的监听
    let typeAskPanel = TypeAskPanel()
    var typeAskMonitor: DoubleTapMonitor?

    var isRecording = false
    var isProcessing = false
    let debugLogQueue = DispatchQueue(label: "io.github.schaeferanjon.askfree.debug-log", qos: .utility)
    let debugLogMaxBytes: UInt64 = 2 * 1024 * 1024
    var didReportMissingAccessibility = false
    var didPromptForAccessibility = false
    var axPollTimer: Timer?  // 辅助功能未授权时轮询，授权后立即接管快捷键（无需重启）
    var pendingOverlayHide: DispatchWorkItem?  // 防止上一次错误的延时隐藏误杀新录音浮窗

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 用户关了「在 Dock 中显示」：在 Dock 图标出现前就切走，免得启动时闪一下
        DockIcon.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("App launched")

        // 启动早期：把明文 config 残留的 API key 收敛进钥匙串（幂等、fail-closed）。
        AskFreeConfig.shared.reconcileSecrets()

        // 首次启动默认开启「开机自启动」：只自动登记这一次，之后完全尊重用户的选择。
        LaunchAtLogin.applyDefaultIfFirstLaunch()

        // 锁定浅色外观：主窗口的深浅由「设置 → 外观」单独控制，浮窗、面板等一律浅色。
        NSApp.appearance = NSAppearance(named: .aqua)

        // 补一个标准主菜单：没有它，Cmd+C/V/X/A 等编辑快捷键无法分发到输入框
        setupMainMenu()

        // 第一次打开先出欢迎引导：权限在引导第二步由用户点按钮时再申请，先说清为什么。
        // 已经都配好的老用户直接记成看过引导
        if !OnboardingProgress.isCompleted && SetupStatus.shared.allDone { OnboardingProgress.isCompleted = true }
        let showsOnboarding = DevLaunchOptions.openOnboarding || !OnboardingProgress.isCompleted

        // 看过引导之后：启动就把要用的系统权限都申请掉，别等第一次提问才弹。系统只在第一次真的弹框，之后调用无声返回。
        // 开发版带 -skipPermissionPrompts 启动：不弹任何系统授权框，方便无人值守实测
        if DevLaunchOptions.skipPermissionPrompts || showsOnboarding {
            debugLog(showsOnboarding ? "Onboarding: permission prompts wait for the user" : "Dev launch: skipping permission prompts")
            didPromptForAccessibility = true
            didReportMissingAccessibility = true
        } else {
            requestMicrophonePermissionIfUndetermined()
            if AskSettings.isScreenshotEnabled, !ScreenSnapshotCapturer.hasPermission {
                ScreenSnapshotCapturer.requestPermission()
                // 用户在系统授权框上点「打开系统设置」后，旁边浮出能拖的图标；辅助功能也缺时稍后换成它的
                PermissionDragHelper.shared.show(for: .screenRecording)
            }
        }

        statusBar = StatusBarController(delegate: self)
        overlayWindow = OverlayWindow()
        overlayWindow.onCancelRecording = { [weak self] in self?.cancelRecording() }
        overlayWindow.onFinishRecording = { [weak self] in self?.stopRecordingAndAsk() }
        audioRecorder = AudioRecorder()
        audioRecorder.prepare()  // 只注册设备变更监听；引擎录音时才建，空闲不占系统音频设备
        cloudTranscriber = CloudASRTranscriber()
        cloudTranscriber.debugLog = { [weak self] message in
            self?.debugLog(message)
        }
        askAI = AskAI()
        askAI.debugLog = { [weak self] message in
            self?.debugLog(message)
        }
        setupAnswerPanel()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        // 启动末尾主动调一次，注册快捷键
        updateAccessibilityDependentFeatures()

        // 第一次打开出欢迎引导；看过引导但还没填 Key：打开主窗口的「开始」，不填用不了
        if showsOnboarding {
            debugLog("Launch: showing onboarding at step \(OnboardingProgress.step)")
            OnboardingWindowController.show()
        } else if let page = DevLaunchOptions.openPage {
            debugLog("Launch argument: opening page \(page)")
            SettingsWindowController.show(page: page)
        } else if !cloudTranscriber.isConfigured() || !askAI.isConfigured() {
            SettingsWindowController.show(page: .start)
        }
        if let question = DevLaunchOptions.askText {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.devAsk(question) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        stopAskHotkeys()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 在访达 / 启动台再次打开时，系统会把 App 改回普通前台 App（Dock 图标又出来）；用户关了就再切回去
        DockIcon.apply()
        DispatchQueue.main.async { DockIcon.apply() }
        if !flag {
            showSettingsCenter()
        }
        return true
    }

    @objc private func handleAppDidBecomeActive() {
        updateAccessibilityDependentFeatures()
    }
}
