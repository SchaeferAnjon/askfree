import XCTest
@testable import AskFreeCore

final class CloudASRTranscriberTests: XCTestCase {

    // MARK: - recognitionBudget：识别等待预算随音频时长放宽（修长录音超时白录的回归）

    /// 短录音（含 0 / 几秒）维持 ~60s 基础预算，不受影响。
    func testBudgetShortAudioStaysAt60() {
        XCTAssertEqual(CloudASRTranscriber.recognitionBudget(audioSeconds: 0), 60, accuracy: 0.001)
        XCTAssertEqual(CloudASRTranscriber.recognitionBudget(audioSeconds: 5), 62.5, accuracy: 0.001)
        // 60s 录音 → 60*0.5+60 = 90
        XCTAssertEqual(CloudASRTranscriber.recognitionBudget(audioSeconds: 60), 90, accuracy: 0.001)
    }

    /// 长录音放宽，但封顶 600s（10 分钟）。30 分钟曾因死守 60s 超时 → 现在给足时间。
    func testBudgetLongAudioCappedAt600() {
        // 20 分钟（1200s）→ 1200*0.5+60 = 660 → 封顶 600
        XCTAssertEqual(CloudASRTranscriber.recognitionBudget(audioSeconds: 1200), 600, accuracy: 0.001)
        // 30 分钟（1800s）→ 同样封顶 600
        XCTAssertEqual(CloudASRTranscriber.recognitionBudget(audioSeconds: 1800), 600, accuracy: 0.001)
    }

    /// 关键回归点：30 分钟录音的预算必须明显大于旧的写死 60s（否则又会提前超时白录）。
    func testBudgetForThirtyMinutesIsWellAboveOldSixtySeconds() {
        XCTAssertGreaterThan(CloudASRTranscriber.recognitionBudget(audioSeconds: 1800), 60)
    }

}
