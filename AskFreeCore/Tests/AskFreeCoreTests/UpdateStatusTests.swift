import XCTest
@testable import AskFreeCore

final class UpdateStatusTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testLines() {
        let now = date(2026, 10, 28, 9, 5)
        XCTAssertEqual(UpdatePhase.off.line(currentVersion: "1.1.0"), "开发版不自动更新。")
        XCTAssertEqual(UpdatePhase.idle.line(currentVersion: "1.1.0"), "当前版本 1.1.0")
        XCTAssertEqual(UpdatePhase.checking.line(currentVersion: "1.1.0"), "正在检查…")
        XCTAssertEqual(UpdatePhase.downloading(version: "1.2.0", percent: 35).line(currentVersion: "1.1.0"), "正在下载新版本 1.2.0，35%")
        XCTAssertEqual(UpdatePhase.downloading(version: "1.2.0", percent: nil).line(currentVersion: "1.1.0"), "正在下载新版本 1.2.0…")
        XCTAssertEqual(UpdatePhase.preparing(version: "1.2.0").line(currentVersion: "1.1.0"), "新版本 1.2.0 下载好了，正在核对签名…")
        XCTAssertEqual(UpdatePhase.ready(version: "1.2.0").line(currentVersion: "1.1.0"), "新版本 1.2.0 已下载好，重启就能用。")
        XCTAssertEqual(UpdatePhase.error("连不上 GitHub，过一会儿会再查").line(currentVersion: "1.1.0"), "更新出错：连不上 GitHub，过一会儿会再查")
        XCTAssertEqual(UpdatePhase.latest(checkedAt: date(2026, 10, 28, 8, 7)).line(currentVersion: "1.1.0", now: now, calendar: calendar),
                       "已是最新版本 1.1.0，今天 08:07 查过")
        XCTAssertEqual(UpdatePhase.latest(checkedAt: date(2026, 10, 27, 23, 50)).line(currentVersion: "1.1.0", now: now, calendar: calendar),
                       "已是最新版本 1.1.0，昨天 23:50 查过")
        XCTAssertEqual(UpdatePhase.latest(checkedAt: date(2026, 9, 3, 14, 0)).line(currentVersion: "1.1.0", now: now, calendar: calendar),
                       "已是最新版本 1.1.0，9月3日 14:00 查过")
    }

    func testCheckButtonOnlyWhenIdle() {
        XCTAssertEqual([UpdatePhase.idle, .latest(checkedAt: Date()), .error("x")].map(\.canCheck), [true, true, true])
        XCTAssertEqual([UpdatePhase.off, .checking, .downloading(version: "1", percent: 1), .preparing(version: "1"), .ready(version: "1")].map(\.canCheck),
                       [false, false, false, false, false])
        XCTAssertEqual(UpdatePhase.ready(version: "1.2.0").readyVersion, "1.2.0")
        XCTAssertNil(UpdatePhase.downloading(version: "1.2.0", percent: 100).readyVersion)
    }

    func testPercent() {
        XCTAssertNil(UpdatePhase.percent(received: 10, expected: 0), "服务器没说多大")
        XCTAssertEqual(UpdatePhase.percent(received: 0, expected: 200), 0)
        XCTAssertEqual(UpdatePhase.percent(received: 99, expected: 200), 49)
        XCTAssertEqual(UpdatePhase.percent(received: 500, expected: 200), 100, "收到的比说的多也不超过 100")
    }

    func testInApplications() {
        XCTAssertTrue(UpdateLocation.isInApplications(bundlePath: "/Applications/Ask Free.app", home: "/Users/a"))
        XCTAssertTrue(UpdateLocation.isInApplications(bundlePath: "/Users/a/Applications/Ask Free Dev.app", home: "/Users/a"))
        XCTAssertFalse(UpdateLocation.isInApplications(bundlePath: "/Users/a/Downloads/Ask Free.app", home: "/Users/a"))
        XCTAssertFalse(UpdateLocation.isInApplications(bundlePath: "/Volumes/Ask Free/Ask Free.app", home: "/Users/a"))
        XCTAssertFalse(UpdateLocation.isInApplications(bundlePath: "/private/var/folders/x/AppTranslocation/1/d/Ask Free.app", home: "/Users/a"))
        XCTAssertFalse(UpdateLocation.isInApplications(bundlePath: "/ApplicationsOld/Ask Free.app", home: "/Users/a"))
        XCTAssertTrue(UpdateLocation.isInApplications(bundlePath: "/Applications/Tools/../Ask Free.app", home: "/Users/a"))
    }

    /// 照 Sparkle 2.10 实测的样子套三层（本机起一个 404 的地址、一个连不上的端口看到的）
    private func sparkleDownloadError(innermost: NSError) -> NSError {
        let d = UpdateErrorText.sparkleDomain
        let mid = NSError(domain: d, code: 2001, userInfo: [NSLocalizedDescriptionKey: "An error occurred while downloading the update. Please try again later.",
                                                            NSUnderlyingErrorKey: innermost])
        return NSError(domain: d, code: 2001, userInfo: [NSLocalizedDescriptionKey: "An error occurred in retrieving update information. Please try again later.",
                                                         NSUnderlyingErrorKey: mid])
    }

    func testFeedErrors() {
        let d = UpdateErrorText.sparkleDomain
        let notFound = sparkleDownloadError(innermost: NSError(domain: d, code: 2001, userInfo: [
            NSLocalizedDescriptionKey: "A network error occurred while downloading https://github.com/x/appcast.xml. not found (404)"]))
        XCTAssertEqual(UpdateErrorText.message(for: notFound), "GitHub 上还没有能自动更新的新版本")
        XCTAssertEqual(UpdateErrorText.message(for: notFound, foundVersion: "1.2.0"), "新版本 1.2.0 的安装包下载不到（404），过一会儿再试")
        let serverError = sparkleDownloadError(innermost: NSError(domain: d, code: 2001, userInfo: [
            NSLocalizedDescriptionKey: "A network error occurred while downloading https://github.com/x/appcast.xml. internal server error (500)"]))
        XCTAssertEqual(UpdateErrorText.message(for: serverError), "取不到更新信息（500），过一会儿再试")
        let refused = sparkleDownloadError(innermost: NSError(domain: d, code: 2001, userInfo: [
            NSLocalizedDescriptionKey: "Failed to download temporary data.",
            NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)]))
        XCTAssertEqual(UpdateErrorText.message(for: refused), "连不上 GitHub，过一会儿会再查")
        XCTAssertEqual(UpdateErrorText.message(for: NSError(domain: d, code: 2001)), "取不到更新信息，过一会儿再试")
        XCTAssertEqual(UpdateErrorText.message(for: NSError(domain: d, code: 2001), foundVersion: "1.2.0"), "新版本 1.2.0 的安装包下载不到，过一会儿再试")
    }

    func testErrorText() {
        let sparkle = UpdateErrorText.sparkleDomain
        XCTAssertEqual(UpdateErrorText.message(for: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)), "连不上 GitHub，过一会儿会再查")
        XCTAssertEqual(UpdateErrorText.message(for: NSError(domain: sparkle, code: 1000)), "GitHub 上的更新信息读不了，过一会儿再试")
        for code in [3001, 3002, 4009] {
            XCTAssertEqual(UpdateErrorText.message(for: NSError(domain: sparkle, code: code)), "新版本的签名和装着的这一版对不上，没有装", "\(code)")
        }
        // 实测：篡改过的更新包，Sparkle 报的是 4005 ← 4005 ← 3002
        let tampered = NSError(domain: sparkle, code: 4005, userInfo: [
            NSLocalizedDescriptionKey: "The update is improperly signed and could not be validated.",
            NSUnderlyingErrorKey: NSError(domain: sparkle, code: 4005, userInfo: [NSUnderlyingErrorKey: NSError(domain: sparkle, code: 3002)])])
        XCTAssertEqual(UpdateErrorText.message(for: tampered, foundVersion: "1.2.0"), "新版本的签名和装着的这一版对不上，没有装")
        XCTAssertTrue(UpdateErrorText.message(for: NSError(domain: sparkle, code: 1005)).contains("拖进「应用程序」"))
        XCTAssertTrue(UpdateErrorText.message(for: NSError(domain: sparkle, code: 4012)).contains("没有权限"))
        let unknown = NSError(domain: sparkle, code: 4005, userInfo: [NSLocalizedDescriptionKey: "An error occurred while installing the update."])
        XCTAssertEqual(UpdateErrorText.message(for: unknown), "An error occurred while installing the update.", "认不出的原样给")
        XCTAssertEqual(UpdateErrorText.message(for: NSError(domain: "Other", code: 2001, userInfo: [NSLocalizedDescriptionKey: "x"])), "x",
                       "只认 Sparkle 自己的错误码")
    }
}
