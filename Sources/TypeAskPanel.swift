import AppKit
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 打字问 AI 的输入框（design/panels 方向 A）：和回答卡同宽、同圆角、同底色的一条，左边键盘图标，
/// 贴在右上角（回答卡在屏上时贴在它下面）。
/// 不激活 App：输入时原来的 App 还在前台，回车或 Esc 收起后键盘直接回到原来的窗口。
final class TypeAskPanel: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private var panel: InputPanel?
    private let field = NSTextField()
    private let tint = NSView()
    private static let width: CGFloat = AnswerPanel.width
    private static let height: CGFloat = 48
    private static let margin: CGFloat = 12
    private static let gap: CGFloat = 8

    var isVisible: Bool { panel?.isVisible ?? false }

    /// anchor：回答面板此刻的位置；有就贴在它下面，没有就占右上角（回答面板一会儿出现的地方）
    func show(placeholder: String, below anchor: NSRect?) {
        if panel == nil { createPanel() }
        guard let panel else { return }
        let appearance = MainWindowAppearance.resolve()
        panel.appearance = appearance
        // 深浅跟「设置 → 外观」走：layer 的颜色不会自己跟着变，每次弹出按当前外观取一次
        appearance.performAsCurrentDrawingAppearance {
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            tint.layer?.backgroundColor = (dark ? NSColor(srgbRed: 22 / 255, green: 23 / 255, blue: 26 / 255, alpha: 0.94)
                                                : NSColor(srgbRed: 250 / 255, green: 250 / 255, blue: 251 / 255, alpha: 0.94)).cgColor
        }
        field.stringValue = ""
        field.placeholderString = placeholder
        let size = NSSize(width: Self.width, height: Self.height)
        let origin: NSPoint
        if let anchor {
            origin = NSPoint(x: anchor.maxX - size.width, y: anchor.minY - Self.gap - size.height)
        } else {
            let vf = Self.screenUnderMouse().visibleFrame
            origin = NSPoint(x: vf.maxX - size.width - Self.margin, y: vf.maxY - size.height - Self.margin)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    /// 收起，不回调（提问已经换成别的方式发起了）
    func dismiss() {
        panel?.orderOut(nil)
    }

    private func submit() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        dismiss()
        onSubmit?(text)
    }

    private func cancel() {
        dismiss()
        onCancel?()
    }

    // MARK: NSTextFieldDelegate

    /// 输入法选字时的回车由输入法吃掉，到不了这里，不会把拼音半截发出去
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            submit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    // MARK: NSWindowDelegate

    /// 点到别处：还没打字就当作不问了；打了字留着，回来接着写
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, field.stringValue.isEmpty else { return }
        cancel()
    }

    // MARK: 私有

    private func createPanel() {
        let bounds = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let effect = NSVisualEffectView(frame: bounds)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: AnswerPanel.cornerRadius)

        // 和回答卡一样在磨砂上垫一层近实心的底色（Theme.bg），复杂背景下字也清楚
        tint.frame = bounds
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        effect.addSubview(tint)

        let bar = NSImageView(image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) ?? NSImage())
        bar.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        bar.contentTintColor = .secondaryLabelColor

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.setAccessibilityLabel("打字问 AI")

        let hint = NSTextField(labelWithString: "↩ 发送 · esc 取消")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .tertiaryLabelColor
        hint.setContentCompressionResistancePriority(.required, for: .horizontal)

        for view in [bar, field, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            bar.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 10),
            field.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            hint.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 10),
            hint.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            hint.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])

        let p = InputPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.contentView = effect
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        ScreenShareHiding.register(p)
        panel = p
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// 无边框面板默认当不了 key window，不能打字
private final class InputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
