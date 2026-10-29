import AppKit
import SwiftUI
import XCTest
@testable import AnswerRender
@testable import AskFreeCore

/// 26 条 DeepSeek 实录回答逐段回放：每个前缀都解析、排版（task-lue8s §4.4、§12.2）
@MainActor
final class StreamingPrefixTests: XCTestCase {
    /// 每个到达时刻的前缀
    static func prefixes(_ name: String) -> [String] {
        var acc = ""
        return Fixtures.chunks(name).map { acc += $0.text; return acc }
    }

    /// 显示出来的字里有没有半截公式：没收尾的 \(、$$、\[、或者后面紧跟非数字的 $（行内代码里的不算）
    static func halfFormula(in blocks: [AnswerBlock]) -> String? {
        for block in blocks {
            let source: String
            switch block {
            case .heading(let s), .paragraph(let s), .bullet(let s), .numbered(_, let s): source = s
            default: continue
            }
            for span in AnswerBlocks.scanInline(Array(source)) where !span.isMath {
                let text = span.raw.replacingOccurrences(of: "(`+)[^`]*?\\1", with: "", options: .regularExpression)
                if text.contains("\\(") || text.contains("$$") || text.contains("\\[") { return text }
                if text.range(of: #"(?<!\\)\$(?=[^\d\s])"#, options: .regularExpression) != nil { return text }
            }
        }
        return nil
    }

    func testEveryPrefixParsesStablyWithoutHalfFormulas() {
        var total = 0
        for name in Fixtures.sampleNames {
            var previous: [AnswerBlock] = []
            for (k, prefix) in Self.prefixes(name).enumerated() {
                let blocks = AnswerBlocks.parse(prefix, streaming: true)
                total += 1
                if let half = Self.halfFormula(in: blocks) {
                    XCTFail("\(name) 第 \(k) 段露出半截公式：\(half.suffix(60))")
                }
                if previous.count > 1 {
                    for i in 0..<(previous.count - 1) {
                        guard i < blocks.count, blocks[i] == previous[i] else {
                            XCTFail("\(name) 第 \(k) 段：前面第 \(i) 块变了")
                            break
                        }
                    }
                }
                previous = blocks
            }
            // 答完的整条：公式都收了尾
            XCTAssertNil(Self.halfFormula(in: AnswerBlocks.parse(Fixtures.answer(name), streaming: false)), name)
        }
        print("streaming prefixes checked: \(total)")
        XCTAssertGreaterThan(total, 5000)
    }

    /// 流式时测出的高度从不变小（容差 0.5）
    func testStreamingHeightNeverShrinks() {
        var layouts = 0
        for name in Fixtures.sampleNames {
            let host = Offscreen.host(PanelCard(markdown: "", streaming: true), dark: false)
            var last: CGFloat = 0
            for (k, prefix) in Self.prefixes(name).enumerated() {
                host.rootView = PanelCard(markdown: prefix, streaming: true)
                host.layoutSubtreeIfNeeded()
                let h = host.fittingSize.height
                layouts += 1
                if h < last - 0.5 {
                    XCTFail("\(name) 第 \(k) 段高度从 \(last) 变成 \(h)：…\(prefix.suffix(40))")
                }
                last = max(last, h)
            }
        }
        print("streaming layouts measured: \(layouts)")
    }
}

/// 测高那份（直接放 AnswerBody）和屏上那份（放进 ScrollView）同宽时高度一样；冷缓存、热缓存一样
@MainActor
final class HeightTests: XCTestCase {
    private func scrollContentHeight(_ markdown: String, width: CGFloat, style: AnswerStyle) -> CGFloat {
        let view = ScrollView(.vertical) { PanelCard(markdown: markdown, width: width, style: style) }
            .frame(width: width + 32, height: 500)
        let host = Offscreen.host(view, dark: false)
        host.frame = NSRect(x: 0, y: 0, width: width + 32, height: 500)
        Offscreen.window.setContentSize(host.frame.size)
        host.layoutSubtreeIfNeeded()
        guard let sv = Self.findScrollView(in: host), let doc = sv.documentView else { return -1 }
        sv.layoutSubtreeIfNeeded()
        return doc.frame.height
    }

    static func findScrollView(in view: NSView) -> NSScrollView? {
        for sub in view.subviews {
            if let sv = sub as? NSScrollView { return sv }
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }

    func testMeasuredHeightMatchesScrollViewContent() {
        let names = ["q1_quadratic_zh__dollar", "c1_python_zh__latex", "c2_swift_en__latex", "q6_matrix_en__dollar", "q5_maxwell_en__latex", "long-mixed"]
        for name in names {
            let md = Fixtures.answer(name)
            for width: CGFloat in [368, 338, 616] {
                let style = width == 616 ? TestTheme.history : TestTheme.panel
                let measured = Offscreen.fit(Offscreen.host(PanelCard(markdown: md, width: width, style: style), dark: false)).height
                let inScroll = scrollContentHeight(md, width: width, style: style)
                XCTAssertEqual(measured, inScroll, accuracy: 0.5, "\(name) @\(width)")
            }
        }
    }

    func testColdAndWarmCacheGiveSameHeight() {
        for name in ["q1_quadratic_zh__latex", "c1_python_zh__latex", "q4_bayes_en__dollar"] {
            let md = Fixtures.answer(name)
            for width: CGFloat in [368, 338, 616] {
                let style = width == 616 ? TestTheme.history : TestTheme.panel
                AnswerRenderCaches.reset()
                let cold = Offscreen.fit(Offscreen.host(PanelCard(markdown: md, width: width, style: style), dark: false)).height
                let warm = Offscreen.fit(Offscreen.host(PanelCard(markdown: md, width: width, style: style), dark: false)).height
                XCTAssertEqual(cold, warm, accuracy: 0.01, "\(name) @\(width)")
            }
        }
    }
}
