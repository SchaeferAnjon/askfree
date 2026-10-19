import Cocoa
#if canImport(AskFreeCore)
import AskFreeCore
#endif

extension SettingsWindowController {
    // MARK: - Page: About

    func buildAbout(into stack: NSStackView) {
        stack.addArrangedSubview(pageHeader(eyebrow: "ASK FREE / 关于", title: "关于",
                                             sub: "按一个键说出问题，AI 看着你的屏幕回答。"))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        // Logo card
        let card = makeCard()

        let logoBox = makeWaveformMark(box: 64, corner: 16, boxColor: theme.accent, waveColor: theme.onAccent)

        let name = label("Ask Free", size: 22, weight: .semibold, color: theme.text)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "本地开发版"
        let sub = label("\(version) · macOS 状态栏应用", size: 13, weight: .regular, color: theme.text3)

        let logoStack = NSStackView()
        logoStack.orientation = .vertical
        logoStack.alignment = .centerX
        logoStack.spacing = 12
        logoStack.edgeInsets = NSEdgeInsets(top: 28, left: 16, bottom: 28, right: 16)
        logoStack.addArrangedSubview(logoBox)
        logoStack.addArrangedSubview(name)
        logoStack.addArrangedSubview(sub)
        logoStack.setCustomSpacing(4, after: name)

        // GPL-3.0：说明出处，给源码入口
        let note = label("开源软件 · GPL-3.0 · 基于 Typefree（kdsz001/typefree）修改",
                         size: 12, weight: .regular, color: theme.text3)
        note.alignment = .center
        note.maximumNumberOfLines = 0
        logoStack.addArrangedSubview(note)
        logoStack.setCustomSpacing(12, after: sub)

        let sourceButton = VPButton(title: "查看源码", style: .secondary, size: .regular,
                                    theme: theme, target: self, action: #selector(openSourceCode(_:)))
        sourceButton.translatesAutoresizingMaskIntoConstraints = false
        sourceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
        logoStack.addArrangedSubview(sourceButton)
        logoStack.setCustomSpacing(14, after: note)

        mount(logoStack, in: card)
        stack.addArrangedSubview(card)
    }

    @objc private func openSourceCode(_ sender: NSButton) {
        guard let url = URL(string: AppLinks.sourceCodeURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
