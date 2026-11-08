import AppKit
import SwiftUI
#if canImport(AskFreeCore)
import AskFreeCore
#endif
#if canImport(AnswerRender)
import AnswerRender
#endif

/// 历史详情最底下的输入条（design/history-chat 方向 A）：跟正文同宽、左对齐，一行起、打多了往上长、最多 5 行；
/// 右边方的墨黑发送键，没字时变淡，正在答时换成「停下」；下面一行灰字。回车发送，⇧回车换行。
struct HistoryComposer: View {
    let thread: AskHistoryThread
    @ObservedObject var chat: HistoryChat
    @State private var text = ""
    @State private var height: CGFloat = ComposerTextView.lineHeight
    @State private var focused = false

    private var answeringHere: Bool { chat.isBusy && chat.isPending(in: thread.id) }
    private var answeringElsewhere: Bool { chat.isBusy && !chat.isPending(in: thread.id) }
    private var canSend: Bool { !chat.isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                ComposerTextView(text: $text, height: $height, focused: $focused, onSubmit: send)
                    .frame(height: height)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("接着问这一条…").font(.system(size: 13.5)).foregroundStyle(Theme.text3)
                                .padding(.top, 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.vertical, 4)
                Button(action: answeringHere ? { chat.stop() } : send) {
                    Image(systemName: answeringHere ? "stop.fill" : "arrow.up")
                        .font(.system(size: answeringHere ? 10 : 13, weight: .semibold))
                        .foregroundStyle(Theme.onInk)
                        .frame(width: 28, height: 28)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 6))
                        .opacity(answeringHere || canSend ? 1 : 0.25)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!(answeringHere || canSend))
                .help(answeringHere ? "停下，已经出来的留着" : "发送（回车）")
                .accessibilityLabel(answeringHere ? "停下" : "发送")
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .padding(.vertical, 3)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Theme.ink : Theme.borderStrong, lineWidth: 1))
            HStack(spacing: 12) {
                if answeringElsewhere {
                    Text("另一条还在回答，答完再问")
                } else {
                    Text("回车发送，⇧回车换行")
                    Text("接着上面的问答聊，不看屏幕")
                }
            }
            .font(.system(size: 12)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
        .overlay(alignment: .top) { Hairline() }
    }

    private func send() {
        guard canSend else { return }
        chat.send(text, in: thread)
        text = ""
    }
}

/// 输入框本体：系统文本视图。中文输入法选字时按回车只上屏、不发送（选字时回车交给输入法，走不到 insertNewline）
struct ComposerTextView: NSViewRepresentable {
    static let font = NSFont.systemFont(ofSize: 13.5)
    static let lineHeight: CGFloat = 20
    static let maxLines: CGFloat = 5

    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var focused: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let textView = FocusTextView()
        textView.onFocus = { [weak coordinator = context.coordinator] in coordinator?.setFocused($0) }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textColor = NSColor(Theme.text)
        textView.insertionPointColor = NSColor(Theme.ink)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: Self.font, .foregroundColor: NSColor(Theme.text), .paragraphStyle: paragraph]
        textView.setAccessibilityLabel("接着问这一条")
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        context.coordinator.measure(textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        init(_ parent: ComposerTextView) { self.parent = parent }

        func setFocused(_ on: Bool) {
            DispatchQueue.main.async { if self.parent.focused != on { self.parent.focused = on } }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            measure(textView)
        }

        /// 回车发送；⇧回车、⌥回车换行
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }

        /// 按内容的行数定高：一行 20，最多 5 行，再多就在框里滚
        func measure(_ textView: NSTextView) {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let used = max(layout.usedRect(for: container).height, ComposerTextView.lineHeight)
            let target = min(used, ComposerTextView.lineHeight * ComposerTextView.maxLines)
            DispatchQueue.main.async { if abs(self.parent.height - target) > 0.5 { self.parent.height = target } }
        }
    }

    /// 告诉输入条自己有没有光标（有光标时框描成墨黑）
    final class FocusTextView: NSTextView {
        var onFocus: ((Bool) -> Void)?
        override func becomeFirstResponder() -> Bool {
            let ok = super.becomeFirstResponder()
            if ok { onFocus?(true) }
            return ok
        }
        override func resignFirstResponder() -> Bool {
            let ok = super.resignFirstResponder()
            if ok { onFocus?(false) }
            return ok
        }
    }
}

/// 正在问的这一轮：和历史里的追问一个样子；还没出字时一行「在想…」，没答成时是报错卡
struct HistoryPendingTurn: View {
    let pending: HistoryChat.Pending
    let thread: AskHistoryThread
    @ObservedObject var chat: HistoryChat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left").font(.system(size: 10))
                    Text("追问 · \(HistoryFormat.time(pending.at))")
                }
                .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                Text(pending.question).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
            if let failure = pending.failure {
                HistoryFailureCard(failure: failure, provider: chat.providerName) { chat.perform($0, in: thread) }
            } else if pending.answer.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(pending.note ?? "在想…").font(.system(size: 13)).foregroundStyle(Theme.text2)
                }
            } else {
                AnswerBody(markdown: pending.answer, streaming: true, style: .history).equatable()
                    .environment(\.openURL, .answerLink)
            }
        }
    }
}

/// 没答成：和笔记页的报错卡同一个样子，按钮照报错给（重试、去填 Key、订阅会员……）
private struct HistoryFailureCard: View {
    let failure: AskFailure
    let provider: String
    let onAction: (AskFailure.Action) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: failure.symbol).font(.system(size: 15)).foregroundStyle(Theme.text2)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(failure.title(provider: provider)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(failure.detail(provider: provider)).font(.system(size: 13)).foregroundStyle(Theme.text2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                let actions = failure.actions.filter { $0.action != .typeInstead }
                if !actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { i, item in
                            Button(item.title) { onAction(item.action) }
                                .buttonStyle(NotesSmallButtonStyle(solid: i == 0, outlined: i != 0))
                        }
                    }
                    .padding(.top, 9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5))
    }
}
