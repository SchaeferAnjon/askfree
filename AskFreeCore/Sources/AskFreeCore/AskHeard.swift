import Foundation

/// 语音提问：问题是识别出来的文字，可能听错。告诉模型这一点，让它结合屏幕和前面的对话按用户真正想问的来答；
/// 它确定听错了，就在回答第一行写 `[[问题: 改正后的问题]]`，面板把卡上的问题换成改正后的，原话小字留着。
/// 不告诉它的时候，它会把听错的词当成屏幕上的笔误：用户问「什么叫做负包」，它答「负包是文档里的笔误」（2026-10-23 的历史）。
public enum AskHeard {
    public static let promptSuffix = """

    这句问题是语音识别转出来的，可能有字听错：同音字、近音词，英文词被写成发音相近的中文或别的英文（屏幕上是 EOL，听成「伊欧艾尔」；integrated 听成 in-guarded），人名、术语写错。结合截图上的字和前面的对话，按他真正想问的来答；别把听错的地方当成屏幕上的错别字或他的笔误。
    只有原话里确实有字词听错时，回答的第一行才单独写 `[[问题: 改正后的问题]]`，只改听错的那几个字，其余照原话，再换行回答。原话读得通的，哪怕说得含糊（「这个」「这句话啥意思」），也不写这一行，不要替他把问题说完整、换个说法。
    """

    /// 返回去掉标记行后给用户看的文字，和改正后的问题。流式中途 `[[` 还没合上时先藏起来；
    /// 完整回答（isFinal）里没合上的 `[[` 是正文，原样显示。只认回答开头的那一行，正文里引用的不算
    public static func extractMarker(_ text: String, isFinal: Bool = false) -> (display: String, fixed: String?) {
        let ns = text as NSString
        if let m = markerRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let fixed = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let display = ns.replacingCharacters(in: m.range, with: "").trimmingCharacters(in: .newlines)
            return (display, fixed.isEmpty ? nil : fixed)
        }
        if !isFinal {
            // 开头几个字还在路上：可能是 `[[问题: …]]` 的前半截，先不显示
            let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let tag = "[[问题"
            if !head.isEmpty, tag.hasPrefix(head) || (head.hasPrefix(tag) && !head.contains("]]")) { return ("", nil) }
        }
        return (text, nil)
    }

    private static let markerRegex = try! NSRegularExpression(pattern: #"\A\s*\[\[\s*问题\s*[:：]\s*([^\]\n]+?)\s*\]\][ \t]*\n?"#)

    /// 改正后的问题和原话差得太少（只差标点、空格、大小写）就当没改，卡上不出「听成」
    public static func isMeaningfulFix(heard: String, fixed: String) -> Bool {
        func norm(_ s: String) -> String {
            s.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation && !"？?！!。，,.、：:；;「」\"'".contains($0) }
        }
        return norm(heard) != norm(fixed)
    }
}

/// 一问里只报一次改正后的问题（流式每来一段都会解析一遍）
final class AskHeardFix: @unchecked Sendable {
    private let lock = NSLock()
    private var reported = false

    func markReported() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if reported { return false }
        reported = true
        return true
    }
}
