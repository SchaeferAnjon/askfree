import XCTest
@testable import AskFreeCore

final class AnswerMarkdownTests: XCTestCase {
    func testStripsHeadingsBoldAndBullets() {
        let md = "### 原因\n\n- **少装了** sharp\n* 版本不对\n\n\n1、 先装\n2) 再跑"
        XCTAssertEqual(AnswerMarkdown.plainText(md), "原因\n\n• 少装了 sharp\n• 版本不对\n\n1. 先装\n2. 再跑")
        XCTAssertEqual(AnswerMarkdown.preview(md), "原因\n\n• 少装了 sharp\n• 版本不对\n\n1. 先装\n2. 再跑")
    }

    /// 追问时折起来的上一轮预览以前露着反引号：「运行 `npm install sharp`」
    func testStripsInlineCodeBackticks() {
        XCTAssertEqual(AnswerMarkdown.preview("运行 `npm install sharp` 就好，或者 ``brew install vips``。"),
                       "运行 npm install sharp 就好，或者 brew install vips。")
        XCTAssertEqual(AnswerMarkdown.preview("- **命令**：`ls -a`"), "• 命令：ls -a")
        XCTAssertEqual(AnswerMarkdown.plainText("- **命令**：`ls -a`"), "• 命令：ls -a")
    }

    /// 复制出去还是代码块：``` 那一行留着，块里一个字不改
    func testCopyKeepsCodeFences() {
        let md = "装一下：\n\n```bash\nnpm install sharp\n```\n\n再跑一次。"
        XCTAssertEqual(AnswerMarkdown.plainText(md), md)
    }

    /// 代码块里的反引号是命令的一部分，复制时不能删：echo "today is `date`" 不能变成 echo "today is date"
    func testCopyKeepsBackticksInsideCodeBlock() {
        let md = """
        用命令替换：

        ```bash
        echo "today is `date`"
        ```

        JS 里是模板字符串：

        ```js
        const msg = `hi ${name}`;
        function f(**kwargs) {}
          - 缩进的这一行也不动
        ```
        """
        XCTAssertEqual(AnswerMarkdown.plainText(md), md)
    }

    /// 块外的行内反引号照样去掉，块里照样保留
    func testInlineBackticksOutsideBlockStrippedInsideKept() {
        let md = "跑 `date` 看时间：\n```\necho `date`\n```"
        XCTAssertEqual(AnswerMarkdown.plainText(md), "跑 date 看时间：\n```\necho `date`\n```")
        XCTAssertEqual(AnswerMarkdown.preview(md), "跑 date 看时间：\necho `date`")
    }

    func testPreviewDropsCodeFenceLinesButKeepsCode() {
        let md = "装一下：\n\n```bash\n  npm install sharp\n\n```\n\n再跑一次。"
        XCTAssertEqual(AnswerMarkdown.preview(md), "装一下：\n\nnpm install sharp\n\n再跑一次。")
    }

    func testTrimsLeadingAndTrailingBlankLines() {
        XCTAssertEqual(AnswerMarkdown.plainText("\n\n答案\n\n\n"), "答案")
        XCTAssertEqual(AnswerMarkdown.plainText(""), "")
        XCTAssertEqual(AnswerMarkdown.preview(""), "")
    }
}
