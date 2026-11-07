import XCTest
@testable import AskFreeCore

final class PointerTextTests: XCTestCase {
    /// 一行字按等宽排出各词的框：每个字符 w 像素宽，从 x 开始
    private func line(_ text: String, x: CGFloat = 0, y: CGFloat, charWidth w: CGFloat = 16, height h: CGFloat = 30) -> OCRLine {
        let tokens = OCRLine.wordRanges(in: text).map { r -> OCRLine.Token in
            let start = CGFloat(text.distance(from: text.startIndex, to: r.lowerBound))
            let len = CGFloat(text.distance(from: r.lowerBound, to: r.upperBound))
            return .init(text: String(text[r]), box: CGRect(x: x + start * w, y: y, width: len * w, height: h))
        }
        return OCRLine(text: text, box: CGRect(x: x, y: y, width: CGFloat(text.count) * w, height: h), tokens: tokens)
    }

    func testWordRangesSplitWordsAndCJK() {
        let text = "SyntaxError: EOL while snake_case 中文 v1.2"
        XCTAssertEqual(OCRLine.wordRanges(in: text).map { String(text[$0]) },
                       ["SyntaxError", "EOL", "while", "snake_case", "中", "文", "v1", "2"])
        XCTAssertEqual(OCRLine.wordRanges(in: "don't stop").map { String("don't stop"[$0]) }, ["don't", "stop"])
    }

    /// 10 月 22 日问「eol?」那张图：指针在 EOL 上，框里还有十来个词，要挑出 EOL
    func testPicksTheWordUnderThePointer() {
        let lines = [
            line("Cell In [7], line 1", y: 650),
            line("print(\"Hello, Andrew!)", y: 680),
            line("SyntaxError: EOL while scanning string literal", y: 720),
        ]
        // "SyntaxError: " 13 个字符，EOL 在 x 208 到 256
        let picked = PointerTextPicker.pick(lines: lines, pointer: CGPoint(x: 230, y: 735), scale: 2)
        XCTAssertEqual(picked.word, "EOL")
        XCTAssertEqual(picked.line, "SyntaxError: EOL while scanning string literal")
        XCTAssertEqual(picked.wordBox, CGRect(x: 208, y: 720, width: 48, height: 30))
        XCTAssertEqual(picked.context.last, "SyntaxError: EOL while scanning string literal")
        XCTAssertEqual(picked.context.count, 3)
    }

    func testPointerBetweenWordsTakesTheNearestWithinSlop() {
        let lines = [line("hello world", y: 100)]
        // 空格在 x 80 到 96；指针在 x 94，离 world（96 起）2 像素
        XCTAssertEqual(PointerTextPicker.pick(lines: lines, pointer: CGPoint(x: 94, y: 110), scale: 2).word, "world")
        // 离字太远（30 像素外的空白处）：什么都不算
        XCTAssertTrue(PointerTextPicker.pick(lines: lines, pointer: CGPoint(x: 400, y: 110), scale: 2).isEmpty)
    }

    func testContextStaysInTheSameColumn() {
        let lines = [
            line("left column one", x: 0, y: 100),
            line("def add(a, b):", x: 0, y: 140),
            line("    return a + b", x: 0, y: 180),
            line("right sidebar text", x: 1200, y: 140),
        ]
        let picked = PointerTextPicker.pick(lines: lines, pointer: CGPoint(x: 10, y: 150), scale: 2)
        XCTAssertEqual(picked.word, "def")
        XCTAssertEqual(picked.context, ["left column one", "def add(a, b):", "    return a + b"])
    }

    /// Jupyter、教程页：代码夹在讲解段落中间，指着代码那行就算代码
    func testCodeAmidProseCounts() {
        let lines = [
            line("Run the code in the next cell to see an example of how", y: 100),
            line("Python responds to code with an error in it.", y: 140),
            line("SyntaxError: EOL while scanning string literal", y: 180),
            line("You can ask the chatbot to help you fix this code:", y: 220),
            line("1. Open the chatbot", y: 260),
        ]
        XCTAssertTrue(PointerTextPicker.pick(lines: lines, pointer: CGPoint(x: 230, y: 190), scale: 2).looksLikeCode)
        XCTAssertFalse(PointerTextPicker.pick(lines: lines, pointer: CGPoint(x: 20, y: 110), scale: 2).looksLikeCode)
    }

    func testCodeLook() {
        XCTAssertTrue(CodeLook.looksLikeCode(lines: ["def add(a, b):", "    return a + b"]))
        XCTAssertTrue(CodeLook.looksLikeCode(lines: ["const x = items.map(i => i.id);"]))
        XCTAssertTrue(CodeLook.looksLikeCode(lines: ["$ npm install", "SyntaxError: EOL while scanning string literal", "print(\"Hello, Andrew!)"]))
        XCTAssertFalse(CodeLook.looksLikeCode(lines: ["For example, if you go there from here, you will see it.",
                                                      "Let me know what you think of the class."]))
        XCTAssertFalse(CodeLook.looksLikeCode(lines: ["这句话是说：作者在测试之前就把旧的构建产物删掉了。"]))
        XCTAssertTrue(CodeLook.lineLooksLikeCode("SyntaxError: EOL while scanning string literal"))
        // 2026-11-07 实测 Vision 把这行认成了全角标点
        XCTAssertTrue(CodeLook.lineLooksLikeCode("print （\"Hello, Andrew！）"))
        XCTAssertEqual(CodeLook.halfWidth("print （\"Hello, Andrew！）"), "print (\"Hello, Andrew!)")
        XCTAssertTrue(CodeLook.isCodeApp(bundleID: "com.microsoft.VSCode"))
        XCTAssertTrue(CodeLook.isCodeApp(bundleID: "com.jetbrains.pycharm"))
        XCTAssertFalse(CodeLook.isCodeApp(bundleID: "com.apple.Safari"))
        XCTAssertFalse(CodeLook.isCodeApp(bundleID: nil))
    }

    func testPromptTextSaysWhatIsUnderThePointer() throws {
        let p = PointerText(word: "EOL", line: "SyntaxError: EOL while scanning", context: ["print(\"Hi)", "SyntaxError: EOL while scanning"],
                            looksLikeCode: true, appName: "Google Chrome")
        let text = try XCTUnwrap(p.promptText)
        XCTAssertTrue(text.contains("「Google Chrome」"))
        XCTAssertTrue(text.contains("指针正指着「EOL」，在这一行：SyntaxError: EOL while scanning"))
        XCTAssertTrue(text.contains("print(\"Hi)\nSyntaxError"))
        XCTAssertTrue(text.contains("以截图为准"))
        XCTAssertNil(PointerText().promptText)
        let selected = try XCTUnwrap(PointerText(selection: "ephemeral").promptText)
        XCTAssertTrue(selected.contains("选中了这段文字"))
        XCTAssertTrue(selected.contains("ephemeral"))
    }
}

final class AskHeardTests: XCTestCase {
    func testMarkerIsRemovedAndReported() {
        let (display, fixed) = AskHeard.extractMarker("[[问题: 什么叫做首包]]\n首包是流式识别里发的第一段音频。", isFinal: true)
        XCTAssertEqual(display, "首包是流式识别里发的第一段音频。")
        XCTAssertEqual(fixed, "什么叫做首包")
        XCTAssertEqual(AskHeard.extractMarker("[[问题：A♭ 怎么读]]\n读作降 A。").fixed, "A♭ 怎么读")
    }

    func testHalfMarkerIsHiddenWhileStreaming() {
        XCTAssertEqual(AskHeard.extractMarker("[").display, "")
        XCTAssertEqual(AskHeard.extractMarker("[[问").display, "")
        XCTAssertEqual(AskHeard.extractMarker("[[问题: 什么叫").display, "")
        // 答完了还没合上：是正文，原样给
        XCTAssertEqual(AskHeard.extractMarker("[[问题: 什么叫", isFinal: true).display, "[[问题: 什么叫")
        // 普通回答不受影响
        XCTAssertEqual(AskHeard.extractMarker("EOL 是 End Of Line。").display, "EOL 是 End Of Line。")
        // 正文中间引用的不算
        let mid = "你可以这样写：\n[[问题: x]]"
        XCTAssertNil(AskHeard.extractMarker(mid, isFinal: true).fixed)
    }

    func testOnlyMeaningfulFixesCount() {
        XCTAssertFalse(AskHeard.isMeaningfulFix(heard: "这是什么？", fixed: "这是什么"))
        XCTAssertFalse(AskHeard.isMeaningfulFix(heard: "eol", fixed: "EOL?"))
        XCTAssertTrue(AskHeard.isMeaningfulFix(heard: "什么叫做负包", fixed: "什么叫做首包"))
        // 2026-11-07 实测模型写过的两行：原话照抄、只加了间隔点，都不算改
        XCTAssertFalse(AskHeard.isMeaningfulFix(heard: "这句话啥意思", fixed: "这句话啥意思"))
        XCTAssertFalse(AskHeard.isMeaningfulFix(heard: "CF 旁边这个是什么意思啊", fixed: "C·F 旁边这个是什么意思啊"))
        XCTAssertTrue(AskHeard.isMeaningfulFix(heard: "伊欧艾尔是什么意思", fixed: "EOL 是什么意思"))
    }

    func testVisionContentPutsPointerTextBetweenImagesAndQuestion() {
        let content = AskVision.visionUserContent(question: "这是什么", overviewJPEG: Data([1]), closeUpJPEG: Data([2]),
                                                  pointerText: "指针正指着「EOL」")
        XCTAssertEqual(content.count, 4)
        XCTAssertEqual(content[2]["text"] as? String, "指针正指着「EOL」")
        XCTAssertEqual(content[3]["text"] as? String, "这是什么")
        XCTAssertEqual(AskVision.visionUserContent(question: "q", overviewJPEG: Data(), closeUpJPEG: Data()).count, 3)
    }
}
