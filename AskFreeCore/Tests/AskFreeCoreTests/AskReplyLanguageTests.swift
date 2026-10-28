import XCTest
@testable import AskFreeCore

final class AskReplyLanguageTests: XCTestCase {
    func testChineseQuestionsKeepThePromptAsIs() {
        for q in ["这个报错是什么意思？怎么弄好？", "这个 error 是什么意思", "sharp 是什么", "搜一下周六杭州会下雨吗", "  ", "123？"] {
            XCTAssertEqual(AskReplyLanguage.promptLine(for: q), "", q)
        }
    }

    func testEnglishQuestionsGetAnExplicitEnglishLine() {
        for q in ["What does this error mean and how do I fix it?", "Use it in a sentence",
                  "Will it rain in Hangzhou on Saturday?", "what is this", "ok?"] {
            XCTAssertEqual(AskReplyLanguage.languageName(of: q), "English", q)
            let line = AskReplyLanguage.promptLine(for: q)
            XCTAssertTrue(line.contains("Write the entire answer in English"), q)
            XCTAssertTrue(line.hasPrefix("\n\n"), "接在提示词最后，另起一段")
        }
    }

    func testJapaneseAndKorean() {
        XCTAssertEqual(AskReplyLanguage.languageName(of: "この単語はどういう意味ですか"), "Japanese")
        XCTAssertEqual(AskReplyLanguage.languageName(of: "이게 무슨 뜻이에요?"), "Korean")
    }

    func testOtherLatinLanguagesAreNamedWhenClear() {
        XCTAssertEqual(AskReplyLanguage.languageName(of: "Qu'est-ce que cette erreur veut dire et comment la corriger ?"), "French")
        XCTAssertEqual(AskReplyLanguage.languageName(of: "Was bedeutet diese Fehlermeldung und wie behebe ich sie?"), "German")
    }
}
