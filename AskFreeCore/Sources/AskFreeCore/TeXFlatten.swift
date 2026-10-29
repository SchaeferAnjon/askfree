import Foundation

/// TeX 公式写成普通字符：折起来的旧一轮、上个话题、历史左栏的摘要和 VoiceOver 读法用。
/// 例：`x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}` → `x=(−b±√(b²−4ac))/(2a)`。不追求排版，只求读得懂
public enum TeXFlatten {
    public static func plain(_ tex: String) -> String {
        var parser = Parser(Array(tex))
        let out = parser.sequence(untilBrace: false, text: false)
        return collapseSpaces(out)
    }

    // MARK: - 对照表

    static let symbols: [String: String] = [
        // 希腊字母
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ",
        "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ",
        "phi": "ϕ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ",
        "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // 关系
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡", "sim": "∼",
        "simeq": "≃", "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫", "mid": "|", "parallel": "∥", "perp": "⊥",
        // 运算
        "pm": "±", "mp": "∓", "times": "×", "div": "÷", "cdot": "·", "ast": "∗", "star": "⋆", "circ": "∘", "bullet": "•",
        "oplus": "⊕", "otimes": "⊗", "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮",
        "partial": "∂", "nabla": "∇", "infty": "∞",
        // 箭头
        "to": "→", "rightarrow": "→", "leftarrow": "←", "gets": "←", "leftrightarrow": "↔", "Rightarrow": "⇒",
        "Leftarrow": "⇐", "Leftrightarrow": "⇔", "implies": "⇒", "iff": "⇔", "mapsto": "↦", "uparrow": "↑", "downarrow": "↓",
        "longrightarrow": "⟶", "Longrightarrow": "⟹",
        // 集合、逻辑
        "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "supseteq": "⊇", "cup": "∪",
        "cap": "∩", "emptyset": "∅", "varnothing": "∅", "forall": "∀", "exists": "∃", "neg": "¬", "lnot": "¬",
        "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨", "setminus": "∖",
        // 点、括号、其他
        "ldots": "…", "dots": "…", "cdots": "⋯", "vdots": "⋮", "ddots": "⋱", "hbar": "ℏ", "ell": "ℓ", "angle": "∠",
        "degree": "°", "prime": "′", "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉",
        "vert": "|", "lvert": "|", "rvert": "|", "Vert": "‖", "lVert": "‖", "rVert": "‖", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ",
        "triangle": "△", "square": "□", "checkmark": "✓",
    ]

    /// 函数名：去掉反斜杠
    static let functions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "log", "ln", "lg", "exp",
        "lim", "liminf", "limsup", "max", "min", "sup", "inf", "det", "arg", "deg", "dim", "gcd", "lcm", "ker", "Pr", "mod", "bmod",
    ]

    /// 只留里面的字
    static let wrappers: Set<String> = [
        "mathrm", "mathbf", "mathit", "mathsf", "mathtt", "boldsymbol", "bm", "operatorname", "mathcal", "mathscr", "mathfrak",
        "boxed", "textbf", "textit", "textrm", "emph", "underline", "overline", "displaystyle",
    ]
    static let textWrappers: Set<String> = ["text", "textnormal", "mbox", "textrm", "textbf", "textit"]

    /// 去掉的命令（后面不带参数）
    static let dropped: Set<String> = [
        "left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr", "displaystyle",
        "textstyle", "scriptstyle", "limits", "nolimits", "nonumber", "notag", "quad", "qquad",
    ]

    static let blackboard: [Character: String] = [
        "R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ", "H": "ℍ", "E": "𝔼",
    ]

    static let accents: [String: String] = [
        "hat": "\u{0302}", "widehat": "\u{0302}", "bar": "\u{0304}", "vec": "\u{20D7}", "dot": "\u{0307}", "ddot": "\u{0308}",
        "tilde": "\u{0303}", "widetilde": "\u{0303}", "overrightarrow": "\u{20D7}",
    ]

    static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "j": "ʲ", "k": "ᵏ", "l": "ˡ",
        "m": "ᵐ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
        "T": "ᵀ", "A": "ᴬ", "B": "ᴮ", "D": "ᴰ", "E": "ᴱ", "G": "ᴳ", "H": "ᴴ", "I": "ᴵ", "J": "ᴶ", "K": "ᴷ", "L": "ᴸ",
        "M": "ᴹ", "N": "ᴺ", "O": "ᴼ", "P": "ᴾ", "R": "ᴿ", "U": "ᵁ", "V": "ⱽ", "W": "ᵂ",
        // 本来就写在右上角的
        "′": "′", "*": "*", "†": "†", "∗": "∗",
    ]

    static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ",
        "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ", "β": "ᵦ", "γ": "ᵧ", "ρ": "ᵨ", "φ": "ᵩ", "χ": "ᵪ",
    ]

    // MARK: - 解析

    private struct Parser {
        let s: [Character]
        var i = 0
        init(_ s: [Character]) { self.s = s }

        /// 读到 } 或末尾为止。text：\text{} 里面，减号不换、空格照留
        mutating func sequence(untilBrace: Bool, text: Bool) -> String {
            var out = ""
            while i < s.count {
                let c = s[i]
                if c == "}" {
                    if untilBrace { i += 1; return out }
                    i += 1
                    continue
                }
                if text {
                    if c == "{" { i += 1; out += sequence(untilBrace: true, text: true); continue }
                    if c == "\\" { out += command(text: true); continue }
                    out.append(c); i += 1
                    continue
                }
                switch c {
                case "{":
                    i += 1
                    out += sequence(untilBrace: true, text: false)
                case "\\":
                    out += command(text: false)
                case "^", "_":
                    i += 1
                    let arg = argument()
                    out += script(arg, sup: c == "^")
                case "&":
                    i += 1
                    out += " "
                case "-":
                    i += 1
                    out += "−"
                case "~":
                    i += 1
                    out += " "
                case " ", "\n", "\t":
                    // 公式里的空白照 TeX 不算数：a\neq 0 和 a\neq0 写出来一样
                    i += 1
                default:
                    out.append(c)
                    i += 1
                }
            }
            return out
        }

        /// 下一个参数：{…} 一组，或一个命令，或一个字
        mutating func argument() -> String {
            while i < s.count, s[i] == " " { i += 1 }
            guard i < s.count else { return "" }
            if s[i] == "{" { i += 1; return sequence(untilBrace: true, text: false) }
            if s[i] == "\\" { return command(text: false) }
            let c = s[i]
            i += 1
            return c == "-" ? "−" : String(c)
        }

        /// 原样读一组 {…} 里的字（环境名、颜色名）
        mutating func rawGroup() -> String {
            while i < s.count, s[i] == " " { i += 1 }
            guard i < s.count, s[i] == "{" else { return "" }
            i += 1
            var depth = 1
            var out = ""
            while i < s.count {
                let c = s[i]
                i += 1
                if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { break } }
                out.append(c)
            }
            return out
        }

        mutating func textGroup() -> String {
            while i < s.count, s[i] == " " { i += 1 }
            guard i < s.count, s[i] == "{" else { return "" }
            i += 1
            return sequence(untilBrace: true, text: true)
        }

        /// s[i] 是反斜杠
        mutating func command(text: Bool) -> String {
            i += 1
            guard i < s.count else { return "" }
            let first = s[i]
            if !first.isLetter {
                i += 1
                switch first {
                case "\\": return text ? " " : "; "
                case ",", "!", ">", ":": return ""
                case ";", " ": return " "
                case "{", "}", "%", "$", "&", "#", "_": return String(first)
                case "|": return "‖"
                default: return String(first)
                }
            }
            var name = ""
            while i < s.count, s[i].isLetter, s[i].isASCII { name.append(s[i]); i += 1 }
            if text {
                if TeXFlatten.textWrappers.contains(name) { return textGroup() }
                return TeXFlatten.symbols[name] ?? name
            }
            switch name {
            case "frac", "dfrac", "tfrac", "cfrac":
                let num = argument(), den = argument()
                let fraction = wrap(num) + "/" + wrap(den)
                // 分数后面紧跟字母、数字或括号（\frac{b}{a}x）：整个括起来，免得读成 b/(ax)
                return followedByOperand() ? "(" + fraction + ")" : fraction
            case "sqrt":
                var index = ""
                if i < s.count, s[i] == "[" {
                    i += 1
                    while i < s.count, s[i] != "]" { index.append(s[i]); i += 1 }
                    i += 1
                }
                let body = argument()
                let prefix = index.isEmpty ? "" : script(index, sup: true)
                return prefix + "√" + (isAtomic(body) ? body : "(" + body + ")")
            case "begin":
                let env = rawGroup()
                if env.hasSuffix("matrix") { return env.hasPrefix("b") ? "[" : env.hasPrefix("v") ? "|" : env.hasPrefix("p") ? "(" : "" }
                if env == "cases" { return "{" }
                return ""
            case "end":
                let env = rawGroup()
                if env.hasSuffix("matrix") { return env.hasPrefix("b") ? "]" : env.hasPrefix("v") ? "|" : env.hasPrefix("p") ? ")" : "" }
                return ""
            case "mathbb":
                let body = argument()
                return body.map { TeXFlatten.blackboard[$0] ?? String($0) }.joined()
            case "color":
                _ = rawGroup()
                return ""
            case "textcolor":
                _ = rawGroup()
                return argument()
            case "tag":
                if i < s.count, s[i] == "*" { i += 1 }
                _ = rawGroup()
                return ""
            case "not":
                return "¬"
            default:
                break
            }
            if TeXFlatten.textWrappers.contains(name) { return textGroup() }
            if TeXFlatten.wrappers.contains(name) {
                if name == "displaystyle" { return "" }
                return argument()
            }
            if let mark = TeXFlatten.accents[name] { return argument() + mark }
            if TeXFlatten.dropped.contains(name) {
                if name == "quad" || name == "qquad" { return " " }
                if name == "left" || name == "right" || name.hasPrefix("big") || name.hasPrefix("Big") {
                    // \left. 是看不见的定界符
                    if i < s.count, s[i] == "." { i += 1 }
                }
                return ""
            }
            if let sym = TeXFlatten.symbols[name] { return sym }
            if TeXFlatten.functions.contains(name) {
                // sin x、log n：后面紧跟字母或数字时空一格
                var j = i
                while j < s.count, s[j] == " " { j += 1 }
                if j < s.count, s[j].isLetter || s[j].isNumber || s[j] == "\\" { return name + " " }
                return name
            }
            return name   // 不认的命令：去掉反斜杠
        }

        /// 后面（跳过空白）紧跟的是字母、数字、括号，或者会写成字母的命令（希腊字母、函数名）
        func followedByOperand() -> Bool {
            var j = i
            while j < s.count, s[j] == " " { j += 1 }
            guard j < s.count else { return false }
            let c = s[j]
            if c.isLetter || c.isNumber || c == "(" { return true }
            guard c == "\\" else { return false }
            var name = ""
            var k = j + 1
            while k < s.count, s[k].isLetter, s[k].isASCII { name.append(s[k]); k += 1 }
            if TeXFlatten.functions.contains(name) { return true }
            return TeXFlatten.symbols[name]?.first?.isLetter == true
        }

        func script(_ arg: String, sup: Bool) -> String {
            let table = sup ? TeXFlatten.superscripts : TeXFlatten.subscripts
            // 只留字和字之间的空格：lim_(x→0)、_(n terms)
            let a = Array(TeXFlatten.collapseSpaces(arg))
            var tight = ""
            for (k, c) in a.enumerated() {
                if c == " ", k > 0, k + 1 < a.count, !(a[k - 1].isLetter && a[k + 1].isLetter) { continue }
                tight.append(c)
            }
            guard !tight.isEmpty else { return "" }
            if tight.allSatisfy({ table[$0] != nil }) { return String(tight.map { table[$0]! }) }
            let mark = sup ? "^" : "_"
            return tight.count == 1 ? mark + tight : mark + "(" + tight + ")"
        }

        /// 分子分母：一个数、一个字（可以带上下标）、或已经括起来的，不加括号；别的都加
        func wrap(_ part: String) -> String {
            isAtomic(part) ? part : "(" + part + ")"
        }

        func isAtomic(_ part: String) -> Bool {
            let p = Array(part)
            guard !p.isEmpty else { return true }
            if p.allSatisfy({ $0.isNumber || $0 == "." }) { return true }
            // √x、√(…)：根号连着它管的那一块算一个
            if p[0] == "√", p.count > 1 { return isAtomic(String(p.dropFirst())) }
            let scripts = Set(TeXFlatten.superscripts.values).union(TeXFlatten.subscripts.values)
            if p.dropFirst().allSatisfy({ scripts.contains($0) }) && !"+−±=<>≤≥/·×, ".contains(p[0]) { return true }
            if let open = p.first, let close = p.last, (open == "(" && close == ")") || (open == "[" && close == "]") {
                // 整个括起来：括号要配得上（(a)(b) 不算）
                var depth = 0
                for (k, c) in p.enumerated() {
                    if c == open { depth += 1 } else if c == close { depth -= 1 }
                    if depth == 0 && k < p.count - 1 { return false }
                }
                return true
            }
            return false
        }
    }

    static func collapseSpaces(_ s: String) -> String {
        var out = ""
        var lastSpace = false
        for c in s {
            if c == " " || c == "\n" || c == "\t" {
                if !lastSpace && !out.isEmpty { out.append(" ") }
                lastSpace = true
            } else {
                out.append(c)
                lastSpace = false
            }
        }
        // 分号前、括号里侧不留空格：「( 4 1 ; 2 3 )」→「(4 1; 2 3)」
        for (a, b) in [(" ;", ";"), ("( ", "("), (" )", ")"), ("[ ", "["), (" ]", "]")] { out = out.replacingOccurrences(of: a, with: b) }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
    }
}
