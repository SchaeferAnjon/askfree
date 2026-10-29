import XCTest
@testable import AskFreeCore

final class AppIdentityTests: XCTestCase {
    func testDevBundleIDs() {
        XCTAssertFalse(AppIdentity.isDevBundleID("io.github.schaeferanjon.askfree"))
        XCTAssertTrue(AppIdentity.isDevBundleID("io.github.schaeferanjon.askfree.dev"))
        XCTAssertTrue(AppIdentity.isDevBundleID("io.github.schaeferanjon.askfree.dev.latex"))
        XCTAssertFalse(AppIdentity.isDevBundleID("io.github.schaeferanjon.askfree.devx"))
        XCTAssertFalse(AppIdentity.isDevBundleID(nil))
        // 单元测试进程不是开发版
        XCTAssertFalse(AppIdentity.isDevBuild)
    }
}
