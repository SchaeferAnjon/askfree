import AppKit
import SwiftUI
import XCTest
@testable import AnswerRender
@testable import AskFreeCore

/// 只在设了 ASKFREE_RENDER_OUT=<目录> 时跑：每条 fixture 出浅色、深色 × 368、338、616 三种宽度的 PNG，
/// 再加 4 张出字中途的。不进 CI 断言，出图给人看
@MainActor
final class RenderGalleryTests: XCTestCase {
    private var outDir: URL? {
        ProcessInfo.processInfo.environment["ASKFREE_RENDER_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func testGallery() throws {
        guard let outDir else { throw XCTSkip("设 ASKFREE_RENDER_OUT 才出图") }
        let only = ProcessInfo.processInfo.environment["ASKFREE_RENDER_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        var names = Fixtures.sampleNames + ["long-mixed"]
        if let only { names = names.filter { only.contains($0) } }
        var extras: [(String, String)] = [("malicious", Fixtures.text("malicious.md")), ("extra-formulas", Self.extraAnswer()), ("wide", Self.wideAnswer)]
        if let only { extras = extras.filter { only.contains($0.0) } }
        for (name, md) in names.map({ ($0, Fixtures.answer($0)) }) + extras {
            for dark in [false, true] {
                for width: CGFloat in [368, 338, 616] {
                    let style = width == 616 ? TestTheme.history : TestTheme.panel
                    let h = Offscreen.host(PanelCard(markdown: md, width: width, style: style), dark: dark)
                    try Offscreen.writePNG(Offscreen.bitmap(h), to: outDir.appendingPathComponent("\(name)-\(Int(width))-\(dark ? "dark" : "light").png"))
                }
            }
        }
        guard only == nil || only!.contains("mid") else { return }
        // 出字中途：$$ 开了没收、围栏开了没收、行内 $ 开了没收、代码长到一半
        let q1 = Fixtures.answer("q1_quadratic_zh__dollar")
        let c1 = Fixtures.answer("c1_python_zh__latex")
        let cuts: [(String, String)] = [
            ("mid-display-open", String(q1[..<q1.range(of: "$$x^2+\\frac{b}{a}x+\\frac")!.upperBound])),
            ("mid-fence-open", String(c1[..<c1.range(of: "```pyth")!.upperBound])),
            ("mid-inline-open", String(q1[..<q1.range(of: "（$a\\ne")!.upperBound])),
            ("mid-code-half", String(c1[..<c1.range(of: "result = df.groupby(\"cat")!.upperBound])),
        ]
        for (name, prefix) in cuts {
            for dark in [false, true] {
                let h = Offscreen.host(PanelCard(markdown: prefix, streaming: true), dark: dark)
                try Offscreen.writePNG(Offscreen.bitmap(h), to: outDir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
                let raw = Offscreen.host(PanelCard(markdown: prefix, streaming: false), dark: dark)
                try Offscreen.writePNG(Offscreen.bitmap(raw), to: outDir.appendingPathComponent("\(name)-\(dark ? "dark" : "light")-asfinal.png"))
            }
        }
    }

    /// 比栏宽的独立公式（横向滚）、比 200 点宽的行内公式（单独成行）、跟着条目的代码块
    static let wideAnswer = """
    ### 宽的公式

    展开式：$(a+b)^n = \\binom{n}{0}a^n + \\binom{n}{1}a^{n-1}b + \\binom{n}{2}a^{n-2}b^2 + \\cdots + \\binom{n}{n}b^n$，这是二项式定理。

    $$f(x) = a_0 + a_1 x + a_2 x^2 + a_3 x^3 + a_4 x^4 + a_5 x^5 + a_6 x^6 + a_7 x^7 + a_8 x^8 + a_9 x^9 + a_{10} x^{10}$$

    1. 装依赖：
       ```bash
       pip install numpy pandas matplotlib seaborn scikit-learn --upgrade --user
       ```
    2. 跑起来：$\\text{结果} = \\frac{1}{n}\\sum_{i=1}^{n} x_i$

       $$\\bar{x} = \\frac{1}{n}\\sum_{i=1}^{n} x_i$$
    """

    /// extra.json 里的公式拼成一条回答：能排的、不能排的都看一眼
    static func extraAnswer() -> String {
        Fixtures.formulas("extra.json").map { f in f.display ? "$$\(f.tex)$$" : "行内：$\(f.tex)$ 结束。" }.joined(separator: "\n\n")
    }
}
