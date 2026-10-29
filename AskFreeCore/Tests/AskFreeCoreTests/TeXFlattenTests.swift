import XCTest
@testable import AskFreeCore

final class TeXFlattenTests: XCTestCase {
    private func flat(_ tex: String) -> String { TeXFlatten.plain(tex) }

    func testQuadraticFormula() {
        XCTAssertEqual(flat("x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}"), "x=(−b±√(b²−4ac))/(2a)")
        XCTAssertEqual(flat("x=\\dfrac{-b\\pm\\sqrt{b^2-4ac}}{2a}"), "x=(−b±√(b²−4ac))/(2a)")
    }

    func testFractionFollowedByOperandIsBracketed() {
        XCTAssertEqual(flat("x^2+\\frac{b}{a}x+\\frac{c}{a}=0"), "x²+(b/a)x+c/a=0")
        XCTAssertEqual(flat("\\frac{1}{2}\\pi r^2"), "(1/2)πr²")
        XCTAssertEqual(flat("\\pm\\frac{\\sqrt{b^2-4ac}}{2a}"), "±√(b²−4ac)/(2a)")
        XCTAssertEqual(flat("a\\neq 0, a \\pm i\\sqrt{x}"), "a≠0,a±i√x")
    }

    func testSimpleFractionsNeedNoParentheses() {
        XCTAssertEqual(flat("\\frac{1}{2}"), "1/2")
        XCTAssertEqual(flat("\\tfrac{b}{a}"), "b/a")
        XCTAssertEqual(flat("\\frac{\\pi^2}{6}"), "π²/6")
    }

    func testBayes() {
        XCTAssertEqual(flat("P(A \\mid B) = \\frac{P(B \\mid A)\\,P(A)}{P(B)}"), "P(A|B)=(P(B|A)P(A))/(P(B))")
    }

    func testMaxwell() {
        XCTAssertEqual(flat("\\nabla \\times \\mathbf{E} = -\\frac{\\partial \\mathbf{B}}{\\partial t}"), "∇×E=−(∂B)/(∂t)")
        XCTAssertEqual(flat("\\nabla \\cdot \\mathbf{E} = \\frac{\\rho}{\\varepsilon_0}"), "∇·E=ρ/ε₀")
    }

    func testMatrix() {
        XCTAssertEqual(flat("A = \\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}"), "A=(a b; c d)")
        XCTAssertEqual(flat("A^{-1} = \\frac{1}{ad-bc}\\begin{bmatrix} d & -b \\\\ -c & a \\end{bmatrix}"), "A⁻¹=1/(ad−bc)[d −b; −c a]")
    }

    func testTextKeepsWordsAndCJK() {
        XCTAssertEqual(flat("v = \\text{速度}"), "v=速度")
        XCTAssertEqual(flat("\\text{当 } x \\to 0 \\text{ 时}"), "当 x→0 时")
        XCTAssertEqual(flat("\\text{well-known}"), "well-known")
    }

    func testScriptsThatConvertAndThatDont() {
        XCTAssertEqual(flat("x^2 + y_n + e^{i\\pi}"), "x²+yₙ+e^(iπ)")
        XCTAssertEqual(flat("a_{ij} + A^T + x^{n+1}"), "aᵢⱼ+Aᵀ+xⁿ⁺¹")
        XCTAssertEqual(flat("x_{\\text{max}} + 2^q + x_{n\\text{ terms}}"), "xₘₐₓ+2^q+x_(n terms)")
    }

    func testSymbolsAndFunctions() {
        XCTAssertEqual(flat("\\alpha \\le \\beta \\neq \\gamma \\infty \\sum \\int \\hbar"), "α≤β≠γ∞∑∫ℏ")
        XCTAssertEqual(flat("\\sin x + \\log n + \\lim_{x\\to 0}"), "sin x+log n+lim_(x→0)")
        XCTAssertEqual(flat("x \\in \\mathbb{R}, \\ldots"), "x∈ℝ,…")
        XCTAssertEqual(flat("a \\Rightarrow b"), "a⇒b")
    }

    func testAccents() {
        XCTAssertEqual(flat("\\hat{H}\\psi"), "H\u{0302}ψ")
        XCTAssertEqual(flat("\\vec{F} = m\\vec{a}"), "F\u{20D7}=ma\u{20D7}")
    }

    func testSpacingAndDelimiterCommandsDropped() {
        XCTAssertEqual(flat("\\left( \\frac{b}{2a} \\right)^2"), "(b/(2a))²")
        XCTAssertEqual(flat("a\\,b\\!c\\;d\\quad e"), "abc d e")
        XCTAssertEqual(flat("\\left. x \\right|_0^1"), "x|₀¹")
    }

    func testUnknownCommandsLoseBackslash() {
        XCTAssertEqual(flat("\\foo{x} + \\xrightarrow{f}"), "foox+xrightarrowf")
        XCTAssertEqual(flat("50\\% \\{a\\}"), "50%{a}")
    }

    func testBoxedTagColorRemoved() {
        XCTAssertEqual(flat("\\boxed{E = mc^2} \\tag{1}"), "E=mc²")
        XCTAssertEqual(flat("\\color{red}{x} + \\textcolor{blue}{y}"), "x+y")
    }

    func testOddInputDoesNotCrash() {
        for s in ["", "\\", "{", "}", "^", "_", "\\frac", "\\frac{", "\\sqrt[", "\\begin{", "{{{{", "x^", "\\left", "\\text{"] {
            _ = flat(s)
        }
        _ = flat(String(repeating: "{", count: 2000))
        _ = flat(String(repeating: "\\frac{", count: 500))
    }
}

/// 构造出来的深套公式不卡主线程（task-lue8s 代码评审 5）
final class TeXFlattenCostTests: XCTestCase {
    func testDeepNestingIsCheap() {
        for n in [300, 399] {
            let tex = String(repeating: "\\sqrt", count: n) + " x"
            let start = Date()
            let out = TeXFlatten.plain(tex)
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.1, "\(n) 层根号")
            XCTAssertTrue(out.hasPrefix("√√√"))
        }
        // 超过 2000 字、括号套 40 层以上：原样给源码
        let long = String(repeating: "x+", count: 1100)
        XCTAssertEqual(TeXFlatten.plain(long), long)
        let deep = String(repeating: "{", count: 50) + "x" + String(repeating: "}", count: 50)
        XCTAssertEqual(TeXFlatten.plain(deep), deep)
        // 平常的照旧
        XCTAssertEqual(TeXFlatten.plain("\\sqrt{\\sqrt{x}}"), "√√x")
    }
}
