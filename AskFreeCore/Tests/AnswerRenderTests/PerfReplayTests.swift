import AppKit
import SwiftUI
import XCTest
@testable import AnswerRender
@testable import AskFreeCore

/// 性能（task-lue8s §11）：P1 长回答回放、P2 单条公式第一次排版、P5 历史页打开一个 2 轮数学话题。
/// 默认只断言 P1 最长 ≤ 50 ms（CI 机器快慢不一）；ASKFREE_PERF=1 时再断言 p95 ≤ 16 ms、P2、P5，并打印本机实测
@MainActor
final class PerfReplayTests: XCTestCase {
    private var strict: Bool { ProcessInfo.processInfo.environment["ASKFREE_PERF"] == "1" }

    private func stats(_ values: [Double]) -> (median: Double, p95: Double, max: Double) {
        let s = values.sorted()
        return (s[s.count / 2], s[min(s.count - 1, Int(Double(s.count) * 0.95))], s.last!)
    }

    /// fixture 符合描述：独立加行内公式不少于 10 条，代码块正好 2 个
    func testLongMixedFixtureShape() {
        let blocks = AnswerBlocks.parse(Fixtures.answer("long-mixed"), streaming: false)
        var formulas = 0, code = 0
        for block in blocks {
            switch block {
            case .math: formulas += 1
            case .code: code += 1
            case .heading(let s), .paragraph(let s), .bullet(let s), .numbered(_, let s):
                formulas += AnswerBlocks.inline(s).filter { if case .math = $0 { return true } else { return false } }.count
            case .pending: break
            }
        }
        XCTAssertGreaterThanOrEqual(formulas, 10)
        XCTAssertEqual(code, 2)
        print("long-mixed: formulas \(formulas), code blocks \(code), chunks \(Fixtures.chunks("long-mixed").count)")
    }

    /// P1：屏上（ScrollView 里，368×500）和测高两份视图每段都换 rootView、排版，再读测高那份的 fittingSize
    func testP1LongAnswerReplay() {
        AnswerRenderCaches.reset()
        let warm = MathGlyphs.warmUp()   // App 启动 1 秒后做的那次
        let measure = NSHostingView(rootView: PanelCard(markdown: "", streaming: true))
        let shown = NSHostingView(rootView: ScrollView { PanelCard(markdown: "", streaming: true) })
        shown.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        Offscreen.window.contentView = shown
        var acc = ""
        var times: [Double] = []
        for chunk in Fixtures.chunks("long-mixed") {
            acc += chunk.text
            let start = DispatchTime.now().uptimeNanoseconds
            measure.rootView = PanelCard(markdown: acc, streaming: true)
            shown.rootView = ScrollView { PanelCard(markdown: acc, streaming: true) }
            measure.layoutSubtreeIfNeeded()
            shown.layoutSubtreeIfNeeded()
            _ = measure.fittingSize
            times.append(ms(since: start))
        }
        let s = stats(times)
        print(String(format: "P1 updates %d median %.2f ms p95 %.2f ms max %.2f ms (warm-up %.1f ms)", times.count, s.median, s.p95, s.max, warm))
        XCTAssertLessThanOrEqual(s.max, 50)
        if strict {
            XCTAssertLessThanOrEqual(s.p95, 16)
        }
    }

    /// 一段像样的 Python：函数头、带字符串和数字的调用、判断、抛错、返回字典，五行一轮
    static func pythonCode(lines: Int) -> String {
        (0..<lines).map { k -> String in
            switch k % 5 {
            case 0: return "def handler_\(k)(request, *args, **kwargs):  # 处理第 \(k) 个请求"
            case 1: return "    value = compute(\"key_\(k)\", timeout=\(k).5, retries=3)"
            case 2: return "    if value is None or value == 'missing':"
            case 3: return "        raise ValueError(f\"bad value {value!r} at step \(k)\")"
            default: return "    return {\"id\": \(k), \"result\": value, \"ok\": True}"
            }
        }.joined(separator: "\n")
    }

    /// P1b：一句说明加一个 150 行的 Python 代码块，每 12 字一段回放，和 P1 一样两份视图（代码评审 1：原来 100 行 p95 155 ms、最长 176 ms）
    func testP1bLongCodeBlockReplay() {
        AnswerRenderCaches.reset()
        let md = "下面是完整的脚本：\n\n```python\n" + Self.pythonCode(lines: 150) + "\n```\n\n跑一下就行。"
        var chunks: [String] = []
        var rest = Substring(md)
        while !rest.isEmpty { chunks.append(String(rest.prefix(12))); rest = rest.dropFirst(12) }
        let measure = NSHostingView(rootView: PanelCard(markdown: "", streaming: true))
        let shown = NSHostingView(rootView: ScrollView { PanelCard(markdown: "", streaming: true) })
        shown.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        Offscreen.window.contentView = shown
        var acc = ""
        var times: [Double] = []
        for chunk in chunks {
            acc += chunk
            let start = DispatchTime.now().uptimeNanoseconds
            measure.rootView = PanelCard(markdown: acc, streaming: true)
            shown.rootView = ScrollView { PanelCard(markdown: acc, streaming: true) }
            measure.layoutSubtreeIfNeeded()
            shown.layoutSubtreeIfNeeded()
            _ = measure.fittingSize
            times.append(ms(since: start))
        }
        let s = stats(times)
        print(String(format: "P1b code 150 lines, updates %d median %.2f ms p95 %.2f ms max %.2f ms", times.count, s.median, s.p95, s.max))
        XCTAssertLessThanOrEqual(s.max, 50)
        if strict { XCTAssertLessThanOrEqual(s.p95, 10) }
    }

    /// P2：249 条公式逐条第一次排版（冷缓存，字体已预热）
    func testP2FirstTypesetPerFormula() {
        MathGlyphs.warmUp()
        AnswerRenderCaches.reset()
        var times: [Double] = []
        for f in Fixtures.formulas("formulas.json") {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = MathGlyphs.glyph(f.tex + " ", display: f.display, size: 15.5)   // 加个空格：和别的用例的缓存分开
            times.append(ms(since: start))
        }
        let s = stats(times)
        print(String(format: "P2 formulas %d median %.3f ms p95 %.3f ms max %.2f ms", times.count, s.median, s.p95, s.max))
        if strict {
            XCTAssertLessThanOrEqual(s.p95, 5)
            XCTAssertLessThanOrEqual(s.max, 16)
        }
    }

    /// P5：历史页打开一个 2 轮数学话题：离屏 616 宽，冷缓存（拆块、行内、着色、公式图全清），首次渲染。
    /// 历史页本身已经开着（右栏的 NSHostingView 已经在）：量的是换到这个话题那一下
    func testP5HistoryTwoRoundMathTopic() {
        MathGlyphs.warmUp()
        let a1 = Fixtures.answer("q1_quadratic_zh__dollar"), a2 = Fixtures.answer("q6_matrix_en__dollar")
        func topic(_ a: String, _ b: String) -> some View {
            VStack(alignment: .leading, spacing: 24) {
                AnswerBody(markdown: a, streaming: false, style: TestTheme.history)
                AnswerBody(markdown: b, streaming: false, style: TestTheme.history)
            }.frame(width: 616)
        }
        // 冷缓存量 5 次（每次先换回别的话题、清掉缓存），取中位数：单次的数抖得厉害
        var runs: [Double] = []
        var size = CGSize.zero
        for _ in 0..<5 {
            let host = NSHostingView(rootView: AnyView(topic("先开着的一个话题：**加粗** $x$", "第二轮")))
            Offscreen.window.contentView = host
            host.layoutSubtreeIfNeeded()
            _ = host.fittingSize
            AnswerRenderCaches.reset(keepGlyphs: false)
            MathGlyphs.warmUp()
            let start = DispatchTime.now().uptimeNanoseconds
            host.rootView = AnyView(topic(a1, a2))
            host.layoutSubtreeIfNeeded()
            size = host.fittingSize
            runs.append(ms(since: start))
        }
        let t = stats(runs).median
        // 其中公式排版占多少：同样两条回答里的公式再冷排一遍
        AnswerRenderCaches.reset()
        let mathStart = DispatchTime.now().uptimeNanoseconds
        var count = 0
        for md in [a1, a2] {
            for block in AnswerBlocks.parse(md, streaming: false) {
                switch block {
                case .math(let tex, _): _ = MathGlyphs.glyph(tex, display: true, size: 15); count += 1
                case .heading(let x), .paragraph(let x), .bullet(let x), .numbered(_, let x):
                    for case .math(let tex) in AnswerBlocks.inline(x) { _ = MathGlyphs.glyph(tex, display: false, size: 15); count += 1 }
                default: break
                }
            }
        }
        let mathMs = ms(since: mathStart)
        print(String(format: "P5 history 2 rounds first render median %.1f ms of 5 cold runs (%@; height %.0f; %d formulas typeset in %.1f ms)",
                     t, runs.map { String(format: "%.1f", $0) }.joined(separator: " "), size.height, count, mathMs))
        if strict { XCTAssertLessThanOrEqual(t, 30) }
    }
}
