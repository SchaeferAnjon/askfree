// AppUpdater.swift
// Ask Free
//
// 自动更新（Sparkle 2）：每 6 小时查一次 GitHub Release 里固定名的 appcast.xml（Info.plist 的 SUFeedURL），
// 有新版就在后台下载、核对 EdDSA 签名，下好后在「通用 → 更新」和菜单栏里给「重启更新」，点了才重启；
// 不点也行，下次退出时 Sparkle 自己装上。不弹 Sparkle 自带的窗口：状态写在设置那一行里（和 MeetCaption 一样）。
// 开发版不更新（feed 是正式版的）；开发版带 -updateFeedURL <地址> 启动时查那个地址，用来实测整条流程。

import AppKit
import Combine
import Sparkle
#if canImport(AskFreeCore)
import AskFreeCore
#endif

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var phase: UpdatePhase
    /// 「自动检查并下载新版本」：存在 Sparkle 自己的 UserDefaults 里（SUEnableAutomaticChecks / SUAutomaticallyUpdate）
    @Published private(set) var automaticallyChecks = true

    private var updater: SPUUpdater?
    /// 「重启更新」：Sparkle 给的立即安装（后台下好的是 immediateInstallationBlock，手动查的是 reply(.install)）
    private var installNow: (() -> Void)?
    /// 这一轮查到的新版本（后台查的从 didFindValidUpdate 来）；报错时据此分清是取 appcast 还是下安装包出的错
    private var foundVersion = ""
    private var expectedBytes: UInt64 = 0
    private var receivedBytes: UInt64 = 0

    /// 开发版不更新，除非带了 -updateFeedURL（实测用）
    var isSupported: Bool { !AppIdentity.isDevBuild || DevLaunchOptions.updateFeedURL != nil }

    var isInApplications: Bool {
        UpdateLocation.isInApplications(bundlePath: Bundle.main.bundlePath, home: NSHomeDirectory())
    }

    private override init() {
        phase = .off
        super.init()
    }

    /// 启动时调一次
    func start() {
        guard isSupported, updater == nil else { return }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            try updater.start()
        } catch {
            log("Update: Sparkle failed to start: \(Self.describe(error))")
            phase = .error(UpdateErrorText.message(for: error as NSError))
            return
        }
        self.updater = updater
        // 两个开关合成一个：查到了就下，不再问
        updater.automaticallyDownloadsUpdates = updater.automaticallyChecksForUpdates
        automaticallyChecks = updater.automaticallyChecksForUpdates
        phase = .idle
        log("Update: started, automatic=\(automaticallyChecks) feed=\(DevLaunchOptions.updateFeedURL == nil ? "default" : "override")")
    }

    func setAutomaticallyChecks(_ on: Bool) {
        guard let updater else { return }
        // 自动查关着时 Sparkle 不让改「自动下载」：开的时候先开查，关的时候先关下载，两个存下来的值才跟开关一致
        if on {
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
        } else {
            updater.automaticallyDownloadsUpdates = false
            updater.automaticallyChecksForUpdates = false
        }
        automaticallyChecks = updater.automaticallyChecksForUpdates
        log("Update: automatic checks \(on ? "on" : "off")")
    }

    /// 「检查更新」
    func checkNow() {
        guard let updater, phase.canCheck else { return }
        foundVersion = ""
        phase = .checking
        updater.checkForUpdates()
    }

    /// 「重启更新」
    func installAndRelaunch() {
        guard let installNow else { return }
        log("Update: install and relaunch \(phase.readyVersion ?? "?")")
        installNow()
    }

    private func log(_ message: String) {
        (NSApp.delegate as? AppDelegate)?.debugLog(message)
    }

    /// 日志里记错误一层层的来路（domain/code），不记地址
    private static func describe(_ error: Error) -> String {
        var chain: [String] = []
        var next: NSError? = error as NSError
        while let ns = next, chain.count < 5 {
            // HTTP 状态码要留（看得出是 404 还是 500），地址不记
            let status = UpdateErrorText.httpStatus(ns).map { " http=\($0)" } ?? ""
            chain.append("\(ns.domain)/\(ns.code)\(status)")
            next = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain.joined(separator: " <- ")
    }

    private func errorText(_ error: Error) -> String {
        UpdateErrorText.message(for: error as NSError, foundVersion: foundVersion.isEmpty ? nil : foundVersion)
    }

    private func setReady(version: String, install: @escaping () -> Void) {
        installNow = install
        phase = .ready(version: version)
        log("Update: \(version) ready to install")
    }
}

// MARK: - Sparkle 的界面回调：不开窗，只换 phase

extension AppUpdater: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist 写了 SUEnableAutomaticChecks，正常不会问；万一问了，按默认打开、不发系统信息
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        foundVersion = appcastItem.displayVersionString
        log("Update: found \(foundVersion) stage=\(state.stage.rawValue) userInitiated=\(state.userInitiated)")
        if appcastItem.isInformationOnlyUpdate {
            reply(.dismiss)
            phase = .error("新版本 \(foundVersion) 要到官网下载安装")
            return
        }
        switch state.stage {
        case .installing:
            // 已经在等着装了：这时回 .install 会马上重启，留给「重启更新」
            setReady(version: foundVersion) { reply(.install) }
        default:
            // 没下（或下好了还没解包）：接着下、解包，好了走 showReady
            expectedBytes = 0
            receivedBytes = 0
            phase = .downloading(version: foundVersion, percent: nil)
            reply(.install)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        phase = .latest(checkedAt: Date())
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        log("Update: error \(Self.describe(error))")
        phase = .error(errorText(error))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        phase = .downloading(version: foundVersion, percent: nil)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
        receivedBytes = 0
        phase = .downloading(version: foundVersion, percent: UpdatePhase.percent(received: 0, expected: expectedBytes))
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedBytes += length
        let percent = UpdatePhase.percent(received: receivedBytes, expected: expectedBytes)
        if phase != .downloading(version: foundVersion, percent: percent) {
            phase = .downloading(version: foundVersion, percent: percent)
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        phase = .preparing(version: foundVersion)
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        setReady(version: foundVersion) { reply(.install) }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        // 一轮结束：查到一半、下到一半被打断的回到空闲；「已是最新」「出错」「下好了」留着给人看
        switch phase {
        case .checking, .downloading, .preparing: phase = .idle
        default: break
        }
    }
}

// MARK: - Sparkle 的流程回调

extension AppUpdater: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        DevLaunchOptions.updateFeedURL
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundVersion = item.displayVersionString
    }

    /// 后台查到、后台下好了：接管安装时机，给「重启更新」；不点就等退出时装
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        setReady(version: item.displayVersionString, install: immediateInstallHandler)
        return true
    }

    /// 后台查的结果也写进那一行（后台查不走上面的界面回调）
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        defer { if phase.readyVersion == nil { foundVersion = "" } }
        guard let error else { return }
        let ns = error as NSError
        if ns.domain == UpdateErrorText.sparkleDomain && ns.code == Int(SUError.noUpdateError.rawValue) {
            if case .ready = phase { return }
            phase = .latest(checkedAt: Date())
            return
        }
        log("Update: cycle ended with \(Self.describe(error))")
        switch phase {
        case .ready, .error: break
        default: phase = .error(errorText(ns))
        }
    }
}
