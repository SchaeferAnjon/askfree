import AppKit
import AskFreeCore
import SwiftUI

/// 一段行内源码做成 Text：加粗、行内代码、链接走系统的行内 Markdown，公式换成嵌在字里的模板图（跟字一个颜色）。
/// 公式源码从头到尾不经过 Markdown：每条公式先换成一个私用区占位字（U+E000 起），整段交给 AttributedString(markdown:)，
/// 再按占位字拆开、把图放回去。跨过公式的 **加粗** 不会断开，公式里的 \%、\\、*、_ 也不会被吃掉。
/// 两处绕开 SwiftUI Text 的毛病（task-lue8s 设计评审 6、2）：
/// - 公式图后面不许折行（图后面跟一个 U+2060，紧跟着的空格换成不折行空格）：图后面就是折行点、行宽又刚好卡在某个范围时，
///   SwiftUI 量出来是两行、画的时候只画第一行加「…」，下面空一大块。U+2060 每张图后面都跟（后面的字还没来也跟），
///   流式出字时这一行的高度不会因为后面来了字而变
/// - 往下挪图的那一小段字用 1 点的字号：baselineOffset 会把这一段字自己的字框也挪下去算进行高，用正文字号时每条带下沉的公式让行高多出 4 点
@MainActor
enum InlineText {
    /// 行内公式排出来比这宽，就单独成一行（多轮时栏宽 338 的六成左右），不然一行字被它撑得很难看
    static let wideMathWidth: CGFloat = 200
    static let cacheLimit = 256

    enum Part {
        case text(Text)
        /// 太宽的行内公式、带矩阵和 cases 这类环境的行内公式：照独立公式的样子单独一行（不把一行字撑得很高）；
        /// 紧跟着的标点（「，」「.」）跟它留在同一行，不落到下一行行首
        case wideMath(MathGlyph, trailing: String)
    }

    struct Rendered {
        var parts: [Part]
        /// 含公式时整段的读法（公式部分换成普通字符），给 VoiceOver；不含公式是 nil
        var spoken: String?
    }

    private struct Key: Hashable {
        let source: String
        let style: AnswerStyle
    }
    private static var cache: [Key: Rendered] = [:]
    private static var order: [Key] = []

    static func resetCache() { cache.removeAll(); order.removeAll() }

    static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "。", "，", "、", "；", "：", "！", "？", "）", "」", "』", "”", "’"]

    static func render(_ source: String, style: AnswerStyle) -> Rendered {
        let key = Key(source: source, style: style)
        if let hit = cache[key] { return hit }
        let made = make(source, style: style)
        cache[key] = made
        order.append(key)
        if order.count > cacheLimit { cache.removeValue(forKey: order.removeFirst()) }
        return made
    }

    private static func make(_ source: String, style: AnswerStyle) -> Rendered {
        // 空的（流式时条目后面的字还没来）：留一行字的高度，字来了不跳
        if source.isEmpty { return Rendered(parts: [.text(Text(" "))], spoken: nil) }
        let pieces = AnswerBlocks.inline(source)
        var maths: [String] = []
        var marked = ""
        for piece in pieces {
            switch piece {
            case .text(let t): marked += t
            case .math(let tex):
                marked.unicodeScalars.append(Unicode.Scalar(0xE000 + UInt32(min(maths.count, 0x18FF)))!)
                maths.append(tex)
            }
        }
        let parsed = markdown(marked)
        // 没有公式：和原来一模一样（不含 * 和反引号、或解析不了时就是 Text(String)）
        guard !maths.isEmpty else {
            return Rendered(parts: [.text(parsed.map { Text($0) } ?? Text(marked))], spoken: nil)
        }
        let attributed = parsed ?? AttributedString(marked)

        var parts: [Part] = []
        var current: Text?
        var spoken = ""
        /// 上一样是嵌在字里的公式图：接下来的字开头不许折行
        var glue = false
        func append(_ t: Text) { current = current.map { $0 + t } ?? t }
        func appendText(_ piece: AttributedSubstring) {
            var text = AttributedString(piece)
            if glue { text = Self.glued(text) }
            glue = false
            append(Text(text))
        }
        func flush() { if let c = current { parts.append(.text(c)); current = nil }; glue = false }

        let chars = attributed.characters
        var segmentStart = attributed.startIndex
        var i = attributed.startIndex
        while i < attributed.endIndex {
            let ch = chars[i]
            let next = chars.index(after: i)
            guard let first = ch.unicodeScalars.first, (0xE000...0xF8FF).contains(first.value) else {
                spoken.append(ch)
                i = next
                continue
            }
            if segmentStart < i { appendText(attributed[segmentStart..<i]) }
            let k = Int(first.value - 0xE000)
            let tex = k < maths.count ? maths[k] : ""
            let glyph = MathGlyphs.glyph(tex, display: false, size: style.mathSize)
            spoken += TeXFlatten.plain(tex)
            if let glyph {
                if glyph.size.width > wideMathWidth || tex.contains("\\begin{") {
                    flush()
                    var trailing = ""
                    var j = next
                    while j < attributed.endIndex, trailing.count < 3, Self.trailingPunctuation.contains(chars[j]) {
                        trailing.append(chars[j])
                        j = chars.index(after: j)
                    }
                    while j < attributed.endIndex, chars[j] == " " { j = chars.index(after: j) }
                    spoken += trailing
                    parts.append(.wideMath(glyph, trailing: trailing))
                    i = j
                    segmentStart = j
                    continue
                } else {
                    append(Text(Image(nsImage: glyph.image).renderingMode(.template)).font(.system(size: 1)).baselineOffset(-glyph.descent)
                        + Text("\u{2060}"))
                    glue = true
                }
            } else {
                // 排不出来：显示源码（去掉分隔符），等宽、次要色
                append(Text(tex).font(.system(size: style.codeSize, design: .monospaced)).foregroundStyle(style.text2))
                glue = false
            }
            i = next
            segmentStart = next
        }
        if segmentStart < attributed.endIndex { appendText(attributed[segmentStart..<attributed.endIndex]) }
        flush()
        if parts.isEmpty { parts = [.text(Text(""))] }
        return Rendered(parts: parts, spoken: spoken)
    }

    /// 公式图后面那段字开头的空格换成不折行空格（U+2060 已经跟在图后面）
    static func glued(_ text: AttributedString) -> AttributedString {
        guard text.characters.first == " " else { return text }
        var out = text
        out.characters.replaceSubrange(out.startIndex..<out.characters.index(after: out.startIndex), with: "\u{00A0}")
        return out
    }

    /// 行内 Markdown（含 *、反引号、链接的 [ 和 <、反斜杠转义才解析，解析不了按纯文本），再把不是 https 的链接去掉，只留字。
    /// 不含这些记号的字不解析：和原来的面板逐像素一样
    static func markdown(_ s: String) -> AttributedString? {
        guard s.contains(where: { "*`[<\\".contains($0) }),
              var attributed = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return nil
        }
        stripUnsafeLinks(&attributed)
        return attributed
    }

    /// 回答里的链接只留 https（ExternalLink 放行的）；javascript:、file:、http:、mailto:、data: 一律去掉链接，只留字
    static func stripUnsafeLinks(_ attributed: inout AttributedString) {
        var unsafe: [Range<AttributedString.Index>] = []
        for run in attributed.runs {
            guard let url = run.link else { continue }
            if url.scheme?.lowercased() != "https" || !ExternalLink.isAllowed(url) { unsafe.append(run.range) }
        }
        for range in unsafe { attributed[range].link = nil }
    }
}

/// 一段正文：通常就是一个 Text；有太宽的行内公式时拆成上下几段
struct RichText: View {
    let source: String
    let font: Font
    let lineSpacing: CGFloat
    let style: AnswerStyle

    var body: some View {
        let rendered = InlineText.render(source, style: style)
        if rendered.parts.count == 1, case .text(let text) = rendered.parts[0] {
            if let spoken = rendered.spoken {
                text.font(font).lineSpacing(lineSpacing).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(spoken)
            } else {
                text.font(font).lineSpacing(lineSpacing).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rendered.parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let text):
                        text.font(font).lineSpacing(lineSpacing).fixedSize(horizontal: false, vertical: true)
                    case .wideMath(let glyph, let trailing):
                        DisplayGlyph(glyph: glyph, trailing: trailing, font: font)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rendered.spoken ?? "")
        }
    }
}
