import Foundation

/// 语音识别时顺带交给火山的上下文：屏幕上指针附近的字（英文词当热词）、这个话题前几轮的问答。
/// 火山文档（热词与上下文，2026-09-29）：非流式识别能在 request.corpus.context 里直传热词和对话上下文（800 tokens 以内），
/// 热词是「提示」不是强制替换。2026-11-07 用合成语音实测极速版：artifacts 从「R U I」认对、no stream 从「诺斯壮」认对，
/// 速度不变（约 1 到 1.8 秒）；豆包 2.0 带截图当上下文没看出效果，还慢半秒，没用。
public struct ASRContext: Equatable, Sendable {
    /// 指针附近认出来的几行字
    public var screenLines: [String]
    /// 指针正下方的词
    public var pointerWord: String?
    /// 这个话题前几轮的问答，旧的在前
    public var dialog: [ASRDialogTurn]

    public init(screenLines: [String] = [], pointerWord: String? = nil, dialog: [ASRDialogTurn] = []) {
        self.screenLines = screenLines
        self.pointerWord = pointerWord
        self.dialog = dialog
    }

    public var isEmpty: Bool { screenLines.isEmpty && pointerWord == nil && dialog.isEmpty }

    /// 热词最多几个：太多反而容易把不相干的词套进去（火山文档：宁缺毋滥）
    public static let hotwordLimit = 30
    /// 上下文文字最多多少字（文档上限 800 tokens，中文一字约 1 到 2 个 token）
    public static let textLimit = 500

    private static let stopwords: Set<String> = [
        "the", "a", "an", "to", "of", "in", "on", "is", "are", "was", "were", "be", "and", "or", "for", "with", "this", "that",
        "it", "its", "as", "at", "by", "from", "you", "your", "we", "our", "if", "not", "but", "can", "will", "do", "does",
        "has", "have", "had", "so", "than", "then", "there", "they", "he", "she", "his", "her", "all", "any", "more", "no",
        "yes", "up", "out", "into", "about", "what", "which", "who", "how", "when", "where", "why", "also", "just", "only",
    ]

    /// 屏幕上的英文词、代码里的名字：中文对它们最容易听错。指针下的词排第一
    public var hotwords: [String] {
        var words: [String] = []
        func add(_ w: String) {
            let t = w.trimmingCharacters(in: CharacterSet(charactersIn: ".-+"))
            guard t.count >= 2, t.count <= 30, !Self.stopwords.contains(t.lowercased()),
                  !words.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
            words.append(t)
        }
        if let pointerWord, pointerWord.unicodeScalars.contains(where: { $0.isASCII && CharacterSet.letters.contains($0) }) {
            add(pointerWord)
        }
        let pattern = try! NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9_+#♭.\-]*[A-Za-z0-9+#♭]"#)
        for line in screenLines {
            let ns = line as NSString
            for m in pattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                add(ns.substring(with: m.range))
                if words.count >= Self.hotwordLimit { return words }
            }
        }
        return words
    }

    /// request.corpus.context 的值（JSON 字符串）。context_data 新的在前：先是上一轮问答，再是屏幕上的字
    public func corpusContext() -> String? {
        guard !isEmpty else { return nil }
        var data: [[String: String]] = []
        var budget = Self.textLimit
        func push(_ text: String) {
            guard budget > 0 else { return }
            let piece = String(text.prefix(budget))
            budget -= piece.count
            data.append(["text": piece])
        }
        for turn in dialog.reversed() {
            push(String(turn.answer.prefix(200)))
            push(turn.question)
        }
        let screen = screenLines.joined(separator: "\n")
        if !screen.isEmpty { push("用户正看着的屏幕上有这些字：\n" + screen) }
        var json: [String: Any] = [:]
        let words = hotwords
        if !words.isEmpty { json["hotwords"] = words.map { ["word": $0] } }
        if !data.isEmpty {
            json["context_type"] = "dialog_ctx"
            json["context_data"] = data
        }
        guard !json.isEmpty, let encoded = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(data: encoded, encoding: .utf8)
    }
}

public struct ASRDialogTurn: Equatable, Sendable {
    public let question: String
    public let answer: String
    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}
