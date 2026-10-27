import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 两个不用人看着的启动方式（参数说明见 DevLaunchOptions）：
/// - `-selfTest`：CI 在正式包上跑，九页和欢迎引导都打开一遍，菜单栏图标、主窗口、引导都出来了就退出（退出码 0），少一样退出码 1
/// - `-snapshotPages <目录>`：开发版把主窗口九页、欢迎引导六步各画成一张 PNG，改坏了界面一眼能看出来。
///   和自测一样用空的临时配置（没填 Key、没有历史），画出来的是「刚装好」的样子，不带你的历史和截图
extension AppDelegate {
    /// 启动自测开始前这个 App 偏好里的东西：AppKit 会自己往里写菜单栏图标的位置、主窗口的位置，退出前原样放回去，
    /// 在装着正式版的 Mac 上跑自测也不改它的偏好（applicationWillFinishLaunching 里、建菜单栏图标之前记下）
    static var defaultsBeforeSelfTest: [String: Any]?

    static func rememberDefaultsForSelfTest() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        defaultsBeforeSelfTest = UserDefaults.standard.persistentDomain(forName: id) ?? [:]
    }

    private static func restoreDefaultsAfterSelfTest() {
        guard let id = Bundle.main.bundleIdentifier, let saved = defaultsBeforeSelfTest else { return }
        if saved.isEmpty {
            UserDefaults.standard.removePersistentDomain(forName: id)
        } else {
            UserDefaults.standard.setPersistentDomain(saved, forName: id)
        }
        UserDefaults.standard.synchronize()
    }

    func runSelfTest() {
        // 卡住不能让 CI 一直等
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            Self.finishSelfTest(failures: ["60 秒内没走完"])
        }
        Task { @MainActor in
            for page in MainPage.allCases {
                SettingsWindowController.show(page: page)
                try? await Task.sleep(for: .milliseconds(400))
            }
            let mainWindow = SettingsWindowController.shared?.window
            OnboardingWindowController.show()
            try? await Task.sleep(for: .milliseconds(600))

            var failures: [String] = []
            if statusBar?.isShowing != true { failures.append("菜单栏图标没出来") }
            if mainWindow?.isVisible != true || (mainWindow?.contentView?.subviews.isEmpty ?? true) { failures.append("主窗口没出来") }
            if OnboardingWindowController.shared?.window?.isVisible != true { failures.append("欢迎引导没出来") }
            // 不关窗口直接退：关引导会记成「看过引导」
            Self.finishSelfTest(failures: failures)
        }
    }

    private static func finishSelfTest(failures: [String]) {
        let info = Bundle.main.appVersionInfo
        if failures.isEmpty {
            print("Ask Free self-test ok: \(info.version) (\(info.build)), 菜单栏图标、主窗口 \(MainPage.allCases.count) 页、欢迎引导都出来了")
            removeTemporaryData()
        } else {
            print("Ask Free self-test FAILED: \(info.version) (\(info.build)): \(failures.joined(separator: "；"))")
            print("日志：\(AppIdentity.debugLogFileURL.path)")
        }
        restoreDefaultsAfterSelfTest()
        exit(failures.isEmpty ? 0 : 1)
    }

    /// 自测和画页面用的临时配置目录：等日志写完再删
    private static func removeTemporaryData() {
        (NSApp.delegate as? AppDelegate)?.debugLogQueue.sync {}
        // 删不掉也只是系统临时目录里留个小文件夹，不影响结果
        try? FileManager.default.removeItem(at: AppIdentity.temporaryDataDirectory)
    }

    func runPageSnapshots(into directory: URL) {
        // 引导每次打开都停在 OnboardingProgress.step，关窗口会记成「看过引导」：画完（或画失败）把原来的进度放回去。
        // 不用 defer：NSApp.terminate、exit 当场退出，defer 来不及跑
        let savedStep = OnboardingProgress.step
        let savedDone = OnboardingProgress.isCompleted
        @MainActor func restoreOnboarding() {
            OnboardingWindowController.shared?.close()
            OnboardingProgress.step = savedStep
            OnboardingProgress.isCompleted = savedDone
        }
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var written: [String] = []
                for (i, page) in MainPage.allCases.enumerated() {
                    SettingsWindowController.show(page: page)
                    try await Task.sleep(for: .milliseconds(900))
                    guard let window = SettingsWindowController.shared?.window else { throw SnapshotError.noWindow("主窗口") }
                    written.append(try Self.writePNG(of: window, to: directory, name: "main-\(i + 1)-\(page.rawValue)"))
                }
                SettingsWindowController.shared?.close()
                for step in 0..<6 {
                    OnboardingWindowController.shared?.close()
                    OnboardingProgress.step = step
                    OnboardingWindowController.show()
                    try await Task.sleep(for: .milliseconds(900))
                    guard let window = OnboardingWindowController.shared?.window else { throw SnapshotError.noWindow("欢迎引导") }
                    written.append(try Self.writePNG(of: window, to: directory, name: "onboarding-\(step + 1)"))
                }
                restoreOnboarding()
                print("Wrote \(written.count) PNGs to \(directory.path)")
                Self.removeTemporaryData()
                NSApp.terminate(nil)
            } catch {
                restoreOnboarding()
                debugLog("Snapshot failed: \(error)")
                print("Snapshot failed: \(error)")
                exit(1)
            }
        }
    }

    private enum SnapshotError: Error {
        case noWindow(String)
        case render(String)
    }

    /// 只画这个窗口自己（标题栏和红绿灯在内），不截屏、不用屏幕录制权限
    private static func writePNG(of window: NSWindow, to directory: URL, name: String) throws -> String {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw SnapshotError.render(name) }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.render(name) }
        let url = directory.appendingPathComponent(name + ".png")
        try png.write(to: url, options: .atomic)
        return url.lastPathComponent
    }
}
