import Foundation

/// 回答是轻量 Markdown（面板会渲染），拿到别处用纯文本。
/// 代码块外：小标题去掉 #、加粗去掉 **、行内代码去掉反引号、条目统一成「• 」/「1. 」、多余空行合并；
/// 代码块（``` 之间）里的每一行原样保留，命令和模板字符串里的反引号、缩进、** 都不动。
/// 公式：复制时连分隔符原样保留（$x^2$、$$…$$、\(…\)，里面的 *、_、` 一个不删）；预览里写成普通字符（TeXFlatten）。
/// 围栏和公式的判断和面板排版是同一套（AnswerBlocks）
public enum AnswerMarkdown {
    /// 「复制」用：``` 那一行也留着，贴到别处还是代码块；公式原样
    public static func plainText(_ md: String) -> String { convert(md, preview: false).joined(separator: "\n") }

    /// 追问时折起来的上一轮、上个话题、历史列表的摘要用：再去掉 ``` 那一行，代码去掉首尾空格；公式写成普通字符、`\$` 写成 `$`。
    /// 各段、各行用一个空格接成一段：折起来只给两三行，段落中间的空行会占掉一行、行尾也出不了「…」。
    /// 前一行以中文标点（：，。）结尾时不加空格：全角标点自己带着空，再加一个看着像空了两格
    public static func preview(_ md: String) -> String {
        previewLock.lock()
        if let hit = previewCache[md] { previewLock.unlock(); return hit }
        previewLock.unlock()
        var made = ""
        for line in convert(md, preview: true) where !line.isEmpty {
            if let last = made.last, !fullwidthPunctuation.contains(last) { made += " " }
            made += line
        }
        previewLock.lock()
        if previewCache.count >= previewCacheLimit { previewCache.removeAll() }
        previewCache[md] = made
        previewLock.unlock()
        return made
    }

    /// 折起来的旧一轮、历史列表每一行每次重画都要预览一遍：记住最近的几十条（一条带几十个公式的长回答要几毫秒）
    private static var previewCache: [String: String] = [:]
    private static let previewCacheLimit = 64
    private static let previewLock = NSLock()
    private static let fullwidthPunctuation: Set<Character> = ["，", "。", "：", "；", "！", "？", "、", "）", "」", "』", "》", "】", "…"]

    private static func convert(_ md: String, preview: Bool) -> [String] {
        var source = AnswerBlocks.splitLines(md)
        var lines: [String] = []
        var fence: AnswerBlocks.Fence?
        var i = 0
        while i < source.count {
            let raw = source[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if AnswerBlocks.isFenceClose(trimmed, count: open.count) {
                    fence = nil
                    if !preview { lines.append(raw) }
                } else if !preview {
                    lines.append(raw)
                } else if !trimmed.isEmpty {
                    lines.append(trimmed)
                }
                i += 1
                continue
            }
            if let open = AnswerBlocks.fenceOpen(trimmed) {
                fence = open
                if !preview { lines.append(raw) }
                i += 1
                continue
            }
            if let opener = AnswerBlocks.displayMathOpener(trimmed),
               case .found(let tex, let endLine, let rest) = AnswerBlocks.findDisplayMath(source, at: i, opener: opener, streaming: false) {
                if preview {
                    lines.append(TeXFlatten.plain(tex))
                    if !rest.trimmingCharacters(in: .whitespaces).isEmpty {
                        source[endLine] = rest   // 收尾符后面同一行还有字：当新的一行
                        i = endLine
                        continue
                    }
                } else {
                    for k in i...endLine { lines.append(source[k].trimmingCharacters(in: .whitespaces)) }
                }
                i = endLine + 1
                continue
            }
            var line = trimmed
            if line.hasPrefix("#") { line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            line = AnswerBlocks.scanInline(Array(line)).map { span in
                if span.isMath { return preview ? TeXFlatten.plain(span.value) : span.raw }
                // 复制留原文（\$ 照写，贴进别的 Markdown 还是普通的 $）；预览和面板显示的一样，写成 $
                return (preview ? span.value : span.raw).replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            }.joined()
            line = line.replacingOccurrences(of: #"^[-•·*]\s+"#, with: "• ", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^(\d+)[.、)）]\s+"#, with: "$1. ", options: .regularExpression)
            if line.isEmpty, lines.last?.isEmpty ?? true { i += 1; continue }   // 合并连续空行、去掉开头空行
            lines.append(line)
            i += 1
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }
}
