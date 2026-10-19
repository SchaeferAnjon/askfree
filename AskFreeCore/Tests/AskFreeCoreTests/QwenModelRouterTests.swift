import XCTest
@testable import AskFreeCore

final class QwenModelRouterTests: XCTestCase {

    private let suiteName = "QwenModelRouterTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testIsAuto() {
        XCTAssertTrue(QwenModelRouter.isAuto("auto"))
        XCTAssertTrue(QwenModelRouter.isAuto("auto-speed"))
        XCTAssertFalse(QwenModelRouter.isAuto("qwen3.8-max"))
        XCTAssertFalse(QwenModelRouter.isAuto(nil))
    }

    func testDefaultCandidatesAreQualityChain() {
        XCTAssertEqual(QwenModelRouter.candidates(defaults: defaults),
                       ["qwen3.7-plus", "qwen3.8-max", "qwen3.7-max", "qwen3.7-flash", "qwen3.6-flash"])
        XCTAssertEqual(QwenModelRouter.candidates(for: "auto", defaults: defaults),
                       ["qwen3.7-plus", "qwen3.8-max", "qwen3.7-max", "qwen3.7-flash", "qwen3.6-flash"])
    }

    func testSpeedCandidatesPutFlashFirst() {
        XCTAssertEqual(QwenModelRouter.candidates(for: "auto-speed", defaults: defaults),
                       ["qwen3.7-flash", "qwen3.6-flash", "qwen3.8-max", "qwen3.7-max"])
    }

    func testSpeedChainDegradesToMaxWhenFlashExhausted() {
        QwenModelRouter.markExhausted("qwen3.7-flash", defaults: defaults)
        QwenModelRouter.markExhausted("qwen3.6-flash", defaults: defaults)
        XCTAssertEqual(QwenModelRouter.candidates(for: "auto-speed", defaults: defaults),
                       ["qwen3.8-max", "qwen3.7-max"],
                       "flash 档额度用完 → 落到 max 档继续免费")
    }

    func testExhaustedModelIsSkipped() {
        QwenModelRouter.markExhausted("qwen3.8-max", defaults: defaults)
        XCTAssertEqual(QwenModelRouter.candidates(defaults: defaults),
                       ["qwen3.7-plus", "qwen3.7-max", "qwen3.7-flash", "qwen3.6-flash"])
    }

    func testAllExhaustedFallsBackToCheapest() {
        for m in QwenModelRouter.qualityChain {
            QwenModelRouter.markExhausted(m, defaults: defaults)
        }
        XCTAssertEqual(QwenModelRouter.candidates(defaults: defaults),
                       [QwenModelRouter.lastResort],
                       "全部额度用完 → 落到付费最便宜的模型")
    }

    func testCooldownExpires() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        QwenModelRouter.markExhausted("qwen3.8-max", now: t0, defaults: defaults)
        XCTAssertTrue(QwenModelRouter.isExhausted("qwen3.8-max",
                                                    now: t0.addingTimeInterval(19 * 3600),
                                                    defaults: defaults),
                      "冷却期内（19 小时）仍应视为额度用完")
        XCTAssertFalse(QwenModelRouter.isExhausted("qwen3.8-max",
                                                     now: t0.addingTimeInterval(21 * 3600),
                                                     defaults: defaults),
                       "冷却到期（21 小时）后应自动恢复重试")
        XCTAssertTrue(QwenModelRouter.candidates(now: t0.addingTimeInterval(21 * 3600),
                                                   defaults: defaults).contains("qwen3.8-max"),
                      "冷却到期后应回到候选队列")
    }
}
