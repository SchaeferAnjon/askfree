import Foundation

/// 交给 SwiftMath 之前在公式源码上改几处它和 TeX 排法不一样的地方（task-lue8s 设计评审 2–4）。
/// 只改写源码、不碰它解析出的公式树：SwiftMath 把公式树写回源码时有好几处强制解包，交给它一棵改过的树会让整个 App 崩掉
enum TeXTweaks {
    /// 独立公式和行内公式都改：算子后面补细空、矩阵格子开头的负号是一元的
    static func common(_ tex: String) -> String {
        unaryAtCellStart(thinSpaceAfterOperators(tex))
    }

    /// 行内公式再改：∑、∫ 这类单字的大算子用基本字形、上下限写在右边（SwiftMath 在文本样式里换大一号的字形，一行字被撑高）
    static func inline(_ tex: String) -> String {
        baseGlyphOperators(common(tex))
    }

    // MARK: - 算子后面的细空

    /// 写成正体字的算子：后面紧跟字母、数字、希腊字母、分数、根号时，TeX 会空一个细空（3/18 em），SwiftMath 不空
    static let operatorNames: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "coth", "log", "ln", "lg", "exp",
        "det", "dim", "ker", "arg", "deg", "gcd", "lcm", "hom", "Pr", "max", "min", "sup", "inf", "lim", "liminf", "limsup",
    ]

    /// 单字的大算子和它的基本字形
    static let bigOperators: [String: String] = [
        "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "bigcup": "⋃", "bigcap": "⋂",
    ]

    /// 算子后面跟着这些命令（会排成字母一样的东西）也补细空
    static let operandCommands: Set<String> = [
        "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta", "vartheta", "iota", "kappa", "lambda", "mu",
        "nu", "xi", "pi", "varpi", "rho", "varrho", "sigma", "varsigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega",
        "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega",
        "mathrm", "mathbf", "mathit", "mathsf", "mathtt", "mathcal", "mathbb", "mathfrak", "mathscr", "boldsymbol", "bm", "text",
        "vec", "hat", "bar", "tilde", "dot", "ddot", "widehat", "widetilde", "overline", "underline",
        "frac", "dfrac", "tfrac", "cfrac", "binom", "sqrt", "partial", "nabla", "infty", "ell", "hbar", "imath", "jmath", "operatorname",
    ]

    static func thinSpaceAfterOperators(_ tex: String) -> String {
        let s = Array(tex)
        var out: [Character] = []
        out.reserveCapacity(s.count + 8)
        var i = 0
        while i < s.count {
            guard s[i] == "\\", let (name, end) = command(s, at: i) else {
                out.append(s[i])
                i += 1
                continue
            }
            if name.isEmpty {
                // \\、\$ 这类：两个字一起抄，后面的字母不当命令名
                out += s[i..<min(end, s.count)]
                i = end
                continue
            }
            let isOperator = operatorNames.contains(name) || bigOperators[name] != nil || name == "operatorname"
            guard isOperator else {
                out += s[i..<end]
                i = end
                continue
            }
            var j = end
            if name == "operatorname" {
                if j < s.count, s[j] == "*" { j += 1 }
                j = argumentEnd(s, from: j)
            }
            j = scriptsEnd(s, from: j)
            out += s[i..<j]
            if startsOperand(s, at: skipSpaces(s, from: j)) { out += ["\\", ","] }
            i = j
        }
        return String(out)
    }

    private static func startsOperand(_ s: [Character], at k: Int) -> Bool {
        guard k < s.count else { return false }
        let c = s[k]
        if c.isLetter || c.isNumber || c == "{" { return true }
        guard c == "\\", let (name, _) = command(s, at: k), !name.isEmpty else { return false }
        return operandCommands.contains(name) || operatorNames.contains(name) || bigOperators[name] != nil
    }

    // MARK: - 行内的大算子

    static func baseGlyphOperators(_ tex: String) -> String {
        let s = Array(tex)
        var out: [Character] = []
        var i = 0
        while i < s.count {
            guard s[i] == "\\", let (name, end) = command(s, at: i) else {
                out.append(s[i])
                i += 1
                continue
            }
            guard let glyph = bigOperators[name] else {
                out += s[i..<min(end, s.count)]
                i = end
                continue
            }
            // 明写了 \limits 的照它：上下限摞在上下
            let next = skipSpaces(s, from: end)
            if let (after, afterEnd) = command(s, at: next), after == "limits" || after == "nolimits" {
                if after == "limits" { out += s[i..<afterEnd] } else { out += Array("\\text{\(glyph)}") }
                i = afterEnd
                continue
            }
            out += Array("\\text{\(glyph)}")
            i = end
        }
        return String(out)
    }

    // MARK: - 矩阵格子开头的负号

    /// \begin{…} 里每一格开头（\begin 之后、& 之后、\\ 之后）的 - 和 + 换成正文里的 −、+：
    /// SwiftMath 在格子开头垫了一个样式记号，负号跟在它后面被当成二元的，「−2」排成「− 2」、列也被撑宽
    static func unaryAtCellStart(_ tex: String) -> String {
        guard tex.contains("\\begin") else { return tex }
        let s = Array(tex)
        var out: [Character] = []
        var depth = 0
        /// 正在里面的环境开在哪一层括号
        var envDepths: [Int] = []
        var cellStart = false
        var i = 0
        func atCellStart() {
            guard cellStart, !envDepths.isEmpty, envDepths.last == depth else { return }
            let k = skipSpaces(s, from: i)
            guard k < s.count, s[k] == "-" || s[k] == "+" else { return }
            out += s[i..<k]
            out += Array(s[k] == "-" ? "\\text{−}" : "\\text{+}")
            i = k + 1
        }
        while i < s.count {
            atCellStart()
            cellStart = false
            guard i < s.count else { break }
            let c = s[i]
            if c == "{" { depth += 1 } else if c == "}" { depth -= 1 }
            if c == "&" {
                out.append(c)
                i += 1
                cellStart = true
                continue
            }
            guard c == "\\", let (name, end) = command(s, at: i) else {
                out.append(c)
                i += 1
                continue
            }
            out += s[i..<min(end, s.count)]
            i = end
            switch name {
            case "begin":
                let groupEnd = argumentEnd(s, from: i)
                let env = String(s[i..<groupEnd]).trimmingCharacters(in: CharacterSet(charactersIn: " {}"))
                out += s[i..<groupEnd]
                i = groupEnd
                // array 的列格式 {cc}
                if env == "array" {
                    let specEnd = argumentEnd(s, from: i)
                    out += s[i..<specEnd]
                    i = specEnd
                }
                envDepths.append(depth)
                cellStart = true
            case "end":
                if !envDepths.isEmpty { envDepths.removeLast() }
            case "":
                // \\ 换行：后面可能跟 [2pt]
                if end - i == 0, s[end - 1] == "\\" {
                    if i < s.count, s[i] == "[", let close = s[i...].firstIndex(of: "]") {
                        out += s[i...close]
                        i = close + 1
                    }
                    cellStart = true
                }
            default:
                break
            }
        }
        return String(out)
    }

    // MARK: - 行内顶层的分数

    struct Part: Equatable {
        enum Kind: Equatable {
            case fraction
            /// 开头、末尾是二元运算符：它自己排会被当成一元的、两边的空没了，排的时候旁边垫一个「0」
            case text(padLeft: Bool, padRight: Bool)
        }
        let kind: Kind
        let tex: String
        /// 和前一段之间补的空，单位 mu（1/18 em）
        let gapBefore: CGFloat
    }

    /// 行内公式在顶层的分数处切开；没有能切的返回 nil。
    /// 顶层的 \left( … \right) 里有分数时先换成 \bigl( … \bigr)（括号不再跟着整个分数长高），里面的分数也算顶层。
    /// 带上下标的分数、\dfrac（明说要显示样式）、上下标和根号里的分数不切；有 \begin、\displaystyle 的整条不切
    static func splitAtFractions(_ tex: String) -> [Part]? {
        guard tex.contains("frac") || tex.contains("binom"), !tex.contains("\\begin"), !tex.contains("\\displaystyle") else { return nil }
        guard var items = topLevel(Array(tex)) else { return nil }
        // \left … \right 里有分数的拆开
        var expanded: [Item] = []
        for item in items {
            if case .group(let open, let body, let close, let scripts) = item.kind, let inner = topLevel(Array(body)),
               inner.contains(where: { $0.kind == .fraction }), !body.contains("\\left") {
                if !open.isEmpty { expanded.append(Item(kind: .open, tex: "\\bigl" + open)) }
                expanded += inner
                if !close.isEmpty || !scripts.isEmpty { expanded.append(Item(kind: .close, tex: (close.isEmpty ? "{}" : "\\bigr" + close) + scripts)) }
            } else {
                expanded.append(item)
            }
        }
        items = expanded
        guard items.contains(where: { $0.kind == .fraction }) else { return nil }

        var parts: [Part] = []
        var run: [Item] = []
        var afterFraction = false
        /// 这一段末尾的二元运算符其实是一元的：它是整条的第一个，或者前面也是运算符、开括号、标点
        func lastIsUnary() -> Bool {
            guard let last = run.last, last.role == .bin else { return false }
            let before = run.dropLast().last { $0.role != .space }
            guard let before else { return !afterFraction }
            return [.bin, .rel, .open, .punct, .op].contains(before.role)
        }
        func flushRun(beforeFraction: Bool) {
            let significant = run.filter { $0.role != .space }
            guard !significant.isEmpty else { run.removeAll(); return }
            var gap: CGFloat = 0
            var padLeft = false
            if afterFraction {
                let first = run.first { $0.role != .space }!.role
                gap = first.spaceAfterInner
                padLeft = first == .bin
            }
            var padRight = false
            if beforeFraction, let last = run.last(where: { $0.role != .space }) {
                padRight = last.role == .bin && !lastIsUnary()
            }
            let tex = run.map(\.tex).joined().trimmingCharacters(in: .whitespaces)
            parts.append(Part(kind: .text(padLeft: padLeft, padRight: padRight), tex: tex, gapBefore: gap))
            run.removeAll()
        }
        for item in items {
            guard item.kind == .fraction else { run.append(item); continue }
            let left: Role
            if let last = run.last(where: { $0.role != .space }) {
                left = last.role == .bin && lastIsUnary() ? .ord : last.role
            } else if run.contains(where: { $0.role == .space }) {
                left = .space
            } else {
                left = afterFraction ? .inner : .none
            }
            flushRun(beforeFraction: true)
            parts.append(Part(kind: .fraction, tex: item.tex, gapBefore: left.spaceBeforeInner))
            afterFraction = true
        }
        flushRun(beforeFraction: false)
        return parts
    }

    /// 段和分数挨着的那一边是什么（TeX 的原子类别）
    enum Role { case ord, op, bin, rel, open, close, punct, inner, space, none

        /// 它在分数前面时中间补几 mu（TeX 的 Inner 列：Ord、Op、Close、Punct、Inner 细空 3，Rel 粗空 5；
        /// Bin 垫了「0」排、它后面的中空已经在段里了）
        var spaceBeforeInner: CGFloat {
            switch self {
            case .ord, .op, .close, .punct, .inner: return 3
            case .rel: return 5
            case .bin, .open, .space, .none: return 0
            }
        }

        /// 它在分数后面时中间补几 mu（TeX 的 Inner 行：Ord、Op、Open、Punct、Inner 细空 3，Rel 粗空 5）
        var spaceAfterInner: CGFloat {
            switch self {
            case .ord, .op, .open, .punct, .inner: return 3
            case .rel: return 5
            case .bin, .close, .space, .none: return 0
            }
        }
    }

    struct Item: Equatable {
        enum Kind: Equatable {
            case fraction
            case other
            case open
            case close
            /// \left 开 … \right 关 上下标
            case group(open: String, body: String, close: String, scripts: String)
        }
        let kind: Kind
        let tex: String

        /// 它在分数旁边算哪一类
        var role: Role {
            switch kind {
            case .fraction, .group: return .inner
            case .open: return .open
            case .close: return .close
            case .other: return TeXTweaks.role(of: tex)
            }
        }
    }

    static let binaryCommands: Set<String> = ["pm", "mp", "times", "cdot", "div", "ast", "star", "circ", "bullet", "oplus", "otimes",
                                              "cup", "cap", "setminus", "wedge", "vee", "land", "lor"]
    static let relationCommands: Set<String> = ["le", "leq", "ge", "geq", "ne", "neq", "approx", "equiv", "sim", "simeq", "cong",
                                                "propto", "to", "rightarrow", "leftarrow", "Rightarrow", "Leftarrow", "leftrightarrow",
                                                "Leftrightarrow", "mapsto", "in", "notin", "ni", "subset", "subseteq", "supset",
                                                "supseteq", "ll", "gg", "mid", "parallel", "perp", "implies", "iff", "gets", "lt", "gt"]
    static let spaceCommands: Set<String> = ["", "quad", "qquad", "hspace"]

    static func role(of tex: String) -> Role {
        let t = tex.trimmingCharacters(in: .whitespaces)
        guard let c = t.first else { return .space }
        if c == "\\" {
            let s = Array(t)
            guard let (name, end) = command(s, at: 0) else { return .ord }
            if name.isEmpty {
                let symbol = end - 1 < s.count ? s[end - 1] : " "
                if ",;:! ".contains(symbol) { return .space }
                if symbol == "{" { return .open }
                if symbol == "}" { return .close }
                return .ord
            }
            if binaryCommands.contains(name) { return .bin }
            if relationCommands.contains(name) { return .rel }
            if spaceCommands.contains(name) { return .space }
            if operatorNames.contains(name) || bigOperators[name] != nil { return .op }
            if ["langle", "lfloor", "lceil", "lbrace", "lvert", "lVert"].contains(name) { return .open }
            if ["rangle", "rfloor", "rceil", "rbrace", "rvert", "rVert"].contains(name) { return .close }
            return .ord
        }
        if "+-*".contains(c) { return .bin }
        if "=<>:".contains(c) { return .rel }
        if "([".contains(c) { return .open }
        if ")]".contains(c) { return .close }
        if ",;".contains(c) { return .punct }
        if c == "~" { return .space }
        return .ord
    }

    /// 顶层（括号外、\left…\right 外）切成一样一样：分数、\left…\right 一组、上下标连着它的参数、命令、字。认不出结构返回 nil
    static func topLevel(_ s: [Character]) -> [Item]? {
        var items: [Item] = []
        var i = 0
        /// 上一样是要带参数的命令（\sqrt、\mathbf…）：后面紧跟的分数是它的参数，不切
        var takesArgument = false
        while i < s.count {
            let c = s[i]
            if c == " " {
                items.append(Item(kind: .other, tex: " "))
                i += 1
                continue
            }
            if c == "{" {
                let end = argumentEnd(s, from: i)
                items.append(Item(kind: .other, tex: String(s[i..<end])))
                i = end
                takesArgument = false
                continue
            }
            if c == "^" || c == "_" {
                let end = argumentEnd(s, from: i + 1)
                // 上下标接在前一样后面，不单独算一样
                let script = String(s[i..<end])
                if let last = items.last, last.kind != .other || last.tex != " " {
                    items[items.count - 1] = Item(kind: last.kind == .fraction ? .other : last.kind == .close ? .close : .other, tex: last.tex + script)
                } else {
                    items.append(Item(kind: .other, tex: script))
                }
                i = end
                takesArgument = false
                continue
            }
            guard c == "\\", let (name, end) = command(s, at: i) else {
                items.append(Item(kind: .other, tex: String(c)))
                i += 1
                takesArgument = false
                continue
            }
            switch name {
            case "frac", "tfrac", "binom":
                let numEnd = argumentEnd(s, from: end)
                let denEnd = argumentEnd(s, from: numEnd)
                guard denEnd > numEnd, numEnd > end else { return nil }
                items.append(Item(kind: takesArgument ? .other : .fraction, tex: String(s[i..<denEnd])))
                i = denEnd
            case "left":
                guard let (open, openEnd) = delimiter(s, from: end), let (bodyEnd, rightEnd) = matchingRight(s, from: openEnd),
                      let (close, closeEnd) = delimiter(s, from: rightEnd) else { return nil }
                let scriptsEnd = self.scriptsEnd(s, from: closeEnd)
                items.append(Item(kind: .group(open: open, body: String(s[openEnd..<bodyEnd]), close: close,
                                               scripts: String(s[closeEnd..<scriptsEnd]).trimmingCharacters(in: .whitespaces)),
                                  tex: String(s[i..<scriptsEnd])))
                i = scriptsEnd
            default:
                items.append(Item(kind: .other, tex: String(s[i..<end])))
                i = end
                takesArgument = argumentCommands.contains(name)
                continue
            }
            takesArgument = false
        }
        return items
    }

    static let argumentCommands: Set<String> = ["sqrt", "mathrm", "mathbf", "mathit", "mathsf", "mathtt", "mathcal", "mathbb", "mathfrak",
                                                "boldsymbol", "bm", "text", "vec", "hat", "bar", "tilde", "dot", "ddot", "widehat",
                                                "widetilde", "overline", "underline", "operatorname", "overset", "underset", "stackrel",
                                                "frac", "dfrac", "tfrac", "cfrac", "binom", "color", "textcolor", "boxed"]

    // MARK: - 读源码的小工具

    /// s[i] 是反斜杠：命令名（字母）和它后面的位置；不是字母的（\\、\,、\{）名字是空、长度 2
    static func command(_ s: [Character], at i: Int) -> (String, Int)? {
        guard i < s.count, s[i] == "\\" else { return nil }
        var j = i + 1
        var name = ""
        while j < s.count, s[j].isLetter, s[j].isASCII { name.append(s[j]); j += 1 }
        if name.isEmpty { return ("", min(i + 2, s.count)) }
        return (name, j)
    }

    static func skipSpaces(_ s: [Character], from i: Int) -> Int {
        var j = i
        while j < s.count, s[j] == " " || s[j] == "\n" { j += 1 }
        return j
    }

    /// 一个参数（{…} 一组、一个命令、一个字）结束的位置
    static func argumentEnd(_ s: [Character], from i: Int) -> Int {
        let j = skipSpaces(s, from: i)
        guard j < s.count else { return j }
        if s[j] == "{" {
            var depth = 0
            var k = j
            while k < s.count {
                if s[k] == "\\" { k += 2; continue }
                if s[k] == "{" { depth += 1 } else if s[k] == "}" { depth -= 1; if depth == 0 { return k + 1 } }
                k += 1
            }
            return s.count
        }
        if s[j] == "\\", let (_, end) = command(s, at: j) { return end }
        return j + 1
    }

    /// 跳过 \limits、\nolimits 和上下标（可以有好几个）
    static func scriptsEnd(_ s: [Character], from i: Int) -> Int {
        var j = i
        while true {
            let k = skipSpaces(s, from: j)
            if k < s.count, s[k] == "^" || s[k] == "_" { j = argumentEnd(s, from: k + 1); continue }
            if let (name, end) = command(s, at: k), name == "limits" || name == "nolimits" { j = end; continue }
            return j
        }
    }

    /// \left、\right 后面的定界符：一个字或者一个命令（\{、\langle）
    static func delimiter(_ s: [Character], from i: Int) -> (String, Int)? {
        let j = skipSpaces(s, from: i)
        guard j < s.count else { return nil }
        if s[j] == "\\", let (_, end) = command(s, at: j) { return (String(s[j..<end]), end) }
        return (s[j] == "." ? "" : String(s[j]), j + 1)
    }

    /// 和 \left 配对的 \right：返回 \right 开头的位置和它后面的位置
    static func matchingRight(_ s: [Character], from i: Int) -> (Int, Int)? {
        var depth = 1
        var j = i
        while j < s.count {
            if s[j] == "\\", let (name, end) = command(s, at: j) {
                if name == "left" { depth += 1 } else if name == "right" {
                    depth -= 1
                    if depth == 0 { return (j, end) }
                }
                j = end
                continue
            }
            j += 1
        }
        return nil
    }
}
