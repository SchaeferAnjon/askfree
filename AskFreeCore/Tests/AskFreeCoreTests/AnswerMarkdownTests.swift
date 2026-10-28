import XCTest
@testable import AskFreeCore

final class AnswerMarkdownTests: XCTestCase {
    func testStripsHeadingsBoldAndBullets() {
        let md = "### 原因\n\n- **少装了** sharp\n* 版本不对\n\n\n1、 先装\n2) 再跑"
        XCTAssertEqual(AnswerMarkdown.plainText(md), "原因\n\n• 少装了 sharp\n• 版本不对\n\n1. 先装\n2. 再跑")
    }

    /// 追问时折起来的上一轮预览以前露着反引号：「运行 `npm install sharp`」
    func testStripsInlineCodeBackticks() {
        XCTAssertEqual(AnswerMarkdown.plainText("运行 `npm install sharp` 就好，或者 ``brew install vips``。"),
                       "运行 npm install sharp 就好，或者 brew install vips。")
        XCTAssertEqual(AnswerMarkdown.plainText("- **命令**：`ls -a`"), "• 命令：ls -a")
    }

    func testDropsCodeFenceLinesButKeepsCode() {
        let md = "装一下：\n\n```bash\nnpm install sharp\n```\n\n再跑一次。"
        XCTAssertEqual(AnswerMarkdown.plainText(md), "装一下：\n\nnpm install sharp\n\n再跑一次。")
    }

    func testTrimsLeadingAndTrailingBlankLines() {
        XCTAssertEqual(AnswerMarkdown.plainText("\n\n答案\n\n\n"), "答案")
        XCTAssertEqual(AnswerMarkdown.plainText(""), "")
    }
}
