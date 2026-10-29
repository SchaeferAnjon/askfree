import XCTest
@testable import AskFreeCore

final class AnswerMarkdownTests: XCTestCase {
    func testStripsHeadingsBoldAndBullets() {
        let md = "### 原因\n\n- **少装了** sharp\n* 版本不对\n\n\n1、 先装\n2) 再跑"
        XCTAssertEqual(AnswerMarkdown.plainText(md), "原因\n\n• 少装了 sharp\n• 版本不对\n\n1. 先装\n2. 再跑")
        XCTAssertEqual(AnswerMarkdown.preview(md), "原因 • 少装了 sharp • 版本不对 1. 先装 2. 再跑")
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
        XCTAssertEqual(AnswerMarkdown.preview(md), "跑 date 看时间： echo `date`")
    }

    func testPreviewDropsCodeFenceLinesButKeepsCode() {
        let md = "装一下：\n\n```bash\n  npm install sharp\n\n```\n\n再跑一次。"
        XCTAssertEqual(AnswerMarkdown.preview(md), "装一下： npm install sharp 再跑一次。")
    }

    func testTrimsLeadingAndTrailingBlankLines() {
        XCTAssertEqual(AnswerMarkdown.plainText("\n\n答案\n\n\n"), "答案")
        XCTAssertEqual(AnswerMarkdown.plainText(""), "")
        XCTAssertEqual(AnswerMarkdown.preview(""), "")
    }

    // MARK: - 公式（task-lue8s）

    /// 复制时公式连分隔符原样：里面的 *、_、反引号一个不删
    func testCopyKeepsFormulasVerbatim() {
        XCTAssertEqual(AnswerMarkdown.plainText("**面积** $a*b*c$ 和 $\\mathbf{x}_1$，`code` \\(x^2\\)"),
                       "面积 $a*b*c$ 和 $\\mathbf{x}_1$，code \\(x^2\\)")
        XCTAssertEqual(AnswerMarkdown.plainText("- 判别式 $\\Delta=b^2-4ac$"), "• 判别式 $\\Delta=b^2-4ac$")
    }

    func testCopyKeepsDisplayMathVerbatim() {
        let md = "推出：\n\n$$\nx = \\frac{**a**}{b}\n$$\n\n\\[a*b\\]"
        XCTAssertEqual(AnswerMarkdown.plainText(md), md)
    }

    func testCopyKeepsIndentedAndUnclosedFences() {
        let indented = "1. 装：\n   ```bash\n   npm i **x**\n   ```"
        XCTAssertEqual(AnswerMarkdown.plainText(indented), "1. 装：\n   ```bash\n   npm i **x**\n   ```")
        let unclosed = "看：\n```js\nconst a = `x`;\n**b**"
        XCTAssertEqual(AnswerMarkdown.plainText(unclosed), unclosed)
    }

    func testPreviewFlattensInlineFormulas() {
        XCTAssertEqual(AnswerMarkdown.preview("求根公式 $x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}$，**判别式** \\(\\Delta\\)"),
                       "求根公式 x=(−b±√(b²−4ac))/(2a)，判别式 Δ")
    }

    func testPreviewFlattensDisplayFormulasOnTheirOwnLine() {
        XCTAssertEqual(AnswerMarkdown.preview("配方：\n\n$$\n(x+\\frac{b}{2a})^2\n$$\n\n\\[E=mc^2\\] 是质能"),
                       "配方： (x+b/(2a))² E=mc² 是质能")
    }

    func testPreviewStillDropsFences() {
        XCTAssertEqual(AnswerMarkdown.preview("跑：\n\n```python\n  print($x$)\n```\n完"), "跑： print($x$) 完")
    }

    // MARK: - 评审修正（task-lue8s）

    /// 折起来的那一轮只给两行：各段接成一段，中间一个空格，不留空行（设计评审 5）
    func testPreviewIsOneParagraph() {
        let md = "用 pandas 最省事：\n\n```python\nimport pandas as pd\n\ndf = pd.read_csv(\"a.csv\")\n```\n\n跑一下就行。"
        XCTAssertEqual(AnswerMarkdown.preview(md), "用 pandas 最省事： import pandas as pd df = pd.read_csv(\"a.csv\") 跑一下就行。")
        XCTAssertFalse(AnswerMarkdown.preview(md).contains("\n"))
        XCTAssertFalse(AnswerMarkdown.preview(md).contains("  "))
    }

    /// 模型写的 \$ 在预览里是 $，和面板显示的一样；复制照原文（代码评审 4）
    func testPreviewUnescapesDollar() {
        let md = "门票 \\$5，学生票 \\$3，设人数为 $n$。"
        XCTAssertEqual(AnswerMarkdown.preview(md), "门票 $5，学生票 $3，设人数为 n。")
        XCTAssertEqual(AnswerMarkdown.plainText(md), md)
    }
}
