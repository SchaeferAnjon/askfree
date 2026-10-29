import AppKit
import SwiftUI

/// 代码块：左上语言名、右上「复制」，下面一条发丝线；代码等宽 12.5、行距 3、四周留 12，长行不折行、横向滚，
/// 高度等于内容（长代码靠外层面板滚）。底色、描边由 AnswerStyle 给（Theme.hover / Theme.border，8 圆角）
struct CodeBlockView: View {
    let language: String
    let code: String
    let style: AnswerStyle
    @State private var copied = false
    @State private var hovering = false
    @State private var resetWork: DispatchWorkItem?

    var body: some View {
        // 制表符显示成 4 个空格，复制时还是制表符；没内容时留一行字的高度，第一行代码来了不跳
        let shown = code.isEmpty ? " " : code.replacingOccurrences(of: "\t", with: "    ")
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "代码" : language)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style.text2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: copy) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                        Text(copied ? "已复制" : "复制")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(hovering ? style.text : style.text2)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help("复制代码")
                .accessibilityLabel("复制代码")
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            Rectangle().fill(style.codeBorder).frame(height: 1)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(CodeHighlighter.highlight(shown, language: language))
                    .font(.system(size: style.codeSize, design: .monospaced))
                    .lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }
            // 高度等于内容；「始终显示滚动条」时 SwiftUI 自己给横向滚动条多留一条高度，不盖住最后一行
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(style.codeBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style.codeBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.isEmpty ? "代码块" : "代码块，\(language)")
    }

    private func copy() {
        Self.copy(code, to: .general)
        copied = true
        resetWork?.cancel()
        let work = DispatchWorkItem { copied = false }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// 只写纯文字一种类型：块里的代码（围栏和语言名不带、缩进已去掉、制表符保留、末尾不带换行）
    static func copy(_ code: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }
}

/// 给测试和 App 用：按代码块的规则复制（和点「复制」写进剪贴板的一样）
public enum AnswerCodeCopy {
    @MainActor public static func copy(_ code: String, to pasteboard: NSPasteboard = .general) {
        CodeBlockView.copy(code, to: pasteboard)
    }
}
