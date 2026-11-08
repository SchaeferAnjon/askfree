import AppKit
import SwiftUI
#if canImport(AskFreeCore)
import AskFreeCore
#endif

/// 开发版带 -demoData（或 -freshData）启动时，在那个目录里放一个 command.txt，App 每 0.25 秒看一眼，一行一条命令，执行完删掉文件，
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
///   history-changed   通知「历史变了」（实测时从外面改 history.jsonl 来模拟删历史，再发这条让笔记页重新读）
///   size <宽> <高>    把主窗口改成这么大（截很长的一页用）
///   wait <秒>         后面的命令等这么久再执行
///   composer <文字>   历史详情底下的输入框：给它光标、打进这些字、按回车（走和真按回车一样的那条路）
///   panel-outside-click  当作在回答面板外面按了一下鼠标
///   panel-mouse in|out|real  回答面板认为鼠标在里面 / 外面 / 回到看真的鼠标
///   panel-state       写出回答面板：在不在屏上、钉住、一直展开、缩成小框、尺寸
///   demo-stream [noimages] [fast]  回答面板放一段假的流式回答（fast：面板一弹出就出字，不等它滑进来）（出字到四分之一时来三张图），不调模型；
///                     期间每帧记面板高度，答完写一行 panel heights 到日志和 command.out：出字期间缩过几次、方向换过几次
extension AppDelegate {
    func installDevCommands() {
        guard AppIdentity.isDevBuild, let directory = AppIdentity.demoDataDirectory ?? AppIdentity.freshDataDirectory else { return }
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
            case "history-changed":
                NotificationCenter.default.post(name: .askFreeHistoryDidChange, object: nil)
                result = "posted"
            case "size":
                let n = argument.split(separator: " ").compactMap { Double($0) }
                if n.count == 2, let window = MainActor.assumeIsolated({ SettingsWindowController.shared?.window }) {
                    window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - n[1], width: n[0], height: n[1]), display: true)
                    result = "size \(Int(window.frame.width))x\(Int(window.frame.height))"
                }
            case "scrolls":
                var lines: [String] = []
                func visit(_ v: NSView) {
                    if let sv = v as? NSScrollView { lines.append("scroll doc=\(Int(sv.documentView?.frame.height ?? 0)) visibleY=\(Int(sv.documentVisibleRect.minY)) h=\(Int(sv.documentVisibleRect.height))") }
                    v.subviews.forEach(visit)
                }
                for w in NSApp.windows where w.isVisible { lines.append("window \(w.title) occluded=\(!w.occlusionState.contains(.visible)) key=\(w.isKeyWindow)"); if let c = w.contentView { visit(c) } }
                result = lines.joined(separator: "\n")
            case "panel":
                if let panel = Self.devSavePanel() { result = "name=\(panel.nameFieldStringValue) dir=\(panel.directoryURL?.path ?? "-")" } else { result = "no panel" }
            case "accept-panel", "cancel-panel":
                result = Self.devClickPanelButton(accept: command == "accept-panel")
            case "composer":
                result = Self.devTypeInComposer(argument)
            case "panel-outside-click":
                self.answerPanel.handleOutsideClick()
                result = "clicked"
            case "panel-mouse":
                self.answerPanel.devMouseInside = argument == "in" ? true : argument == "out" ? false : nil
                result = "mouse \(argument)"
            case "panel-state":
                let m = self.answerPanel.model
                let size = self.answerPanel.frame.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-"
                // 面板在不在屏幕里：右边缘对不对得上它所在那块屏幕的可见区（应在可见区右缘往里 12）
                let onScreen = self.answerPanel.frame.map { f in
                    let screen = NSScreen.screens.first { $0.frame.intersects(f) } ?? NSScreen.main
                    return "x=\(Int(f.minX)) maxX=\(Int(f.maxX)) screenMaxX=\(Int(screen?.visibleFrame.maxX ?? 0))"
                } ?? "-"
                result = "visible=\(self.answerPanel.isVisible) pinned=\(m.pinned) keepExpanded=\(m.keepExpanded) collapsed=\(m.collapsed) size=\(size) \(onScreen)"
            case "demo-stream":
                self.devDemoStream(withImages: !argument.contains("noimages"), firstTextAfter: argument.contains("fast") ? 0.05 : 0.8,
                                   directory: directory) { summary in
                    let existing = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
                    try? (existing + "## demo-stream done\n\(summary)\n").write(to: output, atomically: true, encoding: .utf8)
                }
                result = "started"
            default: result = "unknown command"
            }
            self.debugLog("Dev command: \(line) → \(result.split(separator: "\n").first.map(String.init) ?? "")")
            let existing = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
            try? (existing + "## \(line)\n\(result)\n").write(to: output, atomically: true, encoding: .utf8)
        }
        timer.resume()
        devCommandTimer = timer
    }

    // MARK: 假的流式回答（看面板跳不跳）

    private static let demoAnswer = """
    `np.exp()` 就是 NumPy 版的「e 的几次方」：给它一个数，返回 e 的那么多次方；给它一个数组，就对每个元素各算一次。

    ```python
    np.exp(1)
    # 2.718281828459045
    ```

    **为什么不直接用 math.exp**

    Python 自带的 `math.exp` 一次只能处理一个数，传数组进去会直接报错。而 sigmoid 的输入 z 在课程里可能是单个样本的标量、一批样本的列向量，也可能是一个 m 维的行向量；你不想为每种情况写一个循环。`np.exp` 对单个数字和数组都能处理，这类「对整个数组一次性做运算」的写法叫向量化，是 NumPy 最核心的价值。

    **放到 sigmoid 里看**

    z = 0 时是 0.5；z 越大越贴近 1；z 越负越贴近 0。代码就是一个式子：

    ```python
    def sigmoid(z):
        return 1 / (1 + np.exp(-z))
    ```

    这里有个坑提前告诉你：当 z 是个很大的负数（比如 -1000）时，-z 变成 1000，`np.exp(1000)` 直接溢出成 inf，于是 1/(1+inf) 得到 0，结果还算对；但如果你写的顺序不小心，就会出现 inf/inf = nan。numpy 会抛一句 RuntimeWarning: overflow encountered in exp，很多人第一次跑作业就被这句话吓到，其实结果是 0 没错。

    还有一个容易混的点：`np.exp` 的底数永远是 e ≈ 2.718，不是 10。要算 10 的 x 次方得用 `np.power(10, x)` 或 `10**x`。
    """

    func devDemoStream(withImages: Bool, firstTextAfter: TimeInterval, directory: URL, done: @escaping (String) -> Void) {
        let panel = answerPanel
        let text = Self.demoAnswer
        let images = withImages ? Self.devDemoImages(in: directory) : []
        var heights: [Int] = []
        var streamingEnd = 0   // 出字结束那一刻 heights 有几项：之前的算「出字期间」
        let sampler = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            guard let h = panel.frame?.height, panel.isVisible else { return }
            let v = Int(h.rounded())
            if heights.last != v { heights.append(v) }
        }
        RunLoop.main.add(sampler, forMode: .common)
        panel.startThread(question: "讲一下这个方式")
        // fast：和真提问一样，面板刚弹出就挂上截图那类东西、马上重排一次（这里用一行小灰字代替）
        if firstTextAfter < 0.5 { panel.setNote("正在看屏幕…") }
        var sent = 0
        var imagesSent = false
        func step() {
            guard sent < text.count else {
                streamingEnd = heights.count
                panel.finish(answer: text)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    sampler.invalidate()
                    let during = Array(heights.prefix(streamingEnd))
                    let shrinks = zip(during, during.dropFirst()).filter { $1 < $0 }.count
                    let deltas = zip(heights, heights.dropFirst()).map { $1 - $0 }.filter { $0 != 0 }
                    let flips = zip(deltas, deltas.dropFirst()).filter { ($0 > 0) != ($1 > 0) }.count
                    let summary = "panel heights=\(heights.map(String.init).joined(separator: ",")) shrinks-while-streaming=\(shrinks) direction-flips=\(flips) images=\(images.count)"
                    self.debugLog("Dev demo-stream: \(summary)")
                    done(summary)
                }
                return
            }
            sent = min(text.count, sent + 5)
            panel.updatePartial(String(text.prefix(sent)))
            if !images.isEmpty, !imagesSent, sent >= text.count / 4 {
                imagesSent = true
                panel.setImages(images)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { step() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + firstTextAfter) { step() }
    }

    /// 三张本地小图（file:// 地址，AsyncImage 直接读），当成联网找到的图
    private static func devDemoImages(in directory: URL) -> [AskImage] {
        let colors: [NSColor] = [.systemTeal, .systemOrange, .systemIndigo]
        return colors.enumerated().compactMap { index, color in
            let url = directory.appendingPathComponent("demo-image-\(index).png")
            if !FileManager.default.fileExists(atPath: url.path) {
                let image = NSImage(size: NSSize(width: 240, height: 320), flipped: false) { rect in
                    color.setFill(); rect.fill(); return true
                }
                guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return nil }
                try? png.write(to: url)
            }
            return AskImage(thumb: url.absoluteString, full: url.absoluteString, pageURL: url.absoluteString,
                            title: "demo \(index)", width: 240, height: 320)
        }
    }

    static func devTypeInComposer(_ text: String) -> String {
        func find(_ view: NSView) -> ComposerTextView.FocusTextView? {
            if let tv = view as? ComposerTextView.FocusTextView { return tv }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        for window in NSApp.windows where window.isVisible {
            guard let content = window.contentView, let textView = find(content) else { continue }
            window.makeFirstResponder(textView)
            textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            return "typed \(text.count) chars + return"
        }
        return "no composer"
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

    /// 存储面板的按钮在系统的远程视图里，进程里点不到：用窗口结束这张面板，带上和「存储」「取消」一样的返回值，
    /// 面板的回调（笔记页拿文件路径往下走）就和用户点了按钮时一样
    static func devClickPanelButton(accept: Bool) -> String {
        guard let panel = devSavePanel() else { return "no panel" }
        if let parent = NSApp.windows.first(where: { $0.attachedSheet === panel }) {
            parent.endSheet(panel, returnCode: accept ? .OK : .cancel)
            return accept ? "sheet ended OK" : "sheet ended cancel"
        }
        return "panel is not a sheet"
    }
}

private extension Array where Element == String {
    func splitHead() -> (String, String) { (first ?? "", count > 1 ? self[1] : "") }
}
