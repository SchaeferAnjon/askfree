import AppKit
import AskFreeCore
import SwiftUI

/// 回答正文：段落、小标题、条目照原来的排法（不含公式和代码块的回答和原来逐像素一样），
/// 再加代码块（语言名、复制、着色、长行横向滚）和公式（行内嵌在字里，独立的单独一行）。
/// streaming：流式出字中，没收尾的公式、还没写完的围栏行先不显示（规则在 AnswerBlocks）。
/// 高度都能同步量出来（没有异步出图、没有 WebView），面板离屏测高照旧；新视图里一个动画都不加
public struct AnswerBody: View, Equatable {
    public let markdown: String
    public let streaming: Bool
    public let style: AnswerStyle

    public init(markdown: String, streaming: Bool, style: AnswerStyle) {
        self.markdown = markdown
        self.streaming = streaming
        self.style = style
    }

    public var body: some View {
        let blocks = BlockCache.blocks(markdown, streaming: streaming)
        let content = VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                BlockView(block: block, first: index == 0, style: style).equatable()
            }
        }
        .foregroundStyle(style.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        if style.selectable {
            content.textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } else {
            content
        }
    }
}

/// 拆块结果按 (markdown, streaming) 缓存最近 8 条：屏上和离屏测高两份视图、反复重画都用同一份
@MainActor
enum BlockCache {
    private struct Key: Hashable { let markdown: String; let streaming: Bool }
    private static var entries: [(Key, [AnswerBlock])] = []

    static func resetCache() { entries.removeAll() }

    static func blocks(_ markdown: String, streaming: Bool) -> [AnswerBlock] {
        let key = Key(markdown: markdown, streaming: streaming)
        if let hit = entries.first(where: { $0.0 == key }) { return hit.1 }
        // 还没收尾的那块不占位置：它总是最后一块，去掉它不影响前面各块的序号
        let blocks = AnswerBlocks.parse(markdown, streaming: streaming).filter { $0 != .pending }
        entries.append((key, blocks))
        if entries.count > 8 { entries.removeFirst() }
        return blocks
    }
}

/// 一块。Equatable：流式时前面的块不变，SwiftUI 不重算它们，只有最后一块在长
struct BlockView: View, Equatable {
    let block: AnswerBlock
    let first: Bool
    let style: AnswerStyle

    var body: some View {
        let font = Font.system(size: style.bodySize)
        switch block {
        case .heading(let s):
            RichText(source: s, font: .system(size: style.bodySize, weight: .semibold), lineSpacing: style.headingLineSpacing, style: style)
                .padding(.top, first ? 0 : style.headingTopPadding)
        case .paragraph(let s):
            RichText(source: s, font: font, lineSpacing: style.lineSpacing, style: style)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(style.text3).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                RichText(source: s, font: font, lineSpacing: style.lineSpacing, style: style)
            }
            .padding(.leading, 3)
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n).font(font).foregroundStyle(style.text2).monospacedDigit()
                    .frame(minWidth: 18, alignment: .trailing)
                RichText(source: s, font: font, lineSpacing: style.lineSpacing, style: style)
            }
        case .code(let language, let code, let attached):
            CodeBlockView(language: language, code: code, style: style)
                .padding(.leading, AnswerStyle.indent(attached))
        case .math(let tex, let attached):
            DisplayMathView(tex: tex, style: style)
                .padding(.leading, AnswerStyle.indent(attached))
        case .pending:
            EmptyView()
        }
    }
}

/// 独立公式：左对齐，跟着条目时缩进；上下各留 4，高度固定为图高 + 8；比栏宽的横向滚。排不出来的显示源码
struct DisplayMathView: View {
    let tex: String
    let style: AnswerStyle

    var body: some View {
        if let glyph = MathGlyphs.glyph(tex, display: true, size: style.mathSize) {
            DisplayGlyph(glyph: glyph)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("公式")
                .accessibilityValue(TeXFlatten.plain(tex))
        } else {
            Text(tex)
                .font(.system(size: style.codeSize, design: .monospaced))
                .foregroundStyle(style.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("公式")
                .accessibilityValue(tex)
        }
    }
}

/// 一张单独成行的公式图：放得下就直接放；放不下进横向 ScrollView（只有这时才有内层滚动）
struct DisplayGlyph: View {
    let glyph: MathGlyph
    /// 跟在公式后面的标点（从段落里拆出来的宽行内公式才有）
    var trailing = ""
    var font: Font = .body

    /// 公式图；带标点时图和标点拼成一行字（标点落在公式的基线上）
    @ViewBuilder private var content: some View {
        if trailing.isEmpty {
            Image(nsImage: glyph.image).renderingMode(.template)
                .padding(.vertical, 4)
                .frame(height: glyph.size.height + 8)
        } else {
            (Text(Image(nsImage: glyph.image).renderingMode(.template)).baselineOffset(-glyph.descent) + Text(trailing).font(font))
                .fixedSize()
                .padding(.vertical, 4)
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content
            // 高度等于内容；系统设成「始终显示滚动条」时 SwiftUI 自己给横向滚动条多留一条高度（实测 57 → 72），公式不被盖住
            ScrollView(.horizontal, showsIndicators: true) { content }
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 测试用：清掉拆块、行内、着色、公式四份缓存（量冷启动）
@MainActor
enum AnswerRenderCaches {
    static func reset(keepGlyphs: Bool = false) {
        BlockCache.resetCache()
        InlineText.resetCache()
        CodeHighlighter.resetCache()
        if !keepGlyphs { MathGlyphs.resetCache() }
    }
}
