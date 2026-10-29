import XCTest
@testable import AskFreeCore

/// 提示词第二段：允许标了语言的代码块，公式用 $ / $$（task-lue8s §7）
final class AskAIPromptTests: XCTestCase {
    func testFormatLineAllowsCodeBlocksAndDollarMath() {
        let prompt = AskAI.askSystemPrompt
        XCTAssertTrue(prompt.contains("$...$"))
        XCTAssertTrue(prompt.contains("$$...$$"))
        XCTAssertTrue(prompt.contains("```python"))
        XCTAssertTrue(prompt.contains("不用表格、引用。"))
        XCTAssertFalse(prompt.contains("代码块。"))
    }

    /// Swift 字符串里写成 \\( 才是反斜杠加括号，写成 \( 会被当成插值
    func testBackslashDelimitersAreLiteral() {
        let prompt = AskAI.askSystemPrompt
        XCTAssertTrue(prompt.contains("不用 \\(、\\[、\\boxed、\\tag。"))
        XCTAssertEqual(prompt.components(separatedBy: "\n").count, 2, "还是两段")
    }
}
