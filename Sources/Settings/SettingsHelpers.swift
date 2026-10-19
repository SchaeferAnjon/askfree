import Cocoa
import Combine
import AudioToolbox
import AVFoundation
import ApplicationServices
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension SettingsWindowController {
    // MARK: - Reusable helpers

    func pageHeader(eyebrow: String, title: String, sub: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        let eyebrowLbl = label(eyebrow, size: 11, weight: .medium, color: theme.text3)
        let titleLbl = label(title, size: 28, weight: .semibold, color: theme.text)
        let subLbl = label(sub, size: 13, weight: .regular, color: theme.text2)
        subLbl.maximumNumberOfLines = 0
        stack.addArrangedSubview(eyebrowLbl)
        stack.addArrangedSubview(titleLbl)
        stack.addArrangedSubview(subLbl)
        stack.setCustomSpacing(2, after: eyebrowLbl)
        stack.setCustomSpacing(6, after: titleLbl)
        return stack
    }

    func sectionTitle(_ text: String) -> NSView {
        let lbl = label(text, size: 12, weight: .semibold, color: theme.text2)
        return lbl
    }

    func makeCard() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 12
        v.layer?.borderWidth = 1
        v.layer?.setAppearanceBorder(theme.sep)
        v.layer?.setAppearanceBackground(theme.card)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    func mount(_ body: NSView, in card: NSView) {
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            body.topAnchor.constraint(equalTo: card.topAnchor),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
    }

    func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.isSelectable = false
        l.alignment = .left
        l.lineBreakMode = .byWordWrapping
        return l
    }

    /// 「标题 + 说明 + 右侧控件」这类行的横向约束：文字列吃掉控件以外的全部宽度，控件按自身宽度靠右。
    /// 折行标签的 preferredMaxLayoutWidth 是 0，固有宽度取的是上一次布局给它的宽度。以前文字列和空白占位的
    /// 拥抱优先级都是 250，谁被拉宽不确定：页面在窗口没定宽时重建（切回 App 触发），标签先被排窄一次，
    /// 之后就拿这个窄宽度当固有宽度，多出来的空间全给了占位，说明被挤成一条窄列。
    /// 这里去掉占位，把标签宽度钉死在文字列上，文字列最低拥抱、控件最高拥抱和抗压，结果和建的时机无关。
    func layoutTextColumn(_ textStack: NSStackView, beside control: NSView) {
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for case let text as NSTextField in textStack.arrangedSubviews {
            text.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            text.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        }
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func monoFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    func circle(color: NSColor, size: CGFloat) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.setAppearanceBackground(color)
        v.layer?.cornerRadius = size / 2
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: size),
            v.heightAnchor.constraint(equalToConstant: size),
        ])
        return v
    }

    func makeTextField(_ value: String?, mono: Bool = false) -> NSTextField {
        let f = NSTextField()
        f.stringValue = value ?? ""
        if mono {
            f.font = monoFont(size: 12, weight: .regular)
        }
        return f
    }

    func makeSecureField(_ value: String?) -> NSSecureTextField {
        let f = NSSecureTextField()
        f.stringValue = value ?? ""
        return f
    }

    func showAlert(title: String, message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "好")
        a.runModal()
    }
}
