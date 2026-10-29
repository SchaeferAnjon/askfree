import AppKit
import SwiftUI
import XCTest
@testable import AnswerRender
@testable import AskFreeCore

/// 不含公式、不含代码块的回答：新排版和原来的 AnswerText 逐像素一样（task-lue8s §12.2）
@MainActor
final class LegacyParityTests: XCTestCase {
    /// 2026-10-29 之前 AnswerPanel.swift 里的 AnswerText 原样抄过来，Theme 换成同值的 TestTheme
    struct LegacyAnswerText: View {
        let text: String
        private let body14 = Font.system(size: 14)

        private enum Block { case heading(String), paragraph(String), bullet(String), numbered(String, String) }

        private var blocks: [Block] {
            var out: [Block] = []
            var para: [String] = []
            func flush() {
                if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para.removeAll() }
            }
            for raw in text.components(separatedBy: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { flush(); continue }
                if line.hasPrefix("#") {
                    flush()
                    let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty { out.append(.heading(title)) }
                    continue
                }
                if let r = line.range(of: #"^(?:[-•·*]|\d+[.、)）])\s+"#, options: .regularExpression) {
                    flush()
                    let marker = String(line[r.lowerBound..<r.upperBound]).trimmingCharacters(in: .whitespaces)
                    let body = String(line[r.upperBound...])
                    if marker.first?.isNumber == true {
                        let num = marker.trimmingCharacters(in: CharacterSet(charactersIn: ".、)）")) + "."
                        out.append(.numbered(num, body))
                    } else {
                        out.append(.bullet(body))
                    }
                } else {
                    para.append(line)
                }
            }
            flush()
            return out
        }

        private func inline(_ s: String) -> Text {
            if s.contains("*") || s.contains("`"),
               let attr = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                return Text(attr)
            }
            return Text(s)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .heading(let s):
                        inline(s).font(.system(size: 14, weight: .semibold))
                            .padding(.top, index == 0 ? 0 : 6)
                            .fixedSize(horizontal: false, vertical: true)
                    case .paragraph(let s):
                        inline(s).font(body14).lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    case .bullet(let s):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(TestTheme.text3).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                            inline(s).font(body14).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 3)
                    case .numbered(let n, let s):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(n).font(body14).foregroundStyle(TestTheme.text2).monospacedDigit()
                                .frame(minWidth: 18, alignment: .trailing)
                            inline(s).font(body14).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .foregroundStyle(TestTheme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct Card<Content: View>: View {
        let width: CGFloat
        @ViewBuilder let content: Content
        var body: some View {
            content.frame(width: width, alignment: .leading).padding(16).background(TestTheme.bg)
        }
    }

    static let handwritten = [
        "### 小标题\n\n先说结论：**加粗**和 `ls -a` 都在。\n\n- 圆点一\n- 圆点二，带 **重点**\n\n1. 编号一\n2. 编号二\n10. 编号十\n\n链接 [文档](https://developer.apple.com/documentation) 和 *斜体*。",
        "第一行\n同一段第二行\n\n## 另一个标题\n\n• 中文圆点 `code`\n3） 中文括号编号\n\n最后一段很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长。",
    ]

    func testPlainAnswersRenderPixelIdentical() throws {
        let fixtures = Fixtures.sampleNames.filter { $0.hasSuffix("__current") }.map(Fixtures.answer).filter { !$0.contains("$") && !$0.contains("```") && !$0.contains("\\(") && !$0.contains("\\[") }
        XCTAssertGreaterThanOrEqual(fixtures.count, 5, "要有 5 条不含公式的 __current 回答")
        let answers = Array(fixtures.prefix(5)) + Self.handwritten
        var compared = 0
        for (i, md) in answers.enumerated() {
            for width: CGFloat in [368, 338] {
                for dark in [false, true] {
                    let old = Offscreen.host(Card(width: width) { LegacyAnswerText(text: md) }, dark: dark)
                    let oldRep = Offscreen.bitmap(old)
                    let oldSize = old.fittingSize
                    let new = Offscreen.host(Card(width: width) { AnswerBody(markdown: md, streaming: false, style: TestTheme.panel) }, dark: dark)
                    let newRep = Offscreen.bitmap(new)
                    XCTAssertEqual(new.fittingSize, oldSize, "answer \(i) width \(width) dark \(dark)")
                    XCTAssertEqual(newRep.pixelsWide, oldRep.pixelsWide)
                    XCTAssertEqual(newRep.pixelsHigh, oldRep.pixelsHigh)
                    let same = newRep.tiffRepresentation == oldRep.tiffRepresentation || Self.pixelsEqual(newRep, oldRep)
                    XCTAssertTrue(same, "answer \(i) width \(width) dark \(dark) 逐像素不同")
                    compared += 1
                }
            }
        }
        XCTAssertEqual(compared, 28)
        // 比较本身是灵的：行距差 1 点就认得出来
        var off = TestTheme.panel
        off.lineSpacing = 6
        let a = Offscreen.bitmap(Offscreen.host(Card(width: 368) { LegacyAnswerText(text: Self.handwritten[1]) }, dark: false))
        let b = Offscreen.bitmap(Offscreen.host(Card(width: 368) { AnswerBody(markdown: Self.handwritten[1], streaming: false, style: off) }, dark: false))
        XCTAssertFalse(a.pixelsHigh == b.pixelsHigh && Self.pixelsEqual(a, b))
    }

    static func pixelsEqual(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Bool {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return false }
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide where a.colorAt(x: x, y: y) != b.colorAt(x: x, y: y) { return false }
        }
        return true
    }
}
