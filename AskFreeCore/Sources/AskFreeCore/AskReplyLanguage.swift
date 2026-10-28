import Foundation
import NaturalLanguage

/// 用什么语言回答。system prompt 是中文写的，里面「用用户提问的语言回答」一句不够：
/// 2026-10-28 拍 README 截图时问了 8 个英文问题，DeepSeek 4 次用中文答（看屏幕问报错、它的追问、造句、联网查天气）。
/// 问题不是中文时，在 system prompt 最末尾（截图说明、联网资料之后）用英文再说一遍，点名是哪种语言。
public enum AskReplyLanguage {
    /// 要补的那一句；中文问题返回空串（提示词照旧）
    public static func promptLine(for question: String) -> String {
        guard let name = languageName(of: question) else { return "" }
        return "\n\nIMPORTANT: The user asked in \(name). Write the entire answer in \(name), "
            + "even though the instructions above are in Chinese and the screenshot or search results may be in Chinese. "
            + "Do not answer in Chinese."
    }

    /// 问题是什么语言（英文名）；中文、没有字母的返回 nil
    public static func languageName(of question: String) -> String? {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = text.unicodeScalars
        // 日文带假名（汉字也算日文）；有汉字没假名就是中文，夹着英文词（「这个 error 是什么」）也算中文
        if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return "Japanese" }
        if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return "Korean" }
        if scalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }) { return nil }
        guard scalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        // 几个词的短句认不准：拿不准就按英文（语音识别只出中文和英文）
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first, confidence >= 0.6,
              language != .simplifiedChinese, language != .traditionalChinese,
              let name = Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue) else { return "English" }
        return name
    }
}
