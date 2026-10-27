import XCTest
@testable import AskFreeCore

final class SetupChecklistTests: XCTestCase {
    private let allSet = SetupChecklist(micAuthorized: true, accessibility: true, screenRecording: true,
                                        screenshotEnabled: true, asrReady: true, askReady: true, screenHotkeySet: true)

    func testFreshInstallMissesAllThreeInSetupOrder() {
        let fresh = SetupChecklist()
        XCTAssertEqual(fresh.missing, [.permissions, .keys, .hotkey], "先授权、再填 Key、再选提问键")
        XCTAssertEqual(fresh.current, .permissions)
        XCTAssertEqual(fresh.missingPermissions, 3)
        XCTAssertEqual(fresh.statusTitle, "还差 3 步")
        XCTAssertEqual(fresh.missingSummary, "允许权限、填 Key、选提问键")
        XCTAssertFalse(fresh.allDone)
    }

    func testAllDone() {
        XCTAssertTrue(allSet.allDone)
        XCTAssertNil(allSet.current)
        XCTAssertEqual(allSet.statusTitle, "一切就绪")
        XCTAssertEqual(allSet.menuDetail(screenHotkeyTitle: "右 ⌥"), "按住 右 ⌥ 看着屏幕问")
        for page in MainPage.allCases {
            XCTAssertFalse(allSet.needsAttention(page), "\(page) 不该挂橙点")
        }
    }

    func testScreenRecordingNotNeededWhenScreenshotsOff() {
        var c = allSet
        c.screenRecording = false
        XCTAssertFalse(c.permissionsReady)
        XCTAssertEqual(c.missingPermissions, 1)
        c.screenshotEnabled = false
        XCTAssertTrue(c.permissionsReady, "关了「让 AI 看屏幕」就不要屏幕录制")
        XCTAssertEqual(c.missingPermissions, 0)
        XCTAssertTrue(c.allDone)
    }

    func testBothKeysNeeded() {
        var c = allSet
        c.askReady = false
        XCTAssertEqual(c.missing, [.keys])
        c.askReady = true
        c.asrReady = false
        XCTAssertEqual(c.missing, [.keys])
        XCTAssertEqual(c.menuDetail(screenHotkeyTitle: "右 ⌥"), "还差 1 项：填 Key")
    }

    func testCurrentStepFollowsSetupOrder() {
        var c = allSet
        c.screenHotkeySet = false
        c.askReady = false
        XCTAssertEqual(c.current, .keys, "Key 排在提问键前面")
        c.accessibility = false
        XCTAssertEqual(c.current, .permissions)
        XCTAssertEqual(c.statusTitle, "还差 3 步")
    }

    func testSidebarDots() {
        var c = allSet
        c.screenHotkeySet = false
        XCTAssertEqual(MainPage.allCases.filter(c.needsAttention), [.start, .hotkeys])
        c = allSet
        c.asrReady = false
        XCTAssertEqual(MainPage.allCases.filter(c.needsAttention), [.start, .models])
        c = allSet
        c.micAuthorized = false
        XCTAssertEqual(MainPage.allCases.filter(c.needsAttention), [.start, .permissions])
        XCTAssertEqual(MainPage.allCases.filter(SetupChecklist().needsAttention), [.start, .hotkeys, .models, .permissions])
    }
}

final class MainPageTests: XCTestCase {
    func testArgumentNames() {
        XCTAssertEqual(MainPage(argument: "home"), .start)
        XCTAssertEqual(MainPage(argument: "start"), .start)
        XCTAssertEqual(MainPage(argument: "model"), .models)
        XCTAssertEqual(MainPage(argument: "MODELS"), .models)
        XCTAssertEqual(MainPage(argument: "settings"), .general)
        for page in MainPage.allCases {
            XCTAssertEqual(MainPage(argument: page.rawValue), page)
        }
        XCTAssertNil(MainPage(argument: "onboarding"), "onboarding 打开的是引导窗，不是主窗口的一页")
        XCTAssertNil(MainPage(argument: ""))
    }

    func testSidebarOrderAndMenuKeys() {
        XCTAssertEqual(MainPage.allCases.map(\.title),
                       ["开始", "历史", "快捷键", "语音与模型", "回答方式", "录音", "权限", "通用", "关于"])
        XCTAssertEqual(MainPage.allCases.map(\.menuKeyEquivalent), (1...9).map(String.init))
        XCTAssertEqual(MainPage.settings, Array(MainPage.allCases.dropFirst(2)))
    }

    func testArrowKeysStopAtEnds() {
        XCTAssertEqual(MainPage.start.stepped(by: -1), .start)
        XCTAssertEqual(MainPage.start.stepped(by: 1), .history)
        XCTAssertEqual(MainPage.about.stepped(by: 1), .about)
        XCTAssertEqual(MainPage.general.stepped(by: 1), .about)
        XCTAssertEqual(MainPage.history.stepped(by: -1), .start)
    }

    func testStartBecomesHome() {
        XCTAssertEqual(MainPage.start.title(setupDone: false), "开始")
        XCTAssertEqual(MainPage.start.title(setupDone: true), "首页")
        XCTAssertEqual(MainPage.start.symbol(setupDone: true), "house")
        XCTAssertEqual(MainPage.history.title(setupDone: true), "历史")
        XCTAssertEqual(MainPage.history.symbol(setupDone: true), "clock")
    }
}

final class AskFailureTests: XCTestCase {
    private struct Described: LocalizedError {
        let errorDescription: String?
    }

    func testKnownErrors() {
        XCTAssertEqual(AskFailure(error: AskAI.AskError.noAPIKey), .noKey)
        XCTAssertEqual(AskFailure(error: AskAI.AskError.quotaExhausted("403")), .quota)
        XCTAssertEqual(AskFailure(error: URLError(.timedOut)), .timeout)
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed] {
            XCTAssertEqual(AskFailure(error: URLError(code)), .offline, "\(code)")
        }
    }

    func testProviderMessagesTranslatedByAskAI() {
        // 服务商原话 → AskAI 翻成人话 → 报错卡认出是哪一类
        let invalid = AskAI.friendlyProviderError(code: "invalid_api_key", type: nil, message: "Incorrect API key provided")
        XCTAssertEqual(AskFailure(error: AskAI.AskError.apiError(invalid!)), .invalidKey)
        let deepseek401 = AskAI.friendlyProviderError(code: nil, type: nil, message: "Authentication Fails (no such user)")
        XCTAssertEqual(AskFailure(error: AskAI.AskError.apiError(deepseek401!)), .invalidKey)
        let overdue = AskAI.friendlyProviderError(code: "Arrearage", type: nil, message: "account is not in good standing")
        XCTAssertEqual(AskFailure(error: AskAI.AskError.apiError(overdue!)), .quota)
    }

    func testUnknownErrorKeepsReason() {
        XCTAssertEqual(AskFailure(error: Described(errorDescription: "模型服务 500")), .other("模型服务 500"))
        // URLSession 给的 URLError 带系统写好的说明，原样给
        let badResponse = URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "服务器响应有误。"])
        XCTAssertEqual(AskFailure(error: badResponse), .other("服务器响应有误。"))
        let throttled = AskFailure(error: AskAI.AskError.apiError("请求太频繁或额度超限，稍后再试（Throttling）"))
        XCTAssertEqual(throttled, .other("请求太频繁或额度超限，稍后再试（Throttling）"))
    }

    func testCardTextAndButtons() {
        XCTAssertEqual(AskFailure.invalidKey.title(provider: "DeepSeek"), "DeepSeek 不认这个 Key")
        XCTAssertEqual(AskFailure.timeout.title(provider: "通义千问"), "通义千问 没有回应")
        XCTAssertEqual(AskFailure.other("x").detail(provider: "DeepSeek"), "x")
        XCTAssertEqual(AskFailure.noKey.actions.map(\.action), [.openModels, .retry])
        XCTAssertEqual(AskFailure.offline.actions.map(\.title), ["再试一次"])
        // 橙 = 还差一步（没填、网络），红 = 出错
        XCTAssertEqual([AskFailure.noKey, .timeout, .offline].map(\.isError), [false, false, false])
        XCTAssertEqual([AskFailure.invalidKey, .quota, .other("x")].map(\.isError), [true, true, true])
    }
}

final class AskScreenNoteTests: XCTestCase {
    func testNoPermissionOffersGrant() {
        let banner = AskScreenNote.banner(for: ScreenSnapshotError.noPermission.userMessage, needsRelaunch: false)
        XCTAssertEqual(banner.text, "这次没看屏幕：还没给屏幕录制权限")
        XCTAssertEqual(banner.action, .grant)
        // 没给权限时就算启动标记说「后来给了」也先去授权
        XCTAssertEqual(AskScreenNote.banner(for: ScreenSnapshotError.noPermission.userMessage, needsRelaunch: true).action, .grant)
    }

    func testGrantedAfterLaunchOffersRelaunch() {
        let banner = AskScreenNote.banner(for: ScreenSnapshotError.captureFailed("SCK -3801").userMessage, needsRelaunch: true)
        XCTAssertEqual(banner.text, "这次没看屏幕：屏幕录制刚打开，重新打开 Ask Free 后生效")
        XCTAssertEqual(banner.action, .relaunch)
    }

    func testOtherReasonsDropTheSecondHalf() {
        XCTAssertEqual(AskScreenNote.banner(for: ScreenSnapshotError.noDisplay.userMessage, needsRelaunch: false).text,
                       "这次没看屏幕：没找到指针所在的屏幕")
        XCTAssertEqual(AskScreenNote.banner(for: ScreenSnapshotError.captureFailed("超时").userMessage, needsRelaunch: false).text,
                       "这次没看屏幕：截屏失败（超时）")
        XCTAssertEqual(AskScreenNote.banner(for: AskScreenNote.slowCapture, needsRelaunch: false).text, "这次没看屏幕：截屏没赶上")
        XCTAssertNil(AskScreenNote.banner(for: ScreenSnapshotError.encodeFailed.userMessage, needsRelaunch: false).action)
    }
}
