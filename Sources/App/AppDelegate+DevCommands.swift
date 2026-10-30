import AppKit
import SwiftUI
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 开发版带 -demoData 启动时，在那个目录里放一个 command.txt，App 每 0.25 秒看一眼，一行一条命令，执行完删掉文件，
/// 结果写进 command.out。给没人看着的实测用（屏幕锁着、不能发鼠标键盘）：不走鼠标，而是在 App 自己的进程里
/// 走一遍无障碍树，按名字找到控件、执行和旁白一样的「按下」，所以按下去走的是控件真正的响应；点击的命中区域这里测不到。
/// 命令：
///   press <名字>      找无障碍名字（或标题）完全等于它的控件，按下；找不到写 not found
///   press~ <开头>     同上，名字以这几个字开头也算
///   find <片段>       列出名字里含这段字的控件
///   dump              列出所有有名字的控件
///   panel             写出当前存储面板的文件名和文件夹
///   accept-panel      点存储面板的默认按钮（「存储」）
///   cancel-panel      点存储面板的「取消」
///   wait <秒>         后面的命令等这么久再执行
extension AppDelegate {
    func installDevCommands() {
        guard AppIdentity.isDevBuild, let directory = AppIdentity.demoDataDirectory else { return }
        let input = directory.appendingPathComponent("command.txt")
        let output = directory.appendingPathComponent("command.out")
        let timer = DispatchSource.makeTimerSource(queue: .main)
        var queue: [String] = []
        var waitUntil = Date.distantPast
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            if let text = try? String(contentsOf: input, encoding: .utf8) {
                try? FileManager.default.removeItem(at: input)
                queue += text.split(separator: "\n").map(String.init)
            }
            guard Date() >= waitUntil, !queue.isEmpty, let self else { return }
            let line = queue.removeFirst().trimmingCharacters(in: .whitespaces)
            let (command, argument) = line.split(separator: " ", maxSplits: 1).map(String.init).splitHead()
            var result = ""
            switch command {
            case "wait": waitUntil = Date().addingTimeInterval(Double(argument) ?? 1); result = "waiting"
            case "press": result = Self.devPress(argument)
            case "press~": result = Self.devPress(argument, prefix: true)
            case "find": result = Self.devLabels().filter { $0.contains(argument) }.joined(separator: "\n")
            case "dump": result = Self.devLabels().joined(separator: "\n")
            case "panel":
                if let panel = Self.devSavePanel() { result = "name=\(panel.nameFieldStringValue) dir=\(panel.directoryURL?.path ?? "-")" } else { result = "no panel" }
            case "accept-panel", "cancel-panel":
                result = Self.devClickPanelButton(accept: command == "accept-panel")
            default: result = "unknown command"
            }
            self.debugLog("Dev command: \(line) → \(result.split(separator: "\n").first.map(String.init) ?? "")")
            let existing = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
            try? (existing + "## \(line)\n\(result)\n").write(to: output, atomically: true, encoding: .utf8)
        }
        timer.resume()
        devCommandTimer = timer
    }

    // MARK: 无障碍树（进程内）

    /// SwiftUI 的无障碍节点（AccessibilityNode）不声明遵守 NSAccessibilityProtocol，但会回应这些方法：按选择器问
    private static func ask(_ object: NSObject, _ selector: String) -> Any? {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel) else { return nil }
        return object.perform(sel)?.takeUnretainedValue()
    }

    private static func children(of node: NSObject) -> [NSObject] {
        (ask(node, "accessibilityChildren") as? [Any])?.compactMap { $0 as? NSObject } ?? []
    }

    private static func name(of node: NSObject) -> String {
        let label = ask(node, "accessibilityLabel") as? String ?? ""
        return label.isEmpty ? (ask(node, "accessibilityTitle") as? String ?? "") : label
    }

    private static func role(of node: NSObject) -> String {
        (ask(node, "accessibilityRole") as? String) ?? ""
    }

    private static func walk(_ node: NSObject, depth: Int = 0, visit: (NSObject) -> Bool) -> Bool {
        guard depth < 80 else { return false }
        if visit(node) { return true }
        for child in children(of: node) where walk(child, depth: depth + 1, visit: visit) { return true }
        return false
    }

    /// 窗口自己的无障碍孩子里没有 SwiftUI 的控件，要从内容视图（NSHostingView）往下走；存储面板、弹窗同理
    private static func roots() -> [NSObject] {
        NSApp.windows.filter(\.isVisible).flatMap { window -> [NSObject] in
            [window.contentView, window.attachedSheet?.contentView].compactMap { $0 }
        }
    }

    static func devLabels() -> [String] {
        var out: [String] = []
        for root in roots() {
            _ = walk(root) { node in
                let n = name(of: node)
                if !n.isEmpty { out.append("\(role(of: node)) | \(n)") }
                return false
            }
        }
        return out
    }

    static func devPress(_ label: String, prefix: Bool = false) -> String {
        let pressable: Set<String> = ["AXButton", "AXCheckBox", "AXMenuButton", "AXRadioButton", "AXPopUpButton"]
        for root in roots() {
            if walk(root, visit: { node in
                guard prefix ? name(of: node).hasPrefix(label) : name(of: node) == label, pressable.contains(role(of: node)),
                      node.responds(to: NSSelectorFromString("accessibilityPerformPress")) else { return false }
                _ = node.perform(NSSelectorFromString("accessibilityPerformPress"))
                return true
            }) { return "pressed" }
        }
        return "not found"
    }

    static func devSavePanel() -> NSSavePanel? {
        for window in NSApp.windows {
            if let panel = window as? NSSavePanel { return panel }
            if let sheet = window.attachedSheet as? NSSavePanel { return sheet }
        }
        return nil
    }

    static func devClickPanelButton(accept: Bool) -> String {
        guard let panel = devSavePanel() else { return "no panel" }
        var found: NSButton?
        func search(_ view: NSView) {
            for sub in view.subviews {
                if let b = sub as? NSButton, found == nil, accept ? b.keyEquivalent == "\r" : b.keyEquivalent == "\u{1b}" { found = b }
                search(sub)
            }
        }
        if let content = panel.contentView { search(content) }
        guard let button = found else { return "button not found" }
        button.performClick(nil)
        return "clicked \(button.title)"
    }
}

private extension Array where Element == String {
    func splitHead() -> (String, String) { (first ?? "", count > 1 ? self[1] : "") }
}
