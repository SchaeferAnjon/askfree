import AppKit
import SwiftUI
import XCTest
@testable import AnswerRender
@testable import AskFreeCore

/// 深浅色：公式是模板图，跟着字色走；代码五种颜色和正文色对代码底色的对比度都够（task-lue8s §10.1）
@MainActor
final class AppearanceTests: XCTestCase {
    /// 只画一条独立公式（透明底），算有字的像素平均亮度
    private func formulaLuminance(dark: Bool) -> Double {
        let view = AnswerBody(markdown: "$$x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}$$", streaming: false, style: TestTheme.panel).frame(width: 368)
        let rep = Offscreen.bitmap(Offscreen.host(view, dark: dark))
        var sum = 0.0, n = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.8 else { continue }
                sum += 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                n += 1
            }
        }
        XCTAssertGreaterThan(n, 30, "公式画出来了") // 没接显示器（CI）位图是 1 倍，有字的像素只有 2 倍屏的一半多
        return sum / Double(max(n, 1))
    }

    func testFormulaFollowsTextColor() {
        XCTAssertLessThan(formulaLuminance(dark: false), 0.3)
        XCTAssertGreaterThan(formulaLuminance(dark: true), 0.7)
    }

    private func resolve(_ color: NSColor, dark: Bool) -> (r: Double, g: Double, b: Double, a: Double) {
        var out = (0.0, 0.0, 0.0, 0.0)
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            out = (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        }
        return out
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    func testCodeColorsContrast() {
        // 代码底色 = hover 叠在面板底（bg，面板的底是 bg 94% 不透明叠在磨砂上）、历史页底（bg）、卡片（elevated）上
        let bases: [(String, NSColor)] = [("bg", TestTheme.bgNS), ("elevated", TestTheme.elevatedNS)]
        var report: [String] = []
        for dark in [false, true] {
            for (baseName, base) in bases {
                let b = resolve(base, dark: dark), h = resolve(TestTheme.hoverNS, dark: dark)
                let bg = (r: h.r * h.a + b.r * (1 - h.a), g: h.g * h.a + b.g * (1 - h.a), b: h.b * h.a + b.b * (1 - h.a))
                var colors = CodeHighlighter.colors.map { ("\($0.key)", $0.value) }
                colors.append(("text", TestTheme.textNS))
                for (name, color) in colors {
                    let c = resolve(color, dark: dark)
                    let l1 = luminance((c.r, c.g, c.b)), l2 = luminance(bg)
                    let ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
                    report.append(String(format: "%@ %@ %@ %.2f", dark ? "dark" : "light", baseName, name, ratio))
                    // 回答的代码块放在 bg 上（面板、历史页都是）：必须 ≥ 4.5；elevated 只记下来
                    if baseName == "bg" { XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(dark ? "深色" : "浅色") \(name) 对比度 \(ratio)") }
                }
            }
        }
        print("contrast:\n" + report.joined(separator: "\n"))
    }
}

/// VoiceOver：公式读法、代码块、复制按钮（task-lue8s §10.2）
@MainActor
final class AccessibilityTests: XCTestCase {
    private struct Element { let role: String; let label: String; let value: String }

    private func collect(_ element: Any, into out: inout [Element], depth: Int = 0) {
        guard depth < 40, let el = element as? NSObject & NSAccessibilityProtocol else { return }
        let label = el.accessibilityLabel() ?? ""
        let value = (el.accessibilityValue() as? String) ?? ""
        let role = el.accessibilityRole()?.rawValue ?? ""
        out.append(Element(role: role, label: label, value: value))
        for child in el.accessibilityChildren() ?? [] { collect(child, into: &out, depth: depth + 1) }
    }

    func testFormulaCodeAndCopyButtonAreLabelled() throws {
        let md = "求根公式：\n\n$$x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}$$\n\n判别式 $\\Delta=b^2-4ac$ 决定根。\n\n```python\nprint(1)\n```"
        let host = Offscreen.host(PanelCard(markdown: md), dark: false)
        Offscreen.fit(host)
        // SwiftUI 要窗口真的在（屏幕外的位置）才建无障碍树
        Offscreen.window.orderFrontRegardless()
        defer { Offscreen.window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        var all: [Element] = []
        collect(host, into: &all)
        // 测试进程里没有辅助功能的客户端连着，SwiftUI 不建无障碍树（实测只有根节点）：这一项在真 App 里用 AX 读（task-lue8s §13.7）
        if all.count <= 1 { throw XCTSkip("离屏拿不到 SwiftUI 的无障碍树，改在真 App 里用 AX 读") }
        let formula = all.first { $0.label == "公式" }
        XCTAssertEqual(formula?.value, "x=(−b±√(b²−4ac))/(2a)")
        XCTAssertTrue(all.contains { $0.label.contains("判别式 Δ=b²−4ac 决定根") }, all.map(\.label).description)
        XCTAssertTrue(all.contains { $0.label == "代码块，python" }, all.map(\.label).description)
        XCTAssertTrue(all.contains { $0.label == "复制代码" }, all.map(\.label).description)
        XCTAssertTrue(all.contains { $0.label.contains("print(1)") || $0.value.contains("print(1)") }, "代码照常读")
    }
}

/// 代码块的「复制」：只有代码，缩进去掉、制表符保留、末尾不带换行，只写纯文字一种类型
@MainActor
final class CodeCopyTests: XCTestCase {
    func testCopyWritesOnlyTheCode() {
        let md = "1. 写个函数：\n   ```python\n   def f():\n   \treturn 1\n\n   ```\n"
        guard case .code(_, let code, _)? = AnswerBlocks.parse(md, streaming: false).last else { return XCTFail("没拆出代码块") }
        let pb = NSPasteboard(name: NSPasteboard.Name("io.github.schaeferanjon.askfree.test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        AnswerCodeCopy.copy(code, to: pb)
        XCTAssertEqual(pb.string(forType: .string), "def f():\n\treturn 1")
        // setString 只写一种（AppKit 自己会带上它的旧名字 NSStringPboardType）
        XCTAssertEqual(Set(pb.types ?? []), [.string, NSPasteboard.PasteboardType("NSStringPboardType")])
    }
}
